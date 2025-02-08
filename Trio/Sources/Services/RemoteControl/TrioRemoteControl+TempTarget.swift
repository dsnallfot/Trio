import CoreData
import Foundation

extension TrioRemoteControl {
    @MainActor func handleTempTargetCommand(_ pushMessage: PushMessage) async {
        guard let targetValue = pushMessage.target,
              let durationValue = pushMessage.duration
        else {
            await logError("Kommandot avvisades: data för temp target är ofullständig eller ogiltig.", pushMessage: pushMessage)
            return
        }

        let durationInMinutes = Int(durationValue)
        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)

        let tempTarget = TempTarget(
            name: TempTarget.custom,
            createdAt: pushMessageDate,
            targetTop: Decimal(targetValue),
            targetBottom: Decimal(targetValue),
            duration: Decimal(durationInMinutes),
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: true,
            halfBasalTarget: settings.preferences.halfBasalExerciseTarget
        )

        await tempTargetsStorage.storeTempTarget(tempTarget: tempTarget)
        tempTargetsStorage.saveTempTargetsToStorage([tempTarget])

        debug(
            .remoteControl,
            "Remote Temp Target behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )
        var notificationBody = "Temp target aktiverades: \(targetValue) i \(durationInMinutes) minuter.\n"
        notificationBody += "Inlagt av: \(pushMessage.user)\n"
        // Convert timestamp to HH:mm:ss format
        let date = Date(timeIntervalSince1970: pushMessage.timestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let formattedTime = dateFormatter.string(from: date)
        notificationBody += "Tid: \(formattedTime)\n"

        // Trim trailing newline, if present
        notificationBody = notificationBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // Send success notification
        notificationManager.notifyTrioRemoteControl(
            title: "Remote Temp Target",
            body: notificationBody
        )
    }

    @MainActor func cancelTempTarget(_ pushMessage: PushMessage) async {
        debug(.remoteControl, "Avbryter temp target.")

        await disableAllActiveTempTargets()

        debug(
            .remoteControl,
            "Remote Temp Target behandlades framgångsrikt. \(pushMessage.humanReadableDescription())"
        )
        var notificationBody = "Pågående temp target avbröts.\n"
        notificationBody += "Inlagt av: \(pushMessage.user)\n"
        // Convert timestamp to HH:mm:ss format
        let date = Date(timeIntervalSince1970: pushMessage.timestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let formattedTime = dateFormatter.string(from: date)
        notificationBody += "Tid: \(formattedTime)\n"

        // Trim trailing newline, if present
        notificationBody = notificationBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // Send success notification
        notificationManager.notifyTrioRemoteControl(
            title: "Remote Temp Target",
            body: notificationBody
        )
    }

    @MainActor func disableAllActiveTempTargets() async {
        let ids = await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)

        let didPostNotification = await viewContext.perform { () -> Bool in
            do {
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? TempTargetStored
                }

                guard !results.isEmpty else {
                    Task {
                        await self.logError("Kommandot avvisades: ingen aktiv temp target att avbryta.")
                    }
                    return false
                }

                for canceledTempTarget in results where canceledTempTarget.enabled {
                    let newTempTargetRunStored = TempTargetRunStored(context: self.viewContext)
                    newTempTargetRunStored.id = UUID()
                    newTempTargetRunStored.name = canceledTempTarget.name
                    newTempTargetRunStored.startDate = canceledTempTarget.date ?? .distantPast
                    newTempTargetRunStored.endDate = Date()
                    newTempTargetRunStored
                        .target = canceledTempTarget.target ?? 0
                    newTempTargetRunStored.tempTarget = canceledTempTarget
                    newTempTargetRunStored.isUploadedToNS = false

                    canceledTempTarget.enabled = false
                    canceledTempTarget.isUploadedToNS = false
                }

                if self.viewContext.hasChanges {
                    try self.viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)

                    // Update the storage so oref can pick up cancellation
                    self.tempTargetsStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date().addingTimeInterval(-1))])
                    return true
                } else {
                    return false
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active TempTargets with error: \(error.localizedDescription)"
                )
                return false
            }
        }

        if didPostNotification {
            await awaitNotification(.didUpdateTempTargetConfiguration)
        }
    }
}
