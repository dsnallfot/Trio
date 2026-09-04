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

        let glucoseDate = Date(timeIntervalSince1970: pushMessage.timestamp)

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
}
