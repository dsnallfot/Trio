import CoreData
import Foundation

extension TrioRemoteControl {
    @MainActor internal func handleCancelOverrideCommand(_ pushMessage: PushMessage) async {
        await disableAllActiveOverrides()

        debug(
            .remoteControl,
            "Remote Override behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )
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
            await enactOverridePreset(preset: preset, pushMessage: pushMessage)
        } else {
            await logError("Kommandot avvisades: override '\(overrideName)' hittades inte.", pushMessage: pushMessage)
        }
    }

    @MainActor private func enactOverridePreset(preset: OverrideStored, pushMessage: PushMessage) async {
        debug(.remoteControl, "🛑 Starting enactment of override: \(preset.name ?? "Unnamed")")

        // Step 1: Disable all active overrides
        await disableAllActiveOverrides()
        debug(.remoteControl, "✅ All previous overrides disabled. Proceeding to enact new override.")

        // Step 2: Fetch a fresh instance of the preset using its name
        let overrideName = preset.name ?? ""
        debug(.remoteControl, "🔍 Fetching preset with name: \(overrideName)")

        guard let refreshedPreset = await viewContext.perform({
            self.overrideStorage.fetchPresetWithName(overrideName, in: self.viewContext)
        }) else {
            debug(.remoteControl, "❌ CRITICAL: Failed to fetch preset '\(overrideName)' after disabling overrides.")
            return
        }

        debug(.remoteControl, "✅ Successfully fetched preset: \(refreshedPreset.name ?? "Unnamed")")

        // Step 3: Ensure the preset is in a clean state and enable it
        await viewContext.perform {
            refreshedPreset.enabled = true
            refreshedPreset.date = Date()
            refreshedPreset.isUploadedToNS = false
            debug(
                .remoteControl,
                "🚀 Preset \(refreshedPreset.name ?? "Unnamed") marked as enabled with date: \(refreshedPreset.date?.description ?? "nil")"
            )
        }

        // Step 4: Save and notify
        do {
            debug(.remoteControl, "🔎 Checking for Core Data changes: \(viewContext.hasChanges ? "Yes" : "No")")
            if viewContext.hasChanges {
                debug(.remoteControl, "💾 Saving new override state to Core Data...")
                try viewContext.save()
                debug(.remoteControl, "✅ Override \(refreshedPreset.name ?? "Unnamed") successfully saved.")

                // Notify system that override state has changed
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)
                debug(.remoteControl, "✅ Notification received. Override is now active.")

                var notificationBody = "\(pushMessage.overrideName ?? "Anpassad override") aktiverades\n"
                notificationBody += "Inlagt av: \(pushMessage.user)\n"
                let date = Date(timeIntervalSince1970: pushMessage.timestamp)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH:mm:ss"
                let formattedTime = dateFormatter.string(from: date)
                notificationBody += "Tid: \(formattedTime)\n"
                notificationBody = notificationBody.trimmingCharacters(in: .whitespacesAndNewlines)

                notificationManager.notifyTrioRemoteControl(
                    title: "Remote Override",
                    body: notificationBody
                )
            } else {
                debug(
                    .remoteControl,
                    "⚠️ No changes detected in Core Data after enabling preset '\(overrideName)'. Investigating state..."
                )
                debug(
                    .remoteControl,
                    "Preset state - enabled: \(refreshedPreset.enabled), date: \(refreshedPreset.date?.description ?? "nil")"
                )
            }
        } catch {
            debug(.remoteControl, "❌ Failed to save override preset '\(overrideName)': \(error.localizedDescription)")
        }
    }

    @MainActor private func disableAllActiveOverrides(keepOverrideWithName _: String? = nil) async {
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // Fetch all

        let didPostNotification = await viewContext.perform { () -> Bool in
            do {
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }

                guard !results.isEmpty else {
                    debug(.remoteControl, "ℹ️ No active overrides found to disable.")
                    return false
                }

                debug(.remoteControl, "🛑 Disabling \(results.count) active override(s)...")

                for canceledOverride in results where canceledOverride.enabled {
                    debug(.remoteControl, "🚫 Cancelling override: \(canceledOverride.name ?? "Unnamed")")

                    let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = canceledOverride.name
                    newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored.target = NSDecimalNumber(
                        decimal: self.overrideStorage.calculateTarget(override: canceledOverride)
                    )
                    newOverrideRunStored.override = canceledOverride
                    newOverrideRunStored.isUploadedToNS = false

                    canceledOverride.enabled = false
                    canceledOverride.isUploadedToNS = false
                }

                debug(.remoteControl, "💾 Checking if Core Data has changes before saving...")
                if self.viewContext.hasChanges {
                    try self.viewContext.save()
                    debug(.remoteControl, "✅ Overrides successfully disabled.")
                    Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                    return true
                } else {
                    debug(.remoteControl, "⚠️ No changes detected while disabling overrides. Maybe already disabled?")
                    return false
                }
            } catch {
                debug(.remoteControl, "❌ Failed to disable active overrides: \(error.localizedDescription)")
                return false
            }
        }

        if didPostNotification {
            await awaitNotification(.didUpdateOverrideConfiguration)
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
