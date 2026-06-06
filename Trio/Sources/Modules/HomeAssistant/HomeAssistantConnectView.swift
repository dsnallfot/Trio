import SwiftUI

struct HomeAssistantConnectView: View {
    @AppStorage("HomeAssistantConfig.localGlucoseUploadEnabled") private var localGlucoseUploadEnabled = false
    @AppStorage("HomeAssistantConfig.urlHA") private var urlHA = "http://192.168.0.191:8123/api/webhook/localglucoseupdate"
    @AppStorage("HomeAssistantConfig.urlThisPhone") private var urlThisPhone = "192.168.0.246"

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Home Assistant"),
                footer: Text(
                    "Används för lokal glukosbackup via webhook när Trio-enheten är hemma på samma Wi‑Fi som Home Assistant."
                )
            ) {
                Toggle("Ladda upp glukos lokalt", isOn: $localGlucoseUploadEnabled)

                TextField("Home Assistant webhook URL", text: $urlHA)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                TextField("Denna iPhones lokala IP-adress", text: $urlThisPhone)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
            }
            .listRowBackground(Color.chart)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktiv när")
                        .font(.headline)
                    Text("• lokal uppladdning är påslagen")
                    Text("• denna iPhones Wi‑Fi-IP matchar IP-adressen ovan")
                    Text("• ett nytt glukosvärde finns att skicka")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Home Assistant")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
