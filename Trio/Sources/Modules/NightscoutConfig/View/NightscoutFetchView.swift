import SwiftUI

struct NightscoutFetchView: View {
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
                booleanValue: $state.isDownloadEnabled,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Tillåt hämtning från Nightscout"
                    }
                ),
                units: state.units,
                type: .boolean,
                label: "Tillåt hämtning från Nightscout",
                miniHint: "Aktivera hämtning av valda data från Nightscout.",
                verboseHint: VStack(alignment: .leading, spacing: 10) {
                    Text("Standard: AV").bold()

                    Text(
                        "När funktionen Hämta behandlingar är aktiverad hämtas kolhydrater och tillfälliga glukosmål som har registrerats i Careportal eller av en annan enhet än Trio och laddats upp till Nightscout."
                    )
                },
                headerText: "Hämta data från Nightscout Careportal"
            )
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
        .navigationTitle("Hämtning")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
