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
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Omedelbar registrering \(\.$carbQuantity) vid \(\.$dateAdded)") {
                \.$fatQuantity
                \.$proteinQuantity
                \.$note
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
                note
            )
            return .result(
                dialog: IntentDialog(stringLiteral: finalQuantityCarbsDisplay)
            )

        } catch {
            throw error
        }
    }
}
