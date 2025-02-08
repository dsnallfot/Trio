import AppIntents
import Foundation
import Intents
import Swinject

@available(iOS 16.0,*) struct BolusIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Ge bolus", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Tillåt att bolus skickas till appen", table: "ShortcutsDetail"))

    @Parameter(
        title: LocalizedStringResource("Mängd", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Bolusmängd i E", table: "ShortcutsDetail"),
        controlStyle: .field,
        /// The 200 upperBound does nothing here, the true max is set based on pump max
        /// An upperBound is specificed so that we can usethe lowerBound of 0, which ensures no negatives are allowed
        /// A preferred approach would be to just block negatives and not specify an upperBound here, since it is implemented elsewhere
        inclusiveRange: (lowerBound: 0, upperBound: 200),
        requestValueDialog: IntentDialog(LocalizedStringResource(
            "Bolusmängd (enheter insulin)?",
            table: "ShortcutsDetail"
        ))
    ) var bolusQuantity: Double

    @Parameter(
        title: LocalizedStringResource("Bekräfta innan dosering", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Om aktiverad, så måste du konfirmera innan dosering.", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Ger \(\.$bolusQuantity) E", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Omedelbar dosering \(\.$bolusQuantity) E", table: "ShortcutsDetail") {
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
                        dialog: IntentDialog(LocalizedStringResource(
                            "Vill du vill ge \(bolusFormatted) E insulin?",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            let finalBolusDisplay = try await BolusIntentRequest().bolus(amount)
            return .result(
                dialog: IntentDialog(finalBolusDisplay)
            )

        } catch {
            throw error
        }
    }
}
