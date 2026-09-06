import CoreData
import Foundation

extension TrioRemoteControl {
    @MainActor func handleGlucoseCommand(_ pushMessage: PushMessage) async {
        guard let glucose = pushMessage.glucose, glucose > 0 else {
            await logError(
                "Kommandot avvisades: blodsockervärde saknas eller är ogiltigt.",
                pushMessage: pushMessage
            )
            return
        }

        // Remote glucose is always sent from LoopFollow in mg/dL.
        let glucoseAsInt = NSDecimalNumber(decimal: glucose).intValue

        guard glucoseAsInt > 0 else {
            await logError(
                "Kommandot avvisades: blodsockervärdet kunde inte konverteras till ett giltigt värde.",
                pushMessage: pushMessage
            )
            return
        }

        let glucoseDate = Date(timeIntervalSince1970: pushMessage.scheduledTime ?? pushMessage.timestamp)

        // Wait for Core Data to finish saving before trying to upload
        // the new manual glucose to Nightscout.
        await glucoseStorage.addManualGlucose(
            glucose: glucoseAsInt,
            date: glucoseDate
        )

        // 1) Upload newly registered manual glucose directly to Nightscout.
        // 2) Trigger a basal sync so calculations (IOB/COB/etc) update immediately.
        // 3) Upload device status after sync so Nightscout gets fresh deviceStatus.

        let resolver = TrioApp.resolver

        let nightscoutManager: NightscoutManager? =
            resolver.resolve(NightscoutManager.self)

        let apsManager: APSManager? =
            resolver.resolve(APSManager.self)

        if let nightscoutManager {
            debugPrint(
                "Uploading manual glucose to Nightscout after remote glucose command..."
            )

            await nightscoutManager.uploadManualGlucose()

            debugPrint(
                "Manual glucose upload to Nightscout finished."
            )
        } else {
            debugPrint(
                "NightscoutManager not available; skipping manual glucose upload."
            )
        }

        if let apsManager {
            debugPrint(
                "Triggering basal sync after remote glucose upload..."
            )

            await apsManager.determineBasalSync()

            debugPrint(
                "Basal sync triggered after remote glucose upload."
            )

            if let nightscoutManager {
                debugPrint(
                    "Uploading deviceStatus to Nightscout after basal sync..."
                )

                await nightscoutManager.uploadDeviceStatus()

                debugPrint(
                    "deviceStatus upload to Nightscout finished."
                )
            } else {
                debugPrint(
                    "NightscoutManager not available; skipping deviceStatus upload."
                )
            }
        } else {
            debugPrint(
                "APSManager not available; skipping basal sync and deviceStatus upload."
            )
        }

        debug(
            .remoteControl,
            "Remote blodsocker registrerades: \(glucoseAsInt) mg/dL. \(pushMessage.humanReadableDescription())"
        )

        guard settings.settings.notificationsRemote else { return }

        let displayValue: String
        let unit: String

        if settings.settings.units == .mmolL {
            let mmolValue = Double(glucoseAsInt) * 0.0555
            displayValue = String(format: "%.1f", mmolValue)
            unit = "mmol/L"
        } else {
            displayValue = String(glucoseAsInt)
            unit = "mg/dL"
        }

        notificationManager.notifyTrioRemoteControl(
            title: "Remote Blodsocker",
            body: "\(displayValue) \(unit) registrerades."
        )
    }

    @MainActor func handleDeleteGlucoseCommand(_ pushMessage: PushMessage) async {
        // timestamp is the command time; scheduled_time identifies the original fingerstick.
        let deletionTimestamp = pushMessage.scheduledTime ?? pushMessage.timestamp
        guard deletionTimestamp.isFinite, deletionTimestamp > 0 else {
            await logError("Kommandot avvisades: ogiltig tidsstämpel för blodsockerradering.", pushMessage: pushMessage)
            return
        }

        // Match one second to support timestamps without fractional seconds, without
        // accidentally selecting a different fingerstick later in the same minute.
        let startDate = Date(timeIntervalSince1970: floor(deletionTimestamp))
        let endDate = startDate.addingTimeInterval(1)
        let context = CoreDataStack.shared.newTaskContext()
        let matches: [(NSManagedObjectID, String?)]
        do {
            matches = try await context.perform {
                let request: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
                request.predicate = NSPredicate(
                    format: "isManual == YES AND date >= %@ AND date < %@",
                    startDate as NSDate,
                    endDate as NSDate
                )
                request.fetchLimit = 2
                return try context.fetch(request).map { ($0.objectID, $0.id?.uuidString) }
            }
        } catch {
            await logError(
                "Kommandot avvisades: kunde inte söka efter fingerstick att radera. \(error.localizedDescription)",
                pushMessage: pushMessage
            )
            return
        }

        guard matches.count == 1, let match = matches.first else {
            await logError(
                matches.isEmpty
                    ? "Kommandot avvisades: inget matchande fingerstick hittades för den angivna tiden."
                    : "Kommandot avvisades: flera fingerstick matchar den angivna tiden.",
                pushMessage: pushMessage
            )
            return
        }

        // Use the same service deletions as DataTable.StateModel.deleteGlucose.
        // Await them directly so they finish within the remote command's lifetime.
        let resolver = TrioApp.resolver
        if let id = match.1 {
            await nightscoutManager.deleteManualGlucose(withID: id)
            await nightscoutManager.deleteGlucose(withID: id)
            if let healthkitManager = resolver.resolve(HealthKitManager.self) {
                await healthkitManager.deleteGlucose(syncID: id)
            }
        }
        await glucoseStorage.deleteGlucose(match.0)

        if let apsManager = resolver.resolve(APSManager.self) {
            await apsManager.determineBasalSync()
            await nightscoutManager.uploadDeviceStatus()
        }

        debug(.remoteControl, "Remote blodsockerradering behandlades. \(pushMessage.humanReadableDescription())")
        guard settings.settings.notificationsRemote else { return }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        notificationManager.notifyTrioRemoteControl(
            title: "Remote Radera Blodsocker",
            body: "Fingerstick: \(formatter.string(from: startDate))\nRaderat av: \(pushMessage.user)"
        )
    }
}
