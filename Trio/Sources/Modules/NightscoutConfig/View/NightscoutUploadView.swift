import SwiftUI

struct NightscoutUploadView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.isUploadEnabled,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Tillåt uppladdning till Nightscout"
                        shouldDisplayHint = true
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Tillåt uppladdning till Nightscout",
                miniHint: "Aktivera uppladdning av valda data till Nightscout.",
                verboseHint:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Standard: Av").bold()

                    Text(
                        "När funktionen Ladda upp behandlingar är aktiverad laddas följande data upp till din anslutna Nightscout-adress:"
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("• Kolhydrater")
                        Text("• Tillfälliga glukosmål")
                        Text("• Enhetsstatus")
                        Text("• Inställningar")
                        Text("• Preferenser")
                    }
                }
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.isErrorUploadEnabled,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Tillåt uppladdning av pumpfel"
                        shouldDisplayHint = true
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Tillåt uppladdning av pumpfel till Nightscout",
                miniHint: "Aktivera uppladdning av pumpfel till Nightscout.",
                verboseHint:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Standard: AV").bold()

                    Text(
                        "När funktionen Ladda upp pumpfel är aktiverad laddas fel från din pump upp till Nightscout, till exempel:"
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("• Pumpen är upptagen med att ge bolus")
                        Text("• Pumpen är inte ansluten")
                        Text("• Andra kommunikationsfel")
                    }
                }
            )

            if state.changeUploadGlucose {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.uploadGlucose,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Ladda upp glukosvärden"
                            shouldDisplayHint = true
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Ladda upp glukosvärden",
                    miniHint: "Aktivera uppladdning av CGM-värden till Nightscout.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: Av").bold()

                        Text(
                            "När denna funktion är aktiverad laddas glukosvärden från Trio upp till Nightscout."
                        )
                    }
                )
            }
        }
        .listSectionSpacing(sectionSpacing)
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: "Hjälp"
            )
        }
        .navigationTitle("Uppladdning")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
