import SwiftUI
import Swinject

extension UserInterfaceSettings {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerLowThreshold: Bool = false
        @State private var displayPickerHighThreshold: Bool = false

        @AppStorage("colorSchemePreference") private var colorSchemePreference: ColorSchemeOption = .systemDefault

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            List {
                Section(
                    header: Text("Allmännt utseende"),
                    content: {
                        VStack {
                            Picker(
                                selection: $colorSchemePreference,
                                label: Text("Utseende")
                            ) {
                                ForEach(ColorSchemeOption.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Välj Trios utseende. Klicka på frågetecknet för mer info."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Föredraget färgschema"
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Ställer in Trios utseende. En beskrivning av varje alternativ finns nedan."
                                                    )

                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Systemstandard:").bold()
                                                        Text("Följer telefonens aktuella inställning för ljust eller mörkt läge.")
                                                    }

                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Ljust:").bold()
                                                        Text("Använder alltid ljust läge.")
                                                    }

                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Mörkt:").bold()
                                                        Text("Använder alltid mörkt läge.")
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
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.bottom)
                    }
                ).listRowBackground(Color.chart)

                Section {
                    VStack {
                        Picker(
                            selection: $state.glucoseColorScheme,
                            label: Text("Glukos färgschema")
                        ) {
                            ForEach(GlucoseColorScheme.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Välj färgschema för glukosvärden. Klicka på frågetecknet för mer info."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Glukos färgschema"
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Välj färgschema för glukosvärden på huvudgrafen, i Liveaktivitet och i boluskalkylatorn. En beskrivning av varje alternativ finns nedan."
                                                )

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Statiskt:").bold()
                                                    Text("Röd = Under målområdet")
                                                    Text("Grön = Inom målområdet")
                                                    Text("Gul = Över målområdet")
                                                }

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Dynamiskt:").bold()

                                                    Text("Grön = Vid glukosmålet")

                                                    Text(
                                                        "Tonas gradvis mot rött ju närmare glukosvärdet kommer, och ju längre det hamnar under glukosmålet."
                                                    )

                                                    Text(
                                                        "Tonas gradvis mot lila ju närmare glukosvärdet kommer, och ju längre det hamnar över glukosmålet."
                                                    )
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
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)

                Section(
                    header: Text("Inställningar för hemvyn"),
                    content: {
                        VStack {
                            Toggle("Visa rutnätslinjer för X-axeln", isOn: $state.xGridLines)
                            Toggle("Visa rutnätslinjer för Y-axeln", isOn: $state.yGridLines)

                            HStack(alignment: .center) {
                                Text(
                                    "Visa rutnätslinjer bakom glukosgrafen."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)

                                Spacer()

                                Button(
                                    action: {
                                        hintLabel = "Visa rutnätslinjer för X- och Y-axeln"

                                        selectedVerboseHint =
                                            AnyView(
                                                Text(
                                                    "Välj om rutnätslinjer för X-axeln, Y-axeln eller båda ska visas bakom glukosgrafen."
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
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rulerMarks,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa lågt och högt glukosgränsvärde"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa lågt och högt glukosgränsvärde",
                    miniHint: "Visar de låga och höga glukosgränsvärden som anges nedan.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Den här inställningen visar de övre och nedre gränserna för ditt glukosmålområde."
                        )

                        Text(
                            "Glukosmålområdet används endast för visning och statistik och påverkar inte insulindoseringen."
                        )
                    }
                )

                if state.rulerMarks {
                    Section {
                        VStack {
                            VStack {
                                HStack {
                                    Text("Lågt gränsvärde")

                                    Spacer()

                                    Group {
                                        Text(state.units == .mgdL ? state.low.description : state.low.asMmolL.description)
                                            .foregroundColor(!displayPickerLowThreshold ? .primary : .accentColor)

                                        Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    displayPickerLowThreshold.toggle()
                                }
                            }
                            .padding(.top)

                            if displayPickerLowThreshold {
                                let setting = PickerSettingsProvider.shared.settings.low

                                Picker(selection: $state.low, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        let displayValue = state.units == .mgdL ? value : value.asMmolL
                                        Text("\(displayValue.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            VStack {
                                HStack {
                                    Text("Högt gränsvärde")

                                    Spacer()

                                    Group {
                                        Text(state.units == .mgdL ? state.high.description : state.high.asMmolL.description)
                                            .foregroundColor(!displayPickerHighThreshold ? .primary : .accentColor)

                                        Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    displayPickerHighThreshold.toggle()
                                }
                            }
                            .padding(.top)

                            if displayPickerHighThreshold {
                                let setting = PickerSettingsProvider.shared.settings.high
                                Picker(selection: $state.high, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        let displayValue = state.units == .mgdL ? value : value.asMmolL
                                        Text("\(displayValue.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            HStack(alignment: .center) {
                                Text(
                                    "Ange låga och höga glukosgränsvärden för glukosgrafen på hemskärmen och för statistik."
                                )
                                .lineLimit(nil)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()

                                Button(
                                    action: {
                                        hintLabel = "Lågt och högt glukosgränsvärde"

                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Standardvärdena bygger på de internationellt vedertagna gränserna för Tid inom målområdet: \(state.units == .mgdL ? "70" : 70.formattedAsMmolL)–\(state.units == .mgdL ? "180" : 180.formattedAsMmolL) \(state.units.rawValue)."
                                                    )
                                                    .bold()

                                                    Text(
                                                        "Justera dessa värden om du vill att statistiken ska baseras på andra gränser än standardvärdena för Tid inom målområdet."
                                                    )

                                                    Text(
                                                        "Obs: Dessa värden används inte vid beräkning av insulindosering."
                                                    )
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
                            }.padding(.top)
                        }.padding(.bottom)
                    }.listRowBackground(Color.chart)
                }

                Section {
                    VStack {
                        Picker(
                            selection: $state.forecastDisplayType,
                            label: Text("Visningstyp för glukosprognos")
                        ) {
                            ForEach(ForecastDisplayType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Välj hur glukosprognosen ska visas. Se hjälptexten för mer information."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)

                            Spacer()

                            Button(
                                action: {
                                    hintLabel = "Visningstyp för glukosprognos"

                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Den här inställningen låter dig välja mellan osäkerhetskonen och OpenAPS prognoslinjer för visning av glukosprognosen. En beskrivning av varje alternativ finns nedan."
                                                )

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Osäkerhetskon:").bold()

                                                    Text(
                                                        "Visar det samlade intervallet från alla möjliga prognoser i OpenAPS-linjerna och ger därmed ett spann av möjliga glukosutvecklingar. Det här alternativet har visat sig kunna minska förvirring och oro kring algoritmens prognoser genom att presentera dem på ett mindre alarmerande sätt."
                                                    )
                                                }

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Prognoslinjer:").bold()

                                                    Text(
                                                        "Visar prognoslinjerna för IOB, COB, UAM och ZT från OpenAPS. Det här alternativet ger en mer detaljerad bild av algoritmens prognos, men kan upplevas som mer svårtolkat av vissa användare."
                                                    )
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
                    .padding(.bottom)
                }.listRowBackground(Color.chart)

                Section {
                    VStack(alignment: .leading) {
                        Picker(
                            selection: $state.totalInsulinDisplayType,
                            label: Text("Visning av totalt insulin")
                                .multilineTextAlignment(.leading)
                        ) {
                            ForEach(TotalInsulinDisplayType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Välj vilken beräkning av totalt insulin som ska visas på hemskärmen. Se hjälptexten för mer information."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)

                            Spacer()

                            Button(
                                action: {
                                    hintLabel = "Visning av totalt insulin"

                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Välj om Total dygnsdos (TDD) eller Totalt insulin inom tidsintervallet (TINS) ska visas ovanför huvudgrafen. En beskrivning av varje alternativ finns nedan."
                                                )

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Total dygnsdos (TDD):").bold()

                                                    Text(
                                                        "Visar den totala mängden insulin som har administrerats under de senaste 24 timmarna, inklusive både basalinsulin och boluser."
                                                    )
                                                }

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Totalt insulin inom tidsintervallet (TINS):").bold()

                                                    Text(
                                                        "Visar den totala mängden insulin som har getts som bolus (manuell eller SMB) samt via temporära basalhastigheter över 0 E/timme under det tidsintervall som visas i huvudgrafen."
                                                    )
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
                    .padding(.bottom)
                }.listRowBackground(Color.chart)

                Section(
                    header: Text("Trio-statistik"),
                    content: {
                        VStack {
                            Picker(
                                selection: $state.hbA1cDisplayUnit,
                                label: Text("Enhet för visning av HbA1c")
                            ) {
                                ForEach(HbA1cDisplayUnit.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }
                            .padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Välj om HbA1c ska visas i procent eller mmol/mol."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)

                                Spacer()

                                Button(
                                    action: {
                                        hintLabel = "Enhet för visning av HbA1c"

                                        selectedVerboseHint =
                                            AnyView(
                                                Text(
                                                    "Välj vilket format HbA1c ska visas i på statistikskärmen: procent (till exempel 6,5 %) eller mmol/mol (till exempel 48 mmol/mol)."
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
                        .padding(.bottom)
                    }
                ).listRowBackground(Color.chart)

                Section {
                    VStack(alignment: .leading) {
                        Picker(
                            selection: $state.timeInRangeChartStyle,
                            label: Text("Diagramtyp tid inom mål")
                                .multilineTextAlignment(.leading)
                        ) {
                            ForEach(TimeInRangeChartStyle.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Välj hur diagrammet för Tid inom målområdet ska visas."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)

                            Spacer()

                            Button(
                                action: {
                                    hintLabel = "Diagramtyp tid inom mål"

                                    selectedVerboseHint =
                                        AnyView(
                                            Text(
                                                "Välj om diagrammet för Tid inom målområdet ska visas som ett stående stapeldiagram (vertikalt) eller som ett liggande stapeldiagram (horisontellt)."
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
                    .padding(.bottom)
                }.listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.carbsRequiredThreshold,
                    booleanValue: $state.showCarbsRequiredBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa indikator för kolhydratbehov"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("carbsRequiredThreshold"),
                    label: "Visa indikator för kolhydratbehov",
                    conditionalLabel: "Gränsvärde för kolhydratbehov",
                    miniHint: "Visar en röd indikator för rekommenderat kolhydratbehov ovanför huvudgrafen.",
                    verboseHint: Text(
                        """
                        När denna funktion är aktiverad visas den rekommenderade mängden kolhydrater som behövs för att förebygga lågt blodsocker som en röd indikator ovanför huvudgrafen på Trio-hemskärmen.

                        När funktionen är aktiverad kan du ange ett gränsvärde för kolhydratbehov. En rekommendation visas endast om det beräknade kolhydratbehovet är lika med eller högre än detta värde.

                        Obs: Den rekommenderade mängden kolhydrater är endast avsedd som vägledning och ska inte betraktas som ett absolut behov. Beroende på sensorns aktuella noggrannhet och hur väl dina inställningar är anpassade kan den rekommenderade mängden variera avsevärt. Använd alltid ditt eget omdöme innan du äter den föreslagna mängden kolhydrater.
                        """
                    ),
                    headerText: "Indikator för kolhydratbehov"
                )
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
            .navigationBarTitle("Användargränssnitt")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
