import SwiftUI
import Swinject

extension MealSettings {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerMaxCarbs: Bool = false
        @State private var displayPickerMaxFat: Bool = false
        @State private var displayPickerMaxProtein: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var intFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            List {
                Section(
                    header: Text("Begränsning per registrering"),
                    content: {
                        VStack {
                            VStack {
                                HStack {
                                    Text("Max kolhydrater")

                                    Spacer()

                                    Group {
                                        Text(state.maxCarbs.description)
                                            .foregroundColor(!displayPickerMaxCarbs ? .primary : .accentColor)

                                        Text(" g").foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    displayPickerMaxCarbs.toggle()
                                }
                            }.padding(.top)

                            if displayPickerMaxCarbs {
                                let setting = PickerSettingsProvider.shared.settings.maxCarbs
                                Picker(selection: $state.maxCarbs, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        Text("\(value.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            if state.useFPUconversion {
                                VStack {
                                    HStack {
                                        Text("Max protein")

                                        Spacer()

                                        Group {
                                            Text(state.maxProtein.description)
                                                .foregroundColor(!displayPickerMaxProtein ? .primary : .accentColor)

                                            Text(" g").foregroundColor(.secondary)
                                        }
                                    }
                                    .onTapGesture {
                                        displayPickerMaxProtein.toggle()
                                    }
                                }
                                .padding(.top)

                                if displayPickerMaxProtein {
                                    let setting = PickerSettingsProvider.shared.settings.maxProtein
                                    Picker(selection: $state.maxProtein, label: Text("")) {
                                        ForEach(
                                            PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                            id: \.self
                                        ) { value in
                                            Text("\(value.description)").tag(value)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }

                                VStack {
                                    HStack {
                                        Text("Max fett")

                                        Spacer()

                                        Group {
                                            Text(state.maxFat.description)
                                                .foregroundColor(!displayPickerMaxFat ? .primary : .accentColor)

                                            Text(" g").foregroundColor(.secondary)
                                        }
                                    }
                                    .onTapGesture {
                                        displayPickerMaxFat.toggle()
                                    }
                                }
                                .padding(.top)

                                if displayPickerMaxFat {
                                    let setting = PickerSettingsProvider.shared.settings.maxFat
                                    Picker(selection: $state.maxFat, label: Text("")) {
                                        ForEach(
                                            PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                            id: \.self
                                        ) { value in
                                            Text("\(value.description)").tag(value)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }
                            }

                            HStack(alignment: .center) {
                                Text(
                                    "Set gränser för varje typ av makronutrient per måltidsregistrering."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Gräns per registreringLimits per Entry"
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Max kolhydrater:").bold()
                                                    Text("Ange den största mängden kolhydrater som tillåts per registrering.")
                                                    Text("Max fett:").bold()
                                                    Text("Ange den största mängden fett som tillåts per registrering.")
                                                    Text("Max protein:").bold()
                                                    Text("Ange den största mängden protein som tillåts per registrering.")
                                                }
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
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.maxMealAbsorptionTime,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Maximal måltidsabsorptionstid"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxMealAbsorptionTime"),
                    label: "Maximal måltidsabsorptionstid",
                    miniHint: "Den längsta tid som kolhydrater följs för att beräkna kolhydrater ombord (COB).",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 6 timmar").bold()

                        Text(
                            "Registrerade kolhydrater kommer att vara helt avräknade efter det antal timmar som anges som maximal måltidsabsorptionstid. Måltider med mycket fett och/eller protein kan påverka glukosnivån under lång tid. För att sådana sena måltidseffekter ska kunna tas med i beräkningen av kolhydratabsorption kan en längre maximal måltidsabsorptionstid än standardvärdet på 6 timmar användas."
                        )

                        Text(
                            "Om registrerade kolhydrater räknas av för långsamt kan ett lägre värde än standard användas. I de flesta fall är det dock bättre att justera ISF och CR, eftersom dessa tillsammans avgör hur snabbt kolhydrater räknas av."
                        )

                        Text(
                            "Minst 4 timmar, högst 10 timmar."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useFPUconversion,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Aktivera registrering av fett och protein"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Aktivera registrering av fett och protein",
                    miniHint: "Lägg till fett och protein i måltidsregistreringar.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        VStack(spacing: 10) {
                            Text(
                                "När denna inställning är aktiverad kan du registrera mängden fett och protein i dina måltider. Dessa omvandlas sedan till framtida kolhydratekvivalenter med hjälp av Warszawa-metoden."
                            )

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Warszawa-metoden").bold()

                                Text(
                                    "Warszawa-metoden tar hänsyn till de fördröjda glukosstegringar som fett och protein kan orsaka efter en måltid. Den använder fett-proteinenheter (FPU) för att beräkna kolhydrateffekten från fett och protein. Därefter fördelas insulintillförseln över flera timmar för att efterlikna kroppens naturliga insulinbehov och minska glukosstegringar efter måltider."
                                )
                            }

                            VStack(alignment: .center, spacing: 5) {
                                Text("Omvandling av fett").bold()

                                Text("𝑭 = fett (g) × 90 %")
                            }

                            VStack(alignment: .center, spacing: 5) {
                                Text("Omvandling av protein").bold()

                                Text("𝑷 = protein (g) × 40 %")
                            }

                            VStack(alignment: .center, spacing: 5) {
                                Text("FPU-omvandling").bold()

                                Text("𝑭 + 𝑷 = g kolhydrater")
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    "När denna funktion är aktiverad kan du anpassa beräkningen ytterligare med följande inställningar:"
                                )

                                Text("• Fördröjning för fett och protein")

                                Text("• Andel fett och protein")
                            }
                        }
                    },
                    headerText: "Fett och protein"
                )
                if state.useFPUconversion {
                    SettingInputSection(
                        decimalValue: $state.delay,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Fördröjning för fett och protein"
                            }
                        ),
                        units: state.units,
                        type: .decimal("delay"),
                        label: "Fördröjning för fett och protein",
                        miniHint: "Tidsfördröjning mellan registrering av fett och protein och den första FPU-beräkningen.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: 60 min").bold()

                            Text(
                                "Inställningen Fördröjning för fett och protein anger hur lång tid som ska gå mellan att du registrerar fett och protein och att systemet börjar dosera insulin för de kolhydratekvivalenter som beräknas från fett-proteinenheter (FPU)."
                            )

                            Text(
                                "Denna fördröjning tar hänsyn till att fett och protein absorberas långsammare än kolhydrater, enligt Warszawa-metoden. På så sätt kan insulinet ges vid rätt tidpunkt för att bättre hantera glukosstegringar efter måltider med högt innehåll av fett och protein."
                            )
                        }
                    )
                    /*
                     SettingInputSection(
                         decimalValue: $state.timeCap,
                         booleanValue: $booleanPlaceholder,
                         shouldDisplayHint: $shouldDisplayHint,
                         selectedVerboseHint: Binding(
                             get: { selectedVerboseHint },
                             set: {
                                 selectedVerboseHint = $0.map { AnyView($0) }
                                 hintLabel = "Maximum Duration"
                             }
                         ),
                         units: state.units,
                         type: .decimal("timeCap"),
                         label: "Maximum Duration",
                         miniHint: "Set the maximum timeframe to extend FPUs.",
                         verboseHint:
                         VStack(alignment: .leading, spacing: 10) {
                             Text("Default: 8 hours").bold()
                             Text(
                                 "This sets the maximum length of time that Fat and Protein Carb Equivalents (FPUs) will be extended over from a single Fat and/or Protein bolus calcultor entry."
                             )
                             Text(
                                 "It is one factor used in combination with the Fat and Protein Delay, Spread Interval, and Fat and Protein Factor to create the FPU entries."
                             )
                             Text("Increasing this setting may result in more FPU entries with smaller carb values.")
                             Text("Decreasing this setting may result in fewer FPU entries with larger carb values.")
                         }
                     )
                     */
                    /*
                     SettingInputSection(
                         decimalValue: $state.minuteInterval,
                         booleanValue: $booleanPlaceholder,
                         shouldDisplayHint: $shouldDisplayHint,
                         selectedVerboseHint: Binding(
                             get: { selectedVerboseHint },
                             set: {
                                 selectedVerboseHint = $0.map { AnyView($0) }
                                 hintLabel = "Spread Interval"
                             }
                         ),
                         units: state.units,
                         type: .decimal("minuteInterval"),
                         label: "Spread Interval",
                         miniHint: "Time interval between FPUs.",
                         verboseHint:
                         VStack(alignment: .leading, spacing: 10) {
                             Text("Default: 30 minutes").bold()
                             Text(
                                 "This determines how many minutes will be between individual Fat-Protein Unit Carb Equivalent (FPU) entries from a single Fat and/or Protein bolus calculator entry."
                             )
                             Text("The shorter the interval, the smoother the correlating dosing result.")
                             Text("Increasing this setting may result in fewer FPU entries with larger carb values.")
                             Text("Decreasing this setting may result in more FPU entries with smaller carb values.")
                         }
                     )
                     */

                    SettingInputSection(
                        decimalValue: $state.individualAdjustmentFactor,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Andel fett och protein"
                            }
                        ),
                        units: state.units,
                        type: .decimal("individualAdjustmentFactor"),
                        label: "Andel fett och protein",
                        miniHint: "Justerar FPU-omvandlingen enligt Warszawa-metoden.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: 50 %").bold()

                            VStack(spacing: 10) {
                                Text(
                                    "Den här inställningen avgör hur stor påverkan registrerat fett och protein har på beräkningen av fett-proteinenheter (FPU)."
                                )

                                VStack(alignment: .center, spacing: 5) {
                                    Text("50 % ger halv effekt:").bold()
                                    Text("(Fett × 45 %) + (Protein × 20 %)")

                                    Text("100 % ger full effekt:").bold()
                                    Text("(Fett × 90 %) + (Protein × 40 %)")

                                    Text("110 % gör förhållandet mellan fett och kolhydrater i princip 1:1:").bold()
                                    Text("(Fett × 99 %) + (Protein × 44 %)")
                                }
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                                Text(
                                    "Tips: När du börjar registrera fett och protein kan du märka att ditt vanliga kolhydratförhållande (CR) behöver höjas. Därför rekommenderas att börja med en faktor på omkring 50 %."
                                )
                            }
                        }
                    )
                }
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
            .navigationBarTitle("Måltidsinställningar")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
