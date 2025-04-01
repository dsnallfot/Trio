import AppIntents
import Foundation
import SwiftUI

// A new intent request to access our injected services
final class ToggleClosedLoopIntentRequest: BaseIntentsRequest {}

@available(iOS 16.0, *) struct ToggleClosedLoopIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Closed Loop"
    static var description = IntentDescription(
        "Toggles the closed loop setting in the app, or sets it explicitly if a value is provided."
    )

    // Optional parameter: if provided, sets the setting to that value; otherwise, toggles it.
    @Parameter(
        title: "Enable",
        description: "Optional value: true to enable, false to disable. If omitted, the setting will be toggled."
    ) var enable: Bool?

    @Parameter(
        title: LocalizedStringResource("Bekräfta innan du sluter/öppnar loop", table: "ShortcutsDetail"),
        description: LocalizedStringResource(
            "Om aktiverad, så måste du bekräfta innan du sluter/öppnar loop",
            table: "ShortcutsDetail"
        ),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Sluten loop \(\.$enable)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Sluten loop \(\.$enable)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ReturnsValue<ToggleResult> & ShowsSnippetView {
        // Create an instance of our intent request so we can access the SettingsManager.
        let request = ToggleClosedLoopIntentRequest()

        // Get the current closedLoop value from your settings.
        let currentValue = request.settingsManager.settings.closedLoop

        // Determine the new value: if 'enable' is provided, use it; otherwise, invert the current value.
        let newValue = enable ?? !currentValue

        // If confirmation is enabled, present a confirmation dialog.
        if confirmBeforeApplying {
            // Choose an appropriate message based on the new state.
            let actionText = newValue
                ? LocalizedStringResource("Vill du aktivera loop?", table: "ShortcutsDetail")
                : LocalizedStringResource("Vill du inaktivera loop?", table: "ShortcutsDetail")
            try await requestConfirmation(
                result: .result(
                    dialog: IntentDialog(actionText)
                )
            )
        }

        // Update the setting.
        request.settingsManager.settings.closedLoop = newValue

        // Return the result.
        return .result(value: ToggleResult(status: newValue))
    }
}

// MARK: - Default Query

// Define an empty query that explicitly works with ToggleResult.
struct EmptyToggleQuery: EntityQuery {
    // Explicitly state the associated entity type.
    typealias Entity = ToggleResult

    func entities(for _: [ToggleResult.ID]) async throws -> [ToggleResult] {
        []
    }

    func suggestedEntities() async throws -> [ToggleResult] {
        []
    }
}

// MARK: - ToggleResult Entity

struct ToggleResult: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Closed Loop Status"

    // Provide a concrete default query.
    static var defaultQuery = EmptyToggleQuery()

    // Unique identifier required by Identifiable.
    var id = UUID()

    // Using the property wrapper. Simply assign to the property.
    @Property(title: "Status") var status: Bool

    // Custom initializer.
    init(status: Bool) {
        self.status = status
    }

    // Display representation for Shortcuts.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: status ? "Closed Loop Enabled" : "Closed Loop Disabled")
    }
}
