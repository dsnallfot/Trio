import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State var importAlert: Alert?
        @State var isImportAlertPresented = false
        @State var importedHasRun = false
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            ZStack {
                List {
                    Section(
                        header: Text("Nightscout-integrering"),
                        content: {
                            NavigationLink(
                                destination: NightscoutConnectView(state: state),
                                label: {
                                    HStack {
                                        Text("Anslut")

                                        ZStack {
                                            if state.isConnectedToNS {
                                                Image(systemName: "network")

                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption2)
                                                    .offset(x: 9, y: 6)
                                            } else {
                                                Image(systemName: "network.slash")
                                            }
                                        }
                                    }
                                }
                            )

                            NavigationLink(
                                "Uppladdning",
                                destination: NightscoutUploadView(state: state)
                            )

                            NavigationLink(
                                "Hämtning",
                                destination: NightscoutFetchView(state: state)
                            )
                        }
                    )
                    .listRowBackground(Color.chart)

                    Section {
                        VStack {
                            Button {
                                importAlert = Alert(
                                    title: Text("Importera behandlingsinställningar?"),
                                    message:
                                    Text(
                                        "Är du säker på att du vill importera profilinställningar från Nightscout?\n\n"
                                    )
                                        + Text(
                                            "Detta skriver över följande behandlingsinställningar i Trio:\n"
                                        )
                                        + Text("• Basalhastigheter\n")
                                        + Text("• Insulinkänslighet\n")
                                        + Text("• Kolhydratförhållanden\n")
                                        + Text("• Glukosmål\n")
                                        + Text("• Insulinets verkningstid"),
                                    primaryButton: .default(
                                        Text("Ja, importera!"),
                                        action: {
                                            Task {
                                                await state.importSettings()

                                                if state.importStatus == .failed,
                                                   state.importErrors.isNotEmpty,
                                                   let errorMessage = state.importErrors.first
                                                {
                                                    DispatchQueue.main.async {
                                                        importAlert = Alert(
                                                            title: Text("Importen misslyckades"),
                                                            message: Text(errorMessage.description),
                                                            dismissButton: .default(Text("OK"))
                                                        )

                                                        isImportAlertPresented = true
                                                    }
                                                }
                                            }
                                        }
                                    ),
                                    secondaryButton: .cancel(Text("Avbryt"))
                                )

                                isImportAlertPresented = true
                            } label: {
                                Text("Importera inställningar")
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)
                            .disabled(state.url.isEmpty || state.connecting)

                            HStack(alignment: .center) {
                                Text(
                                    "Importera behandlingsinställningar från Nightscout.\nSe hjälptexten för en lista över vilka inställningar som kan importeras."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)

                                Spacer()

                                Button(
                                    action: {
                                        hintLabel = "Importera inställningar från Nightscout"

                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Detta skriver över följande behandlingsinställningar i Trio:"
                                                    )

                                                    VStack(alignment: .leading) {
                                                        Text("• Basalprofil")
                                                        Text("• Insulinkänslighet")
                                                        Text("• Insulinkvoter")
                                                        Text("• Målglukos")
                                                        Text("• Insulinets verkningstid")
                                                    }
                                                }
                                            )

                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                )
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.top)
                        }
                        .padding(.vertical)
                    }
                    .listRowBackground(Color.chart)

                    Section(
                        content: {
                            VStack {
                                Button {
                                    Task {
                                        await state.backfillGlucose()
                                    }
                                } label: {
                                    Text("Återfyll glukosdata")
                                        .font(.title3)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                                .disabled(
                                    state.url.isEmpty ||
                                        state.connecting ||
                                        state.backfilling
                                )

                                HStack(alignment: .center) {
                                    Text(
                                        "Återfyll saknade glukosdata från Nightscout."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)

                                    Spacer()

                                    Button(
                                        action: {
                                            hintLabel = "Återfyll glukosdata från Nightscout"

                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "Detta hämtar och återfyller de senaste 24 timmarnas glukosdata från din anslutna Nightscout-adress till Trio."
                                                    )
                                                )

                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    )
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                                .padding(.top)
                            }
                            .padding(.vertical)
                        }
                    )
                    .listRowBackground(Color.chart)
                }
                .listSectionSpacing(sectionSpacing)
                .blur(radius: state.importStatus == .running ? 5 : 0)

                if state.importStatus == .running {
                    CustomProgressView(text: "Importerar profil...")
                }
            }
            .fullScreenCover(
                isPresented: $state.isImportResultReviewPresented,
                content: {
                    NightscoutImportResultView(
                        resolver: resolver,
                        state: state
                    )
                }
            )
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Hjälp"
                )
            }
            .navigationBarTitle("Nightscout")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(isPresented: $isImportAlertPresented) {
                importAlert ?? Alert(title: Text("Okänt fel"))
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
        }
    }
}
