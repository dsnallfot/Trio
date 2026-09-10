import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension Settings {
    @MainActor private struct DiagnosticStatusView: View {
        @ObservedObject private var diagnostics = RuntimeDiagnosticsDisplay.shared

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter
        }()

        private func memoryText(_ sample: RuntimeDiagnosticsDisplay.MemorySample?) -> String {
            guard let sample else { return "Inväntar mätning" }
            return "\(Self.timeFormatter.string(from: sample.date))  \(String(format: "%.1f", sample.mebibytes)) MiB"
        }

        var body: some View {
            Group {
                LabeledContent("Minnesanvändning", value: memoryText(diagnostics.latest))
                LabeledContent("Max användning uppmätt", value: memoryText(diagnostics.peak))
                LabeledContent(
                    "Senaste omstart",
                    value: diagnostics.sessionStart.map { Self.dateFormatter.string(from: $0) } ?? "Inväntar appstart"
                )
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    struct VersionInfo: Equatable {
        var latestVersion: String?
        var isUpdateAvailable: Bool
        var isBlacklisted: Bool
    }

    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @AppStorage(DiagnosticLogging.enabledKey) private var logDiagnostics = DiagnosticLogging.defaultEnabled

        @State private var showShareSheet = false
        @State private var searchText: String = ""

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var versionInfo = VersionInfo(
            latestVersion: nil,
            isUpdateAvailable: false,
            isBlacklisted: false
        )

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        private var filteredItems: [FilteredSettingItem] {
            SettingItems.filteredItems(searchText: searchText)
        }

        @ViewBuilder var versionInfoView: some View {
            let latestVersion = versionInfo.latestVersion
            if let version = latestVersion {
                let updateColor: Color = versionInfo.isUpdateAvailable ? .orange : .green
                let versionIconName = versionInfo.isUpdateAvailable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Senaste version: \(version)")
                            .font(.footnote)
                            .foregroundColor(updateColor)
                        Image(systemName: versionIconName)
                            .foregroundColor(updateColor)
                    }
                    if versionInfo.isBlacklisted {
                        HStack {
                            Text("Varning: Kända fel. Uppdatera snarast.")
                                .font(.footnote)
                                .foregroundColor(.red)
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            } else {
                Text("Senaste version: Söker...")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }

        var body: some View {
            List {
                if searchText.isEmpty {
                    let buildDetails = BuildDetails.shared

                    Section(
                        header: Text("Branch: \(buildDetails.branchAndSha)").textCase(nil),
                        content: {
                            let versionNumber = Bundle.main.releaseVersionNumber ?? "Unknown"
                            let buildNumber = Bundle.main.buildVersionNumber ?? "Unknown"

                            NavigationLink(destination: SubmodulesView(buildDetails: buildDetails)) {
                                HStack {
                                    Image(appIcons.appIcon.rawValue)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(10)
                                        .padding(.trailing, 10)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Trio v\(versionNumber) (\(buildNumber))")
                                            .font(.headline)
                                        if let expirationDate = buildDetails.calculateExpirationDate() {
                                            let formattedDate = DateFormatter.localizedString(
                                                from: expirationDate,
                                                dateStyle: .medium,
                                                timeStyle: .none
                                            )
                                            Text("\(buildDetails.expirationHeaderString): \(formattedDate)")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Simulatorbygge löper aldrig ut")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }

                                        versionInfoView
                                    }
                                }
                            }
                        }
                    ).listRowBackground(Color.chart)

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.closedLoop,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Sluten Loop"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Sluten Loop",
                        miniHint: "Aktivera automatisk insulintillförsel.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Att använda Trio med sluten loop kräver an aktiv CGM-sensorsession och en ansluten pump. Detta möjliggör automatisk insulindosering."
                            )
                            Text(
                                "Innan aktivering, se till att dina behandlingsinställningar är väl injusterade (Basal/ISF/CR)."
                            )
                        },
                        headerText: "Automatisk insulintillförsel"
                    )

                    Section(
                        header: Text("Trio Konfiguration"),
                        content: {
                            ForEach(SettingItems.trioConfig) { item in
                                Text(item.title).navigationLink(to: item.view, from: self)
                            }
                        }
                    )
                    .listRowBackground(Color.chart)

                    Section(
                        header: Text("Support & Community"),
                        content: {
                            Button {
                                showShareSheet.toggle()
                            } label: {
                                HStack {
                                    Text("Dela loggar")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            /*
                             Button {
                                 if let url = URL(string: "https://github.com/nightscout/Trio/issues/new/choose") {
                                     UIApplication.shared.open(url)
                                 }
                             } label: {
                                 HStack {
                                     Text("Registrera en ticket på GitHub")
                                         .foregroundColor(.primary)
                                     Spacer()
                                     Image(systemName: "chevron.right")
                                         .foregroundColor(.secondary)
                                         .font(.footnote)
                                 }
                             }
                             .frame(maxWidth: .infinity, alignment: .leading)
                             */
                            Button {
                                if let url = URL(string: "https://discord.gg/FnwFEFUwXE") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Trio Discord")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            /*
                             Button {
                                 if let url = URL(string: "https://m.facebook.com/groups/1351938092206709/") {
                                     UIApplication.shared.open(url)
                                 }
                             } label: {
                                 HStack {
                                     Text("Trio Facebook")
                                         .foregroundColor(.primary)
                                     Spacer()
                                     Image(systemName: "chevron.right")
                                         .foregroundColor(.secondary)
                                         .font(.footnote)
                                 }
                             }
                             .frame(maxWidth: .infinity, alignment: .leading)
                             */
                            Button {
                                if let url = URL(string: "https://diy-trio.org/") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Trio Webbsida")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    ).listRowBackground(Color.chart)

                    Section(
                        header: Text("Avancerade alternativ"),
                        content: {
                            Toggle("Visa", isOn: $state.debugOptions)
                        }
                    ).listRowBackground(Color.chart)

                    Section(
                        // header: Text("diagnostik"),
                        content: {
                            if state.debugOptions {
                                Toggle("Logga diagnostik", isOn: $logDiagnostics)
                                if logDiagnostics {
                                    DiagnosticStatusView()
                                }
                                Button {
                                    Task {
                                        await state.uploadProfile()
                                    }
                                } label: {
                                    HStack {
                                        Text("Ladda upp profil till Nighscout")
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.footnote)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    ).listRowBackground(Color.chart)

                } else {
                    Section(
                        header: Text("Sökresultat"),
                        content: {
                            if filteredItems.isNotEmpty {
                                ForEach(filteredItems) { filteredItem in
                                    VStack(alignment: .leading) {
                                        Text(filteredItem.matchedContent).bold()
                                        if let path = filteredItem.settingItem.path {
                                            Text(path.map(\.stringValue).joined(separator: " > "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }.navigationLink(to: filteredItem.settingItem.view, from: self)
                                }
                            } else {
                                Text("Inga inställningar matchar din sökning")
                                    +
                                    Text(" »\(searchText)« ").bold()
                                    +
                                    Text("hittades.")
                            }
                        }
                    ).listRowBackground(Color.chart)
                }

                // TODO: remove this more or less entirely; add build-time flag to enable Middleware; add settings export feature
//                Section {
//                    Toggle("Developer Options", isOn: $state.debugOptions)
//                    if state.debugOptions {
//                        Group {
//                            HStack {
//                                Text("NS Upload Profile and Settings")
//                                Button("Upload") { state.uploadProfileAndSettings(true) }
//                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                                    .buttonStyle(.borderedProminent)
//                            }
//                            // Commenting this out for now, as not needed and possibly dangerous for users to be able to nuke their pump pairing informations via the debug menu
//                            // Leaving it in here, as it may be a handy functionality for further testing or developers.
//                            // See https://github.com/nightscout/Trio/pull/277 for more information
//                            //
//                            //                            HStack {
//                            //                                Text("Delete Stored Pump State Binary Files")
//                            //                                Button("Delete") { state.resetLoopDocuments() }
//                            //                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                            //                                    .buttonStyle(.borderedProminent)
//                            //                            }
//                        }
//                        Group {
//                            Text("Preferences")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.preferences), from: self)
//                            Text("Pump Settings")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.settings), from: self)
//                            Text("Autosense")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autosense), from: self)
//                            //                            Text("Pump History")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
//                            Text("Basal profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
//                    Text("Targets ranges")
//                        .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
//                            Text("Temp targets")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
//                        }
//
//                        Group {
//                            Text("Pump profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
//                            Text("Profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
//                            //                            Text("Carbs")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
//                        }
//
//                        Group {
//                            Text("Target presets")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Trio.tempTargetsPresets), from: self)
//                            Text("Calibrations")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Trio.calibrations), from: self)
//                            Text("Middleware")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Middleware.determineBasal), from: self)
//                            //                            Text("Statistics")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
//                            Text("Edit settings json")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Trio.settings), from: self)
//                        }
//                    }
//                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Help"
                )
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: state.logItems())
            }
            .onAppear(perform: configureView)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        action: {
                            if let url = URL(string: "https://triodocs.org/") {
                                UIApplication.shared.open(url)
                            }
                        },
                        label: {
                            HStack {
                                Text(" Trio Docs")
                                Image(systemName: "questionmark.circle")
                            }
                        }
                    )
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .screenNavigation(self)
            .onAppear {
                AppVersionChecker.shared.refreshVersionInfo { _, latestVersion, isNewer, isBlacklisted in
                    let updateAvailable = isNewer
                    DispatchQueue.main.async {
                        versionInfo = VersionInfo(
                            latestVersion: latestVersion,
                            isUpdateAvailable: updateAvailable,
                            isBlacklisted: isBlacklisted
                        )
                    }
                }
            }
        }
    }
}
