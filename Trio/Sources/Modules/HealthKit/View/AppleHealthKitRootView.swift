import SwiftUI
import Swinject

extension AppleHealthKit {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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
                    booleanValue: $state.useAppleHealth,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Anslut till Apple Hälsa"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Anslut till Apple Hälsa",
                    miniHint: "Låt Trio läsa och skriva data i Apple Hälsa.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: Av").bold()

                        Text(
                            "Detta gör det möjligt för Trio att läsa och skriva data i Apple Hälsa."
                        )

                        Text(
                            "Varning: Du måste även ge Trio behörighet i iOS-inställningarna för appen Hälsa."
                        )
                        .bold()
                    },
                    headerText: "Apple Hälsa-integrering"
                )

                if !state.needShowInformationTextForSetPermissions {
                    Section {
                        VStack {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Ge Apple Hälsa skrivbehörighet")
                            }
                            .padding(.bottom)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("1. Öppna appen Inställningar på din iPhone.")
                                Text("2. Bläddra ned eller sök efter \"Hälsa\" och öppna appen Hälsa.")
                                Text("3. Tryck på \"Dataåtkomst och enheter\".")
                                Text("4. Välj \"Trio\" i listan över appar.")
                                Text(
                                    "5. Kontrollera att \"Skriva data\" är aktiverat för de hälsodata du vill att Trio ska kunna spara."
                                )
                            }
                            .font(.footnote)
                        }
                        .padding(.vertical)
                        .foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.chart)
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
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Apple Hälsa")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
