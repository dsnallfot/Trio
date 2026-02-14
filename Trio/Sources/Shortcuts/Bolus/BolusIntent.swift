import AppIntents
import CoreData
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct BolusIntent: AppIntent {
    static var title = LocalizedStringResource("Ge bolus", table: "ShortcutsDetail")
    static var description = IntentDescription(.init("Tillåt att bolus skickas till appen", table: "ShortcutsDetail"))

    @Parameter(
        title: LocalizedStringResource("Mängd", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Bolusmängd i E", table: "ShortcutsDetail"),
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog(LocalizedStringResource("Bolusmängd (enheter insulin)?", table: "ShortcutsDetail"))
    ) var bolusQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Inlagt av", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Valfri text att bifoga med bolusen", table: "ShortcutsDetail"),
        default: ""
    ) var inlagtAv: String

    @Parameter(
        title: LocalizedStringResource("Bekräfta innan dosering", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Om aktiverad, så måste du konfirmera innan dosering.", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Ger \(\.$bolusQuantity) E, anteckning: \(\.$inlagtAv)", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Omedelbar dosering \(\.$bolusQuantity) E, anteckning: \(\.$inlagtAv)", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let amount: Double = bolusQuantity
            let bolusFormatted = amount.formatted()

            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(
                            LocalizedStringResource(
                                "Vill du ge \(bolusFormatted) E insulin?",
                                table: "ShortcutsDetail"
                            )
                        )
                    )
                )
            }

            // Set pending note
            if !inlagtAv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateLatestBolusNote(with: inlagtAv)
            } else {
                updateLatestBolusNote(with: "✨")
            }

            // Short delay to ensure note is set
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Enact bolus
            let finalBolusDisplay = try await BolusIntentRequest().bolus(amount)

            // 1) Upload pump history
            // 2) Trigger basal sync
            // 3) Upload fresh device status
            do {
                let resolver = TrioApp.resolver

                let nightscoutManager: NightscoutManager? = resolver.resolve(NightscoutManager.self)
                let apsManager: APSManager? = resolver.resolve(APSManager.self)

                if let nightscoutManager {
                    debugPrint("Uploading pump history to Nightscout after bolus...")
                    await nightscoutManager.uploadPumpHistory()
                    debugPrint("Pump history upload to Nightscout finished.")
                } else {
                    debugPrint("NightscoutManager not available; skipping pump history upload.")
                }

                if let apsManager {
                    debugPrint("Triggering basal sync after pump history upload...")
                    await apsManager.determineBasalSync()
                    debugPrint("Basal sync triggered after pump history upload.")

                    if let nightscoutManager {
                        debugPrint("Uploading deviceStatus to Nightscout after basal sync...")
                        await nightscoutManager.uploadDeviceStatus()
                        debugPrint("deviceStatus upload to Nightscout finished.")
                    } else {
                        debugPrint("NightscoutManager not available; skipping deviceStatus upload.")
                    }
                } else {
                    debugPrint("APSManager not available; skipping basal sync and deviceStatus upload.")
                }
            }

            return .result(dialog: IntentDialog(finalBolusDisplay))

        } catch {
            throw error
        }
    }

    func updateLatestBolusNote(with noteText: String) {
        TrioRemoteControl.pendingRemoteBolusNote = (note: noteText, timestamp: Date())
        print("Shortcuts: Set pendingRemoteBolusNote = \(noteText) at \(Date())")
    }
}
