import AppIntents
import CoreData
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

            let finalBolusDisplay = try await BolusIntentRequest().bolus(amount)

            // Daniel: After the bolus is enacted, if the user entered some text under Inlagt av,
            // update the most recent bolus event with the note.
            if !inlagtAv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Schedule an asynchronous Core Data update.
                updateLatestBolusNote(with: inlagtAv)
            }

            return .result(
                dialog: IntentDialog(finalBolusDisplay)
            )
        } catch {
            throw error
        }
    }

    // Daniel: Hack to upload enteredBy with for instance Mamma or Pappa when shortcuts used for bolus
    func updateLatestBolusNote(with noteText: String) {
        let context = CoreDataStack.shared.newTaskContext()
        context.perform {
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            // Look for the most recent bolus (e.g. within the last 10 minutes).
            let twentyMinutesAgo = Date().addingTimeInterval(-10 * 60)
            fetchRequest.predicate = NSPredicate(
                format: "type == %@ AND timestamp >= %@",
                PumpEventStored.EventType.bolus.rawValue,
                twentyMinutesAgo as NSDate
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            fetchRequest.fetchLimit = 1
            do {
                let events = try context.fetch(fetchRequest)
                if let latestBolus = events.first {
                    latestBolus.note = "Trio(\(noteText))"
                    try context.save()
                }
            } catch {
                print("Error updating bolus note: \(error)")
            }
        }
    }
}
