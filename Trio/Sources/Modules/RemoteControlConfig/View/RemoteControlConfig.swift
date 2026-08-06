import Combine
import SwiftUI
import Swinject
import UIKit

extension RemoteControlConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var isCopied: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.isTrioRemoteControlEnabled,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Aktivera fjärrstyrning"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Aktivera fjärrstyrning",
                    miniHint: "Tillåt Trio att ta emot kommandon från Loop Follow på distans.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "När fjärrstyrning är aktiverad kan du skicka boluser, overrides, tillfälliga mål, kolhydrater och andra kommandon till Trio via pushnotiser."
                        )

                        Text(
                            "För att säkerställa säkerheten skyddas dessa kommandon med en delad hemlighet som måste anges i appen Loop Follow."
                        )
                    },
                    headerText: "Trio Fjärrstyrning"
                )

                Section(
                    header: Text("Delad hemlighet"),
                    content: {
                        TextField("Ange delad hemlighet", text: $state.sharedSecret)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                            .padding(8)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)

                        Button(action: {
                            UIPasteboard.general.string = state.sharedSecret
                            isCopied = true
                        }) {
                            Label("Kopiera hemlighet", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .alert(isPresented: $isCopied) {
                            Alert(
                                title: Text("Kopierad"),
                                message: Text("Den delade hemligheten har kopierats till urklipp"),
                                dismissButton: .default(Text("OK"))
                            )
                        }

                        Button(action: {
                            state.generateNewSharedSecret()
                        }) {
                            Label("Generera ny hemlighet", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                )
                .listRowBackground(Color.chart)
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
            .navigationTitle("Fjärrstyrning")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
