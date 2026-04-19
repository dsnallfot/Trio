import CoreData
import Foundation
import UIKit

extension TrioRemoteControl {
    @MainActor internal func handleCancelOverrideCommand(_ pushMessage: PushMessage) async {
        await disableAllActiveOverrides(createOverrideRunEntry: true, shouldStartBackgroundTask: true)

        debug(
            .remoteControl,
            "Remote Override behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )

        guard settings.settings.notificationsRemote else { return }

        var notificationBody = "Pågående override avbröts.\n"
        notificationBody += "Inlagt av: \(pushMessage.user)\n"
        // Convert timestamp to HH:mm:ss format
        let date = Date(timeIntervalSince1970: pushMessage.timestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let formattedTime = dateFormatter.string(from: date)
        notificationBody += "Tid: \(formattedTime)\n"

        // Trim trailing newline, if present
        notificationBody = notificationBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        notificationManager.notifyTrioRemoteControl(
            title: "Remote Override",
            body: notificationBody
        )
    }

    @MainActor internal func handleStartOverrideCommand(_ pushMessage: PushMessage) async {
        guard let overrideName = pushMessage.overrideName, !overrideName.isEmpty else {
            await logError("Kommandot avvisades: override-namn saknas.", pushMessage: pushMessage)
            return
        }

        let presetIDs = await overrideStorage.fetchForOverridePresets()

        let presets = presetIDs.compactMap { id in
            try? viewContext.existingObject(with: id) as? OverrideStored
        }

        if let preset = presets.first(where: { $0.name == overrideName }) {
            await enactOverridePreset(presetObjectID: preset.objectID, pushMessage: pushMessage)
        } else {
            await logError("Kommandot avvisades: override '\(overrideName)' hittades inte.", pushMessage: pushMessage)
        }

        /*
         if let preset = presets.first(where: { $0.name == overrideName }) {
             await enactOverridePreset(preset: preset, pushMessage: pushMessage)
         } else {
             await logError("Kommandot avvisades: override '\(overrideName)' hittades inte.", pushMessage: pushMessage)
         }
         */
    }

    @MainActor private func enactOverridePreset(presetObjectID: NSManagedObjectID, pushMessage: PushMessage) async {
        debug(.remoteControl, "🛑 Starting enactment of override for objectID: \(presetObjectID)")

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Remote Override Upload") {
            guard backgroundTaskID != .invalid else { return }
            Task {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            backgroundTaskID = .invalid
        }

        func endBackgroundTask() {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                debug(.remoteControl, "✅ Successfully ended remote override background task: \(backgroundTaskID)")
                backgroundTaskID = .invalid
            }
        }

        defer {
            endBackgroundTask()
        }

        // Step 1: Disable all active overrides first, creating override run entries just like the shortcuts flow.
        await disableAllActiveOverrides(createOverrideRunEntry: true, shouldStartBackgroundTask: false)
        debug(.remoteControl, "✅ All previous overrides disabled. Proceeding to enact new override.")

        // Step 2: Fetch a fresh instance of the exact preset using its objectID.
        debug(.remoteControl, "🔍 Fetching preset with objectID: \(presetObjectID)")

        guard let refreshedPreset = await viewContext.perform({
            try? self.viewContext.existingObject(with: presetObjectID) as? OverrideStored
        }) else {
            debug(.remoteControl, "❌ CRITICAL: Failed to fetch preset for objectID \(presetObjectID) after disabling overrides.")
            return
        }

        let overrideName = refreshedPreset.name ?? ""
        debug(.remoteControl, "✅ Successfully fetched preset: \(overrideName)")

        // Step 3: Enable override.
        refreshedPreset.enabled = true
        refreshedPreset.date = Date()
        refreshedPreset.enteredBy = "Trio (\(pushMessage.user))"
        refreshedPreset.isUploadedToNS = false

        do {
            if viewContext.hasChanges {
                try viewContext.save()
                debug(.remoteControl, "✅ Override \(refreshedPreset.name ?? "Unnamed") successfully saved.")

                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                debug(.remoteControl, "⌛ Waiting for didUpdateOverrideConfiguration after remote override save...")
                await awaitNotification(.didUpdateOverrideConfiguration)
                debug(.remoteControl, "✅ Notification received. Override is now active.")

                guard settings.settings.notificationsRemote else { return }

                var notificationBody = "\(pushMessage.overrideName ?? "Anpassad override") aktiverades\n"
                notificationBody += "Inlagt av: \(pushMessage.user)\n"
                let date = Date(timeIntervalSince1970: pushMessage.timestamp)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH:mm:ss"
                let formattedTime = dateFormatter.string(from: date)
                notificationBody += "Tid: \(formattedTime)\n"
                notificationBody = notificationBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                notificationManager.notifyTrioRemoteControl(
                    title: "Remote Override",
                    body: notificationBody
                )
            } else {
                debug(.remoteControl, "⚠️ No changes detected in Core Data after enabling preset '\(overrideName)'.")
                debug(
                    .remoteControl,
                    "Preset state - enabled: \(refreshedPreset.enabled), date: \(refreshedPreset.date?.description ?? "nil")"
                )
            }
        } catch {
            debug(.remoteControl, "❌ Failed to save override preset '\(overrideName)': \(error.localizedDescription)")
        }
    }

    @MainActor private func disableAllActiveOverrides(
        createOverrideRunEntry: Bool,
        shouldStartBackgroundTask: Bool = true
    ) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        if shouldStartBackgroundTask {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Remote Override Cancel") {
                guard backgroundTaskID != .invalid else { return }
                Task {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        func endBackgroundTask() {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                debug(.remoteControl, "✅ Successfully ended remote override cancel background task: \(backgroundTaskID)")
                backgroundTaskID = .invalid
            }
        }

        defer {
            endBackgroundTask()
        }

        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)

        do {
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? OverrideStored
            }

            guard !results.isEmpty else {
                debug(.remoteControl, "ℹ️ No active overrides found to disable")
                return
            }

            debug(.remoteControl, "🛑 Disabling \(results.count) active override(s)...")

            for overrideToCancel in results {
                if createOverrideRunEntry, let startDate = overrideToCancel.date {
                    let newOverrideRunStored = OverrideRunStored(context: viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = overrideToCancel.name
                    newOverrideRunStored.enteredBy = overrideToCancel.enteredBy
                    newOverrideRunStored.startDate = startDate

                    let endDate: Date
                    if !overrideToCancel.indefinite, let durationNumber = overrideToCancel.duration {
                        let plannedEndDate = startDate.addingTimeInterval(TimeInterval(truncating: durationNumber) * 60)
                        endDate = Date() > plannedEndDate ? plannedEndDate : Date()
                    } else {
                        endDate = Date()
                    }

                    newOverrideRunStored.endDate = endDate
                    newOverrideRunStored.target = NSDecimalNumber(
                        decimal: overrideStorage.calculateTarget(override: overrideToCancel)
                    )
                    newOverrideRunStored.override = overrideToCancel
                    newOverrideRunStored.isUploadedToNS = false

                    debug(
                        .remoteControl,
                        "Created override run record for \(overrideToCancel.name ?? "Unnamed") with endDate \(endDate)"
                    )
                }

                overrideToCancel.enabled = false
                overrideToCancel.isUploadedToNS = false

                let plannedEndTime = overrideToCancel.date?
                    .addingTimeInterval(TimeInterval(truncating: overrideToCancel.duration ?? 0) * 60)
                debug(
                    .remoteControl,
                    "Disabling override: \(overrideToCancel.name ?? "Unnamed") with planned end time: \(plannedEndTime?.description ?? "Unknown")"
                )
            }

            if viewContext.hasChanges {
                try viewContext.save()
                debug(.remoteControl, "✅ Overrides successfully disabled and saved.")
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)

                debug(.remoteControl, "⌛ Waiting for didUpdateOverrideConfiguration after disabling overrides...")
                await awaitNotification(.didUpdateOverrideConfiguration)
                debug(.remoteControl, "✅ Disable notification received, continuing...")
            } else {
                debug(.remoteControl, "⚠️ No changes detected while disabling overrides. Maybe already disabled?")
            }
        } catch {
            debug(.remoteControl, "❌ Failed to disable active overrides: \(error.localizedDescription)")
        }
    }
}

extension OverrideStorage {
    func fetchPresetWithName(_ name: String?, in context: NSManagedObjectContext) -> OverrideStored? {
        guard let name = name else { return nil }

        let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)
            return results.first
        } catch {
            debugPrint("❌ Failed to fetch override with name '\(name)': \(error.localizedDescription)")
            return nil
        }
    }
}
