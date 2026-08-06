import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State private var setupCGM = false

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                List {
                    Section(
                        header: Text("CGM Integration för Trio"),
                        content: {
                            VStack {
                                Picker("Typ", selection: $state.cgmCurrent) {
                                    ForEach(state.listOfCGM) { type in
                                        VStack(alignment: .leading) {
                                            Text(type.displayName)
                                            Text(type.subtitle).font(.caption).foregroundColor(.secondary)
                                        }.tag(type)
                                    }
                                }.padding(.top)

                                HStack(alignment: .center) {
                                    Text(
                                        "Välj din CGM. Klicka på frågetecknet för mer info."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "Tillgängliga CGM-modeller i Trio"
                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "• Dexcom G5 \n• Dexcom G6 / ONE \n• Dexcom G7 / ONE+ \n• Dexcom Share \n• Freestyle Libre \n• Freestyle Libre Demo \n• Glukossimulator \n• Medtronic Enlite \n• Nightscout \n• xDrip4iOS"
                                                    )
                                                )
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.bottom)

                            if let link = state.cgmCurrent.type.externalLink {
                                Button {
                                    UIApplication.shared.open(link, options: [:], completionHandler: nil)
                                } label: {
                                    HStack {
                                        Text("Om denna källa")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if state.cgmCurrent.type == .plugin {
                                Button {
                                    setupCGM.toggle()
                                } label: {
                                    HStack {
                                        Text("CGM Konfiguration")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    ).listRowBackground(Color.chart)

                    if let appURL = state.urlOfApp() {
                        Section {
                            Button {
                                UIApplication.shared.open(appURL, options: [:]) { success in
                                    if !success {
                                        self.router.alertMessage
                                            .send(MessageContent(content: "Kan inte öppna appen", type: .warning))
                                    }
                                }
                            }

                            label: {
                                Label(state.displayNameOfApp() ?? "-", systemImage: "waveform.path.ecg.rectangle").font(.title3)
                                    .padding() }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                        }
                        .listRowBackground(Color.clear)
                    } else if state.cgmCurrent.type == .nightscout {
                        if let url = state.url {
                            Section {
                                Button {
                                    UIApplication.shared.open(url, options: [:]) { success in
                                        if !success {
                                            self.router.alertMessage
                                                .send(MessageContent(content: "Ingen URL tillgänglig", type: .warning))
                                        }
                                    }
                                }
                                label: { Label("Öppna URL", systemImage: "waveform.path.ecg.rectangle").font(.title3).padding() }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            Section {
                                Button {
                                    state.showModal(for: .nighscoutConfigDirect)
                                }
                                label: {
                                    Label("Konfigurera Nightscout", systemImage: "waveform.path.ecg.rectangle").font(.title3)
                                        .padding()
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }

                    if state.cgmCurrent.type == .xdrip {
                        Section(header: Text("Heartbeat")) {
                            VStack(alignment: .leading) {
                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
                                    Text("CGM adress :").padding(.top)
                                    Text(cgmTransmitterDeviceAddress)
                                } else {
                                    Text("CGM används inte som heartbeat.").padding(.top)
                                }

                                HStack(alignment: .center) {
                                    Text(
                                        "Ett heartbeat triggar Trio att genomföra en loop. Detta krävs för att använda sluten loop."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "CGM Heartbeat"
                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "CGM heartbeat kan komma från en CGM eller en pump, och väcker Trio när telefonen är låst och appen är inaktiv bakgrunden."
                                                    )
                                                )
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.vertical)
                            }
                        }.listRowBackground(Color.chart)
                    }

                    if state.cgmCurrent.type == .plugin && state.cgmCurrent.id.contains("Libre") {
                        Section {
                            Text("Libre kalibrering").navigationLink(to: .calibrations, from: self)
                        }.listRowBackground(Color.chart)
                    }

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.smoothGlucose,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Utjämna glukosvärden"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Utjämna glukosvärden",
                        miniHint: "Utjämna glukosvärden med Savitzky-Golay filtrering.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "Detta filter analyserar små grupper av närliggande glukosvärden och anpassar dem till en enkel matematisk kurva. Processen förändrar inte det övergripande mönstret i dina glukosdata, men hjälper till att jämna ut \"brus\" och små oregelbundna variationer som annars kan ge falskt höga eller låga värden."
                            )
                            Text(
                                "Syftet är att bevara de viktiga trenderna i dina glukosdata samtidigt som små, missvisande variationer minimeras. Det ger både dig och Trio en tydligare bild av vart ditt blodsocker faktiskt är på väg. Den här typen av filtrering är användbar i Trio eftersom den kan minska risken för överkorrigeringar baserade på felaktiga glukosvärden. Den kan också minska påverkan från plötsliga toppar eller dalar som inte speglar ditt verkliga blodsocker."
                            )
                            Text(
                                "Obs: Om denna funktion är aktiverad kan de utjämnade glukosvärden som visas i Trio skilja sig från de värden som visas i din CGM-app."
                            )
                        }
                    )
                }
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Stäng", action: state.hideModal) : nil)
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                        sheetTitle: "Hjälp"
                    )
                }
                .onChange(of: setupCGM) { _, setupCGM in
                    state.setupCGM = setupCGM
                }
                .onChange(of: state.setupCGM) { _, setupCGM in
                    self.setupCGM = setupCGM
                }
                .screenNavigation(self)
            }
            .sheet(isPresented: $setupCGM) {
                if let cgmFetchManager = state.cgmManager,
                   let cgmManager = cgmFetchManager.cgmManager,
                   state.cgmCurrent.type == cgmFetchManager.cgmGlucoseSourceType,
                   state.cgmCurrent.id == cgmFetchManager.cgmGlucosePluginId
                {
                    CGMSettingsView(
                        cgmManager: cgmManager,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        unit: state.settingsManager.settings.units,
                        completionDelegate: state
                    )
                } else {
                    CGMSetupView(
                        CGMType: state.cgmCurrent,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        unit: state.settingsManager.settings.units,
                        completionDelegate: state,
                        setupDelegate: state,
                        pluginCGMManager: self.state.pluginCGMManager
                    )
                }
            }
        }
    }
}
