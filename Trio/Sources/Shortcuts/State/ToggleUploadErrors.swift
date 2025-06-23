import AppIntents
import Foundation
import SwiftUI

// A new intent request to access our injected services
final class ToggleUploadErrorsIntentRequest: BaseIntentsRequest {}

@available(iOS 16.0, *) struct ToggleUploadErrorsIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Upload Errors"
    static var description = IntentDescription(
        "Toggles the upload Errors setting in the app, or sets it explicitly if a value is provided."
    )

    // Optional parameter: if provided, sets the setting to that value; otherwise, toggles it.
    @Parameter(
        title: "Enable",
        description: "Optional value: true to enable, false to disable. If omitted, the setting will be toggled."
    ) var enable: Bool?

    @Parameter(
        title: LocalizedStringResource(
            "Bekräfta innan du aktiverar/inaktiverar uppladdning av pumpfel till Nightscout",
            table: "ShortcutsDetail"
        ),
        description: LocalizedStringResource(
            "Om aktiverad, så måste du bekräfta innan du aktiverar/inaktiverar uppladdning av pumpfel till Nightscout",
            table: "ShortcutsDetail"
        ),
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$confirmBeforeApplying, .equalTo, true, {
            Summary("Aktivera uppladdning av pumpfel \(\.$enable)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Inaktivera uppladdning av pumpfel \(\.$enable)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ReturnsValue<ToggleResult> & ShowsSnippetView {
        // Create an instance of our intent request so we can access the SettingsManager.
        let request = ToggleUploadErrorsIntentRequest()

        // Get the current isErrorUploadEnabled value from your settings.
        let currentValue = request.settingsManager.settings.isErrorUploadEnabled

        // Determine the new value: if 'enable' is provided, use it; otherwise, invert the current value.
        let newValue = enable ?? !currentValue

        // If confirmation is enabled, present a confirmation dialog.
        if confirmBeforeApplying {
            // Choose an appropriate message based on the new state.
            let actionText = newValue
                ? LocalizedStringResource("Vill du aktivera uppladdning av pumpfel?", table: "ShortcutsDetail")
                : LocalizedStringResource("Vill du inaktivera uppladdning av pumpfel?", table: "ShortcutsDetail")
            try await requestConfirmation(
                result: .result(
                    dialog: IntentDialog(actionText)
                )
            )
        }

        // Update the setting.
        request.settingsManager.settings.isErrorUploadEnabled = newValue

        // Return the result.
        return .result(value: ToggleResult(status: newValue))
    }
}

// MARK: - Default Query

// Define an empty query that explicitly works with ToggleResult.
struct EmptyUploadErrorsToggleQuery: EntityQuery {
    // Explicitly state the associated entity type.
    typealias Entity = UploadErrorsToggleResult

    func entities(for _: [UploadErrorsToggleResult.ID]) async throws -> [UploadErrorsToggleResult] {
        []
    }

    func suggestedEntities() async throws -> [UploadErrorsToggleResult] {
        []
    }
}

// MARK: - ToggleResult Entity

struct UploadErrorsToggleResult: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Status Uppladdning av Pumpfel"

    // Provide a concrete default query.
    static var defaultQuery = EmptyUploadErrorsToggleQuery()

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
        DisplayRepresentation(title: status ? "Uppladdning av pumpfel aktiverad" : "Uppladdning av pumpfel inaktiverad")
    }
}
