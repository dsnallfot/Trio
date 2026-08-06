import SwiftUI

struct NightscoutConnectView: View {
    @ObservedObject var state: NightscoutConfig.StateModel
    @State private var portFormatter: NumberFormatter

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    init(state: NightscoutConfig.StateModel) {
        self.state = state
        portFormatter = NumberFormatter()
        portFormatter.allowsFloats = false
        portFormatter.usesGroupingSeparator = false
    }

    var body: some View {
        List {
            Section(
                header: Text("Anslut till Nightscout"),
                content: {
                    HStack {
                        TextField("URL", text: $state.url)
                            .disableAutocorrection(true)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)

                        if state.message.isNotEmpty && !state.isValidURL {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    SecureField("API-hemlighet", text: $state.secret)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .textContentType(.password)
                        .keyboardType(.asciiCapable)

                    if state.message.isNotEmpty {
                        Text(state.message)
                    }

                    if state.connecting {
                        HStack {
                            Text("Ansluter...")

                            Spacer()

                            ProgressView()
                        }
                    }

                    if !state.isConnectedToNS {
                        Button {
                            state.connect()
                        } label: {
                            Text("Anslut till Nightscout")
                                .font(.title3)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                        .disabled(state.url.isEmpty && state.connecting)
                    } else {
                        Button(role: .destructive) {
                            state.delete()
                        } label: {
                            Text("Koppla från och ta bort")
                                .font(.title3)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                        .tint(Color.loopRed)
                    }
                }
            )
            .listRowBackground(Color.chart)

            if state.isConnectedToNS {
                Section {
                    Button {
                        UIApplication.shared.open(
                            URL(string: state.url)!,
                            options: [:],
                            completionHandler: nil
                        )
                    } label: {
                        Label(
                            "Öppna Nightscout",
                            systemImage: "waveform.path.ecg.rectangle"
                        )
                        .font(.title3)
                        .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }

            // TODO: Ta reda på om detta fortfarande behövs.
//            Section {
//                Toggle("Använd lokal glukosserver", isOn: $state.useLocalSource)
//                HStack {
//                    Text("Port")
//                    TextFieldWithToolBar(
//                        text: $state.localPort,
//                        placeholder: "",
//                        keyboardType: .numberPad,
//                        numberFormatter: portFormatter,
//                        allowDecimalSeparator: false
//                    )
//                }
//            } header: { Text("Lokal glukoskälla") }
//            .listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .navigationTitle("Anslut")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
