import ActivityKit
import SwiftUI
import Swinject

extension LiveActivitySettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @State private var systemLiveActivitySetting: Bool = {
            if #available(iOS 16.2, *) {
                ActivityAuthorizationInfo().areActivitiesEnabled
            } else {
                false
            }
        }()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                if !systemLiveActivitySetting {
                    Section(
                        header: Text("Visa livedata från Trio"),
                        content: {
                            Text(
                                "Liveaktivitet måste vara aktiverade i iOS-inställningarna för att Trio ska kunna visa livedata."
                            )
                        }
                    )
                    .listRowBackground(Color.chart)

                    Section {
                        Button {
                            UIApplication.shared.open(
                                URL(string: UIApplication.openSettingsURLString)!
                            )
                        } label: {
                            Label(
                                "Öppna iOS-inställningar",
                                systemImage: "gear.circle"
                            )
                            .font(.title3)
                            .padding()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.useLiveActivity,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Aktivera Liveaktivitet"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Aktivera Liveaktivitet",
                        miniHint: "Visa anpassningsbara data på låsskärmen och i Dynamic Island.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()

                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "När Liveaktivitet är aktiverade kan Trio visa valfri aktuell information på din iPhones låsskärm och i Dynamic Island:"
                                )

                                VStack(alignment: .leading) {
                                    Text("• Aktuellt glukosvärde")
                                    Text("• IOB: Aktivt insulin")
                                    Text("• COB: Kolhydrater ombord")
                                    Text("• Senast uppdaterad: Tid för senaste loopcykel")
                                    Text("• Glukostrendgraf")
                                }
                                .font(.footnote)

                                Text(
                                    "Det gör det möjligt att snabbt se aktuell information och utföra snabba åtgärder i din diabeteshantering."
                                )
                            }
                        },
                        headerText: "Visa livedata från Trio"
                    )

                    if state.useLiveActivity {
                        Section {
                            VStack {
                                Picker(
                                    selection: $state.lockScreenView,
                                    label: Text("Stil för låsskärmswidget")
                                ) {
                                    ForEach(LockScreenView.allCases) { selection in
                                        Text(selection.displayName).tag(selection)
                                    }
                                }
                                .padding(.top)

                                HStack(alignment: .center) {
                                    Text(
                                        "Välj enkel eller detaljerad stil. Se hjälptexten för mer information."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)

                                    Spacer()

                                    Button(
                                        action: {
                                            hintLabel = "Stil för låsskärmswidget"

                                            selectedVerboseHint =
                                                AnyView(
                                                    VStack(alignment: .leading, spacing: 10) {
                                                        Text("Standard: Enkel").bold()

                                                        VStack(alignment: .leading, spacing: 10) {
                                                            Text("Enkel:").bold()

                                                            Text(
                                                                "Trions enkla låsskärmswidget visar aktuellt glukosvärde, trendpil, delta och tidpunkten för det aktuella värdet."
                                                            )
                                                        }

                                                        VStack(alignment: .leading, spacing: 10) {
                                                            Text("Detaljerad:").bold()

                                                            Text(
                                                                "Den detaljerade låsskärmswidgeten visar en glukosgraf och låter dig anpassa vilken information som ska visas med hjälp av följande alternativ:"
                                                            )
                                                        }

                                                        VStack(alignment: .leading) {
                                                            Text("• Aktuellt glukosvärde")
                                                            Text("• IOB: Aktivt insulin")
                                                            Text("• COB: Kolhydrater ombord")
                                                            Text("• Senast uppdaterad: Tid för senaste loopcykel")
                                                        }
                                                        .font(.footnote)
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
                            .padding(.bottom)

                            if state.lockScreenView == .detailed {
                                HStack {
                                    NavigationLink(
                                        "Widgetinställningar",
                                        destination: LiveActivityWidgetConfiguration(
                                            resolver: resolver,
                                            state: state
                                        )
                                    )
                                    .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .listRowBackground(Color.chart)
                    }
                }
            }
            .listSectionSpacing(sectionSpacing)
            .onReceive(
                resolver.resolve(LiveActivityBridge.self)!.$systemEnabled,
                perform: {
                    self.systemLiveActivitySetting = $0
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
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Liveaktivitet")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
