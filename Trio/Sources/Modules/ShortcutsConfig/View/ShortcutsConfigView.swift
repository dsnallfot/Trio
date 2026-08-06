import Combine
import SwiftUI
import Swinject
import UIKit

extension ShortcutsConfig {
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
                Section(
                    header: Text("Integrering med Genvägar"),
                    content: {
                        Text(
                            "Med Trio kan du skapa automatiseringar med hjälp av iOS-appen Genvägar. Öppna appen Genvägar för att skapa nya automatiseringar."
                        )
                    }
                )
                .listRowBackground(Color.chart)

                Section {
                    Button {
                        UIApplication.shared.open(URL(string: "shortcuts://")!)
                    } label: {
                        Label(
                            "Öppna Genvägar",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.title3)
                        .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowBolusByShortcuts,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Tillåt bolus via Genvägar"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Tillåt bolus via Genvägar",
                    miniHint: "Automatisera bolusdoser med iOS-appen Genvägar.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "När denna inställning är aktiverad kan iOS-appen Genvägar skicka boluskommandon till Trio."
                            )

                            Text(
                                "Om inställningen är avstängd kan Genvägar fortfarande skicka andra kommandon, till exempel ange tillfälliga mål, registrera kolhydrater samt starta eller avsluta overrides."
                            )
                        }
                    }
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
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Genvägar")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
