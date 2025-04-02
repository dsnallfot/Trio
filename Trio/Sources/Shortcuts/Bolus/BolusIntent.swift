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
                        dialog: IntentDialog(LocalizedStringResource(
                            "Vill du ge \(bolusFormatted) E insulin?",
                            table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            // Set the pending note first using the shared variable.
            if !inlagtAv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateLatestBolusNote(with: inlagtAv)
            } else {
                updateLatestBolusNote(with: "✨")
            }
            // Introduce a brief delay (e.g., 200 ms) to ensure the note is in place.
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Now enact the bolus.
            let finalBolusDisplay = try await BolusIntentRequest().bolus(amount)

            return .result(dialog: IntentDialog(finalBolusDisplay))
        } catch {
            throw error
        }
    }

    // This method now simply sets the shared pending note.
    func updateLatestBolusNote(with noteText: String) {
        TrioRemoteControl.pendingRemoteBolusNote = (note: noteText, timestamp: Date())
        print("Shortcuts: Set pendingRemoteBolusNote = \(noteText) at \(Date())")
    }
}
