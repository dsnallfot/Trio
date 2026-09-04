import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0, *) struct ManualGlucoseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrera blodsocker"

    static var description = IntentDescription(
        "Registrera ett manuellt blodsockervärde (fingerstick) i Trio."
    )

    init() {
        dateAdded = Date()
    }

    @Parameter(
        title: "Blodsocker",
        description: "Blodsockervärde i den enhet som Trio använder.",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 1, upperBound: 1000),
        requestValueDialog: IntentDialog("Vilket blodsockervärde vill du registrera?")
    ) var glucose: Double?

    @Parameter(
        title: "Tid",
        description: "Tid för blodsockermätningen"
    ) var dateAdded: Date

    @Parameter(
        title: "Bekräfta innan registrering",
        description: "Om aktiverad måste du bekräfta innan registrering.",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Registrerar blodsocker \(\.$glucose) vid \(\.$dateAdded)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Omedelbar registrering av blodsocker \(\.$glucose) vid \(\.$dateAdded)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        let quantityGlucose: Double

        if let value = glucose {
            quantityGlucose = value
        } else {
            quantityGlucose = try await $glucose.requestValue(
                "Vilket blodsockervärde vill du registrera?"
            )
        }

        guard quantityGlucose > 0 else {
            return .result(
                dialog: "Registrerar inte blodsocker i Trio"
            )
        }

        let request = ManualGlucoseIntentRequest()

        let displayValue = request.formatGlucoseValue(quantityGlucose)

        if confirmBeforeApplying {
            try await requestConfirmation(
                result: .result(
                    dialog: "Vill du registrera blodsocker på \(displayValue)?"
                )
            )
        }

        let resultDisplay = try await request.addManualGlucose(
            quantityGlucose,
            dateAdded
        )

        // 1) Upload newly registered manual glucose directly to Nightscout.
        // 2) Trigger a basal sync so calculations (COB/IOB/etc) update immediately.
        // 3) Upload device status after sync so Nightscout gets fresh deviceStatus.
        do {
            let resolver = TrioApp.resolver

            let nightscoutManager: NightscoutManager? =
                resolver.resolve(NightscoutManager.self)

            let apsManager: APSManager? =
                resolver.resolve(APSManager.self)

            if let nightscoutManager {
                debugPrint(
                    "Uploading manual glucose to Nightscout after addManualGlucose..."
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
                    "Triggering basal sync after manual glucose upload..."
                )

                await apsManager.determineBasalSync()

                debugPrint(
                    "Basal sync triggered after manual glucose upload."
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
        }

        return .result(
            dialog: IntentDialog(stringLiteral: resultDisplay)
        )
    }
}
