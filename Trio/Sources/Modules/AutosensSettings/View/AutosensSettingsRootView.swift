import SwiftUI
import Swinject

extension AutosensSettings {
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
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var autosensVerboseHint: some View {
            VStack(alignment: .leading, spacing: 15) {
                Text(
                    "Autosens justerar automatiskt insulindoseringen utifrån hur känslig eller resistent du är mot insulin under den aktuella loopcykeln. Genom att analysera tidigare data hjälper funktionen till att hålla blodsockret stabilt."
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Så fungerar det").bold()
                    Text(
                        "Autosens analyserar data från de senaste 8–24 timmarna, men bortser från förändringar som är kopplade till måltider. Vid behov justeras inställningar som basal och blodsockermål för att bättre matcha din aktuella insulinkänslighet eller insulinresistens."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Vad som justeras").bold()
                    Text(
                        "Autosens justerar insulinkänslighetsfaktorn (ISF), basalen och blodsockermålet. Funktionen tar inte hänsyn till kolhydrater, utan anpassar insulineffekten utifrån mönster i dina glukosvärden."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Viktiga begränsningar").bold()
                    Text(
                        "Autosens har inbyggda säkerhetsgränser som styrs av inställningarna Autosens Max och Autosens Min. Dessa förhindrar att justeringarna blir för stora."
                    )
                }

                Text(
                    "Autosens samverkar med vissa andra funktioner, exempelvis super mikrobolus (SMB). Andra inställningar, som Dynamisk ISF, påverkar delar av Autosens-beräkningen. Läs gärna hjälptexterna för algoritminställningarna innan du aktiverar dem, så att du förstår hur de kan påverka Autosens."
                )
            }
        }

        var AutosensView: some View {
            Section(
                header: !state.settingsManager.preferences
                    .useNewFormula ? Text("Autosens") : Text("Dynamic Sensitivity")
            ) {
                VStack {
                    let dynamicRatio = state.determinationsFromPersistence.first?.sensitivityRatio
                    let dynamicISF = state.determinationsFromPersistence.first?.insulinSensitivity
                    let newISF = state.autosensISF
                    HStack {
                        Text("Sensitivity Ratio")
                        Spacer()
                        Text(
                            rateFormatter
                                .string(from: (
                                    (
                                        !state.settingsManager.preferences.useNewFormula ? state
                                            .autosensRatio as NSDecimalNumber : dynamicRatio
                                    ) ?? 1
                                ) as NSNumber) ?? "1"
                        )
                    }.padding(.vertical)
                    HStack {
                        Text("Calculated Sensitivity")
                        Spacer()
                        if state.units == .mgdL {
                            Text(
                                !state.settingsManager.preferences
                                    .useNewFormula ? newISF!.description : (dynamicISF ?? 0).description
                            )
                        } else {
                            Text((
                                !state.settingsManager.preferences
                                    .useNewFormula ? newISF!.formattedAsMmolL : dynamicISF?.decimalValue.formattedAsMmolL
                            ) ?? "0")
                        }
                        Text(state.units.rawValue + "/E").foregroundColor(.secondary)
                    }

                    HStack(alignment: .top) {
                        Text(
                            "Denna justerade ISF är tillfällig, kommer att justeras vid varje loop, och bör inte användas direkt som inställning för din ISF-profil."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = "Autosens"
                                selectedVerboseHint = AnyView(autosensVerboseHint)
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
            }.listRowBackground(Color.chart)
        }

        var body: some View {
            List {
                if state.autosensISF != nil {
                    AutosensView
                }

                SettingInputSection(
                    decimalValue: $state.autosensMax,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Autosens Max", comment: "Autosens Max")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMax"),
                    label: NSLocalizedString("Autosens Max", comment: "Autosens Max"),
                    miniHint: "Övre gränsvärde för Autosens.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 120%").bold()
                        Text(
                            "Autosens Max anger den högsta Autosens-ration som får användas av Autosens, Dynamisk ISF och Sigmoid-formeln."
                        )

                        Text(
                            "Autosens-ration används för att beräkna hur mycket basalen, ISF och CR ska justeras."
                        )

                        Text(
                            "Tips: Om du ökar detta värde kan automatiska justeringar ge högre basal, lägre ISF och lägre CR."
                        )
                    },
                    headerText: "Algoritm för glukosavvikelser"
                )

                SettingInputSection(
                    decimalValue: $state.autosensMin,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Autosens Min", comment: "Autosens Min")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMin"),
                    label: NSLocalizedString("Autosens Min", comment: "Autosens Min"),
                    miniHint: "Lägre gränsvärde för Autosens.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 70%").bold()
                        Text(
                            "Autosens Min anger den lägsta Autosens-ration som får användas av Autosens, Dynamisk ISF och Sigmoid-formeln."
                        )

                        Text(
                            "Autosens-ration används för att beräkna hur mycket basal, ISF och CR ska justeras."
                        )

                        Text(
                            "Tips: Om du sänker detta värde kan automatiska justeringar ge lägre basal, högre ISF och högre CR."
                        )
                    }
                )
                /*
                 SettingInputSection(
                     decimalValue: $decimalPlaceholder,
                     booleanValue: $state.rewindResetsAutosens,
                     shouldDisplayHint: $shouldDisplayHint,
                     selectedVerboseHint: Binding(
                         get: { selectedVerboseHint },
                         set: {
                             selectedVerboseHint = $0.map { AnyView($0) }
                             hintLabel = NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens")
                         }
                     ),
                     units: state.units,
                     type: .boolean,
                     label: NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens"),
                     miniHint: "Pump rewind initiates a reset in Autosens Ratio.",
                     verboseHint: VStack(alignment: .leading, spacing: 5) {
                         Text("Default: ON").bold()
                         Text("Medtronic Users Only").bold()
                         VStack(alignment: .leading, spacing: 10) {
                             Text(
                                 "This feature resets the Autosens Ratio to neutral when you rewind your pump on the assumption that this corresponds to a site change."
                             )
                             Text(
                                 "Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours."
                             )
                             Text(
                                 "Tip: If you usually rewind your pump independently of site changes, you may want to consider disabling this feature."
                             )
                         }
                     }
                 )*/
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Autosens")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
