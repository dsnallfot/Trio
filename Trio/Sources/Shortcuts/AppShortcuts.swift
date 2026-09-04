import AppIntents
import Foundation

struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        /* AppShortcut(
             intent: BolusIntent(),
             phrases: [
                 "\(.applicationName) bolus",
                 "Ge en bolus via \(.applicationName)"
             ],
             shortTitle: "Bolus",
             systemImageName: "syringe.fill"
         ) */
        AppShortcut(
            intent: ApplyTempPresetIntent(),
            phrases: [
                "Aktivera ett tillfälligt mål i \(.applicationName)?",
                "\(.applicationName) aktivera tillfälligt mål"
            ],
            shortTitle: "Temporary Target",
            systemImageName: "target"
        )
        AppShortcut(
            intent: ListStateIntent(),
            phrases: [
                "Lista \(.applicationName) status",
                "\(.applicationName) status"
            ],
            shortTitle: "List State",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: AddCarbPresetIntent(),
            phrases: [
                "Registera måltid i \(.applicationName)",
                "\(.applicationName) tillåts registrera måltid"
            ],
            shortTitle: "Add Carbs",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: ManualGlucoseIntent(),
            phrases: [
                "Registrera blodsocker i \(.applicationName)",
                "\(.applicationName) registrera blodsocker",
                "Registrera fingerstick i \(.applicationName)",
                "\(.applicationName) registrera fingerstick"
            ],
            shortTitle: "Manual Glucose",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: ApplyOverridePresetIntent(),
            phrases: [
                "Aktivera en override i \(.applicationName)",
                "Aktiverar en tillgänglig override i \(.applicationName)"
            ],
            shortTitle: "Activate Override",
            systemImageName: "arrow.up.arrow.down.circle"
        )
        AppShortcut(
            intent: CancelOverrideIntent(),
            phrases: [
                "Avbryt override i \(.applicationName)",
                "Avbryter en aktiv override i \(.applicationName)"
            ],
            shortTitle: "Cancel Override",
            systemImageName: "xmark.circle.fill"
        )
        AppShortcut(
            intent: CancelTempPresetIntent(),
            phrases: [
                "Avbryt tillfälligt mål i \(.applicationName)",
                "Avbryter ett tillfälligt mål i \(.applicationName)"
            ],
            shortTitle: "Cancel Temp Target",
            systemImageName: "xmark.circle.fill"
        )
        // Daniel: Added delete carb entry app shortcut for testing otherwise remote triggered automations
        AppShortcut(
            intent: DeleteCarbEntryIntent(),
            phrases: [
                "Radera kh vid angiven tid i \(.applicationName)",
                "\(.applicationName) ta bort kh"
            ],
            shortTitle: "Delete Carbs",
            systemImageName: "trash.fill"
        )
        AppShortcut(
            intent: ToggleClosedLoopIntent(),
            phrases: [
                "Toggle closed loop in \(.applicationName)",
                "\(.applicationName) toggle closed loop"
            ],
            shortTitle: "Toggle Closed Loop",
            systemImageName: "switch.2"
        )
        AppShortcut(
            intent: ToggleUploadErrorsIntent(),
            phrases: [
                "Toggle Pump Error Upload \(.applicationName)",
                "\(.applicationName) toggle pump error upload"
            ],
            shortTitle: "Toggle Pump Error Upload",
            systemImageName: "exclamationmark.triangle"
        )
    }
}
