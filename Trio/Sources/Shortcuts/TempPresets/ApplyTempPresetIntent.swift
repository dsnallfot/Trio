import AppIntents
import Foundation

struct ApplyTempPresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title: LocalizedStringResource = "Aktivera ett tillfälligt mål"

    // Description of the action in the Shortcuts app
    static var description = IntentDescription("Aktivera ett tillfälligt mål")

    @Parameter(title: "Förval") var preset: TempPreset?

    @Parameter(
        title: "Bekräfta innan aktivering",
        description: "Om aktiverad måste du bekräfta innan tillfälligt mål tillämpas",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyTempPresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Aktiverar \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Omedelbar aktivering av \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        })
    }

    private func decimalToTimeFormattedString(decimal: Decimal) -> String {
        let timeInterval = TimeInterval(decimal * 60) // seconds

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .brief // example: 1h 10 min

        return formatter.string(from: timeInterval) ?? ""
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let intentRequest = TempPresetsIntentRequest()
            let presetToApply: TempPreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchAndProcessTempTargets(),
                    dialog: "Select Temporary Target"
                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Confirm to apply Temporary Target '\(displayName)'")
                )
            }

            if await intentRequest.enactTempTarget(presetToApply) {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Temporary Target '\(presetToApply.name)' applied",
                            table: "ShortcutsDetail"
                        )
                    )
                )
            } else {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Temporary Target '\(presetToApply.name)' failed",
                            table: "ShortcutsDetail"
                        )
                    )
                )
            }
        } catch {
            throw error
        }
    }
}
