import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showPumpSelection: Bool = false
        @State private var pendingPumpSelection: PumpConfig.PumpType?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                Form {
                    Section(
                        header: Text("Pumpintegration för Trio"),
                        content: {
                            if let pumpState = state.pumpState {
                                Button {
                                    state.setupPump = true
                                } label: {
                                    HStack {
                                        Image(uiImage: pumpState.image ?? UIImage())
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 100)
                                            .padding()
                                        Text(pumpState.name)
                                    }
                                }
                                if state.alertNotAck {
                                    Spacer()
                                    Button("Bekräfta alla notiser") { state.ack() }
                                }
                            } else {
                                VStack {
                                    Button {
                                        showPumpSelection.toggle()
                                    } label: {
                                        Text("Lägg till pump")
                                            .font(.title3) }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .buttonStyle(.bordered)

                                    HStack(alignment: .center) {
                                        Text(
                                            "Parkoppla din insulinpump med Trio. Klicka på frågetecknet för mer info."
                                        )
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        Spacer()
                                        Button(
                                            action: {
                                                shouldDisplayHint.toggle()
                                            },
                                            label: {
                                                HStack {
                                                    Image(systemName: "questionmark.circle")
                                                }
                                            }
                                        ).buttonStyle(BorderlessButtonStyle())
                                    }.padding(.top)
                                }.padding(.vertical)
                            }
                        }
                    )
                    .padding(.top)
                    .listRowBackground(Color.chart)
                }
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationTitle("Insulinpump")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Stäng", action: state.hideModal) : nil)
                .sheet(isPresented: $state.setupPump) {
                    if let pumpManager = state.provider.apsManager.pumpManager {
                        PumpSettingsView(
                            pumpManager: pumpManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    } else {
                        PumpSetupView(
                            pumpType: state.setupPumpType,
                            pumpInitialSettings: state.initialSettings,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    }
                }
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: "Parkoppla pump med Trio",
                        hintText: AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Nuvarande Pumpmodeller som stöds:"
                                )
                                VStack(alignment: .leading) {
                                    ForEach(DeviceCatalog.pumps) { entry in
                                        Text("• \(entry.hintLine)")
                                    }
                                }
                                Text(
                                    "Notera: Pumpsimulatorn ska endast användas för test och utveckling."
                                )
                            }
                        ),
                        sheetTitle: "Hjälp"
                    )
                }
                .sheet(isPresented: $showPumpSelection, onDismiss: {
                    guard let selection = pendingPumpSelection else { return }
                    pendingPumpSelection = nil
                    state.addPump(selection)
                }) {
                    DevicePickerView(title: "Välj insulinpump", entries: DeviceCatalog.pumps) { entry in
                        pendingPumpSelection = entry.selection
                    }
                }
            }
        }
    }
}
