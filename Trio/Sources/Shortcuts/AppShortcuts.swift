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
    }
}
