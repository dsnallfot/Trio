import AppIntents
import Foundation

struct CancelTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Avbryt ett tillfälligt mål."

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Avbryt tillfälligt mål.")

    @MainActor func perform() async throws -> some ProvidesDialog {
        await TempPresetsIntentRequest().cancelTempTarget()
        return .result(
            dialog: IntentDialog(stringLiteral: "Tillfälligt mål avbrutet")
        )
    }
}
