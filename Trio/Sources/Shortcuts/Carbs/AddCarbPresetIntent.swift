import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct AddCarbPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Registrera måltid"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Tillåt att måltid registreras i Trio.")

    init() {
        dateAdded = Date()
    }

    @Parameter(
        title: "Mängd kh",
        description: "Mängd kh i gram",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog("Vad är nummervärdet kh att lägga till")
    ) var carbQuantity: Double?

    @Parameter(
        title: "Mängd fett",
        description: "Mängd fett i g",
        default: 0.0,
        inclusiveRange: (0, 200)
    ) var fatQuantity: Double

    @Parameter(
        title: "Mängd protein",
        description: "Mängd protein i g",
        default: 0.0,
        inclusiveRange: (0, 200)
    ) var proteinQuantity: Double

    @Parameter(
        title: "Tid",
        description: "Tid för måltid"
    ) var dateAdded: Date

    @Parameter(
        title: "Noteringar",
        description: "Emoji eller kort text"
    ) var note: String?

    @Parameter(
        title: "Inlagt av",
        description: "Ange namn"
    ) var enteredBy: String?

    @Parameter(
        title: "Bekräfta innan registrering",
        description: "Om aktiverad, så måste du konfirmera innan registrering.",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Registrerar \(\.$carbQuantity) vid \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
                \.$enteredBy
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Omedelbar registrering \(\.$carbQuantity) vid \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
                \.$enteredBy
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let quantityCarbs: Double
            if let cq = carbQuantity {
                quantityCarbs = cq
            } else {
                quantityCarbs = try await $carbQuantity.requestValue("Hur många g kh?")
            }

            let quantityCarbsName = quantityCarbs.toString()
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Vill du vill registrera \(quantityCarbsName) g kh?")
                )
            }

            let finalQuantityCarbsDisplay = try await CarbPresetIntentRequest().addCarbs(
                quantityCarbs,
                fatQuantity,
                proteinQuantity,
                dateAdded,
                note,
                enteredBy
            )
            // 1) Upload newly registered carbs directly to Nightscout.
            // 2) Trigger a basal sync so calculations (COB/IOB/etc) update immediately.
            // 3) Upload device status after sync so Nightscout gets fresh deviceStatus.
            do {
                let resolver = TrioApp.resolver

                let nightscoutManager: NightscoutManager? = resolver.resolve(NightscoutManager.self)
                let apsManager: APSManager? = resolver.resolve(APSManager.self)

                if let nightscoutManager {
                    debugPrint("Uploading carbs to Nightscout after addCarbs...")
                    await nightscoutManager.uploadCarbs()
                    debugPrint("Carbs upload to Nightscout finished.")
                } else {
                    debugPrint("NightscoutManager not available; skipping carbs upload.")
                }

                if let apsManager {
                    debugPrint("Triggering basal sync after carbs upload...")
                    await apsManager.determineBasalSync()
                    debugPrint("Basal sync triggered after carbs upload.")

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
            return .result(
                dialog: IntentDialog(stringLiteral: finalQuantityCarbsDisplay)
            )

        } catch {
            throw error
        }
    }
}
