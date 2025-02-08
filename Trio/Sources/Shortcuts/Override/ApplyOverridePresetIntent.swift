import AppIntents
import Foundation

struct ApplyOverridePresetIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Aktivera en override", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Aktivera en override", table: "ShortcutsDetail"))

    @Parameter(
        title: LocalizedStringResource("Override", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Val av override", table: "ShortcutsDetail")
    ) var preset: OverridePreset?

    @Parameter(
        title: LocalizedStringResource("Bekräfta före tillämpning", table: "ShortcutsDetail"),
        description: LocalizedStringResource("Om aktiverad måste du bekräfta innan override tillämpas", table: "ShortcutsDetail"),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyOverridePresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Tillämpa override \(\.$preset)", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Tillämpa override \(\.$preset) omedelbart", table: "ShortcutsDetail") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let presetToApply: OverridePreset
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: await OverridePresetsIntentRequest().fetchAndProcessOverrides(),
                    dialog: IntentDialog(LocalizedStringResource("Välj override", table: "ShortcutsDetail"))

                )
            }

            let displayName: String = presetToApply.name
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(
                        dialog: IntentDialog(LocalizedStringResource(
                            "Bekräfta för att tillämpa override '\(displayName)'", table: "ShortcutsDetail"
                        ))
                    )
                )
            }

            if await OverridePresetsIntentRequest().enactOverride(presetToApply) {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Override '\(presetToApply.name)' tillämpad", table: "ShortcutsDetail"
                        )
                    )
                )
            } else {
                return .result(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Misslyckades med att tillämpa override '\(presetToApply.name)'", table: "ShortcutsDetail"
                        )
                    )
                )
            }

        } catch {
            throw error
        }
    }
}
