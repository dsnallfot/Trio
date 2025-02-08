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
        preset.enabled = true
        preset.date = Date()
        preset.isUploadedToNS = false

        await disableAllActiveOverrides(except: preset.objectID)

        do {
            if viewContext.hasChanges {
                try viewContext.save()

                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)

                debug(.remoteControl, "Remote Override behandlades framgångsrikt. \(pushMessage.humanReadableDescription())")

                var notificationBody = "\(pushMessage.overrideName) aktiverades\n"
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
        } catch {
            debug(.remoteControl, "Misslyckades med att aktivera override-presets: \(error.localizedDescription)")
        }
    }

    @MainActor private func disableAllActiveOverrides(except overrideID: NSManagedObjectID? = nil) async {
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit

        let didPostNotification = await viewContext.perform { () -> Bool in
            do {
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }

                guard !results.isEmpty else { return false }

                for canceledOverride in results where canceledOverride.enabled {
                    if let overrideID = overrideID, canceledOverride.objectID == overrideID {
                        continue
                    }

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

                if self.viewContext.hasChanges {
                    try self.viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                    return true
                } else {
                    return false
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Misslyckades med att avaktivera aktiva overrides med fel: \(error.localizedDescription)"
                )
                return false
            }
        }

        if didPostNotification {
            await awaitNotification(.didUpdateOverrideConfiguration)
        }
    }
}
