import ActivityKit
import Combine
import SwiftUI
import Swinject

extension GlucoseNotificationSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerLowGlucose: Bool = false
        @State private var displayPickerHighGlucose: Bool = false

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

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useAlarmSound,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Spela upp larmljud"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Spela upp larmljud",
                    miniHint: "Spela upp ett larmljud vid Trio-notiser.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "När denna funktion är aktiverad spelas ett larmljud upp för Trio-notiser om kolhydratbehov samt vid larm för lågt och högt glukos."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsPump,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa alltid pumpnotiser"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa alltid pumpnotiser",
                    miniHint: "Visa alltid pumpvarningar.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: På").bold()

                        Text(
                            "När Trio-notiser är aktiverade i iOS kan Trio visa de flesta pumpnotiser i iOS Notiscenter som banderoller, i notislistan och på låsskärmen. Det gör det enkelt att snabbt se viktig information och felsöka eventuella problem. Ställ in Banderollstil i iOS på Bestående om du vill att banderoller ska ligga kvar tills de avfärdas."
                        )

                        Text(
                            "Om Trio-notiser är avstängda i iOS visas dessa meddelanden endast som en banderoll i appen."
                        )

                        Text(
                            "Exempel på en pumpvarning: \"Påminnelse om poddens utgångstid\"."
                        )
                    },
                    headerText: "Informationsnotiser från Trio"
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsCgm,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa alltid CGM-notiser"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa alltid CGM-notiser",
                    miniHint: "Visa alltid CGM-varningar.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: På").bold()

                        Text(
                            "När Trio-notiser är aktiverade i iOS kan Trio visa de flesta CGM-notiser i iOS Notiscenter som banderoller, i notislistan och på låsskärmen. Det gör det enkelt att snabbt se viktig information och felsöka eventuella problem. Ställ in Banderollstil i iOS på Bestående om du vill att banderoller ska ligga kvar tills de avfärdas."
                        )

                        Text(
                            "Om Trio-notiser är avstängda i iOS visas dessa meddelanden endast som en banderoll i appen."
                        )

                        Text(
                            "Exempel på en CGM-varning: \"Det gick inte att öppna appen\"."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsCarb,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa alltid kolhydratnotiser"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa alltid kolhydratnotiser",
                    miniHint: "Visa alltid kolhydratvarningar.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: På").bold()

                        Text(
                            "När Trio-notiser är aktiverade i iOS kan Trio visa de flesta kolhydratnotiser i iOS Notiscenter som banderoller, i notislistan och på låsskärmen. Det gör det enkelt att snabbt se viktig information och felsöka eventuella problem. Ställ in Banderollstil i iOS på Bestående om du vill att banderoller ska ligga kvar tills de avfärdas."
                        )

                        Text(
                            "Om Trio-notiser är avstängda i iOS visas dessa meddelanden endast som en banderoll i appen."
                        )

                        Text(
                            "Exempel på en kolhydratvarning: \"Kolhydratbehov: 30 g\"."
                        )
                    }
                )
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsAlgorithm,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa alltid algoritmnotiser"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa alltid algoritmnotiser",
                    miniHint: "Visa alltid varningar från algoritmen.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: På").bold()

                        Text(
                            "När Trio-notiser är aktiverade i iOS kan Trio visa de flesta algoritmnotiser i iOS Notiscenter som banderoller, i notislistan och på låsskärmen. Det gör det enkelt att snabbt se viktig information och felsöka eventuella problem. Ställ in Banderollstil i iOS på Bestående om du vill att banderoller ska ligga kvar tills de avfärdas."
                        )

                        Text(
                            "Om Trio-notiser är avstängda i iOS visas dessa meddelanden endast som en banderoll i appen."
                        )

                        Text(
                            "Exempel på en algoritmvarning: \"Fel: Ogiltigt glukosvärde – otillräckligt med glukosdata\"."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsRemote,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa alltid notiser för fjärrkommandon"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa alltid notiser för fjärrkommandon",
                    miniHint: "Visa alltid mottagna fjärrkommandon.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "När Trio-notiser är aktiverade i iOS kan Trio visa notiser om mottagna fjärrkommandon i iOS Notiscenter som banderoller, i notislistan och på låsskärmen. Det gör det enkelt att snabbt se viktig information och felsöka eventuella problem. Ställ in Banderollstil i iOS på Bestående om du vill att banderoller ska ligga kvar tills de avfärdas."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.glucoseBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Visa glukosindikator på appikonen"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Visa glukosindikator på appikonen",
                    miniHint: "Visa ditt aktuella glukosvärde på Trio-appens ikon.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "Detta visar ditt aktuella glukosvärde som en röd notifieringsindikator uppe till höger på Trio-appens ikon. Ändringen börjar gälla vid nästa glukosvärde."
                        )
                    },
                    headerText: "Övriga glukosnotiser"
                )

                Section {
                    VStack {
                        Picker(
                            selection: $state.glucoseNotificationsOption,
                            label: Text("Glukosnotiser")
                        ) {
                            ForEach(GlucoseNotificationsOption.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Välj hur glukosnotiser ska användas. Se hjälptexten för mer information."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)

                            Spacer()

                            Button(
                                action: {
                                    hintLabel = "Glukosnotiser"

                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Välj hur glukosnotiser ska visas. En beskrivning av varje alternativ finns nedan."
                                                )

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Avaktiverade:").bold()
                                                    Text(
                                                        "Inga glukosnotiser kommer att skickas."
                                                    )
                                                }

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Alltid:").bold()
                                                    Text(
                                                        "En notis skickas varje gång glukosvärdet uppdateras i Trio."
                                                    )
                                                }

                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Endast vid larmgränser:").bold()
                                                    Text(
                                                        "En notis skickas endast när glukosvärdet ligger under den låga larmgränsen eller över den höga larmgränsen som anges under Glukoslarmgränser nedan."
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
                }
                .listRowBackground(Color.chart)

                if state.glucoseNotificationsOption != GlucoseNotificationsOption.disabled {
                    self.lowAndHighGlucoseAlertSection

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.addSourceInfoToGlucoseNotifications,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Lägg till glukoskälla i larmet"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Lägg till glukoskälla i larmet",
                        miniHint: "Glukosvärdets källa läggs till i notisen.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()

                            Text(
                                "Källan till glukosvärdet läggs till i notisen."
                            )
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
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("Trio-notiser")
            .navigationBarTitleDisplayMode(.automatic)
        }

        var lowAndHighGlucoseAlertSection: some View {
            Section {
                VStack {
                    VStack {
                        HStack {
                            Text("Låg glukoslarmgräns")

                            Spacer()

                            Group {
                                Text(
                                    state.units == .mgdL
                                        ? state.lowGlucose.description
                                        : state.lowGlucose.formattedAsMmolL
                                )
                                .foregroundColor(
                                    !displayPickerLowGlucose ? .primary : .accentColor
                                )

                                Text(
                                    state.units == .mgdL ? " mg/dL" : " mmol/L"
                                )
                                .foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            displayPickerLowGlucose.toggle()
                        }
                    }
                    .padding(.top)

                    if displayPickerLowGlucose {
                        let setting = PickerSettingsProvider.shared.settings.lowGlucose

                        Picker(selection: $state.lowGlucose, label: Text("")) {
                            ForEach(
                                PickerSettingsProvider.shared.generatePickerValues(
                                    from: setting,
                                    units: state.units
                                ),
                                id: \.self
                            ) { value in
                                let displayValue = state.units == .mgdL
                                    ? value.description
                                    : value.formattedAsMmolL

                                Text(displayValue).tag(value)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }

                    VStack {
                        HStack {
                            Text("Hög glukoslarmgräns")

                            Spacer()

                            Group {
                                Text(
                                    state.units == .mgdL
                                        ? state.highGlucose.description
                                        : state.highGlucose.formattedAsMmolL
                                )
                                .foregroundColor(
                                    !displayPickerHighGlucose ? .primary : .accentColor
                                )

                                Text(
                                    state.units == .mgdL ? " mg/dL" : " mmol/L"
                                )
                                .foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            displayPickerHighGlucose.toggle()
                        }
                    }
                    .padding(.top)

                    if displayPickerHighGlucose {
                        let setting = PickerSettingsProvider.shared.settings.highGlucose

                        Picker(selection: $state.highGlucose, label: Text("")) {
                            ForEach(
                                PickerSettingsProvider.shared.generatePickerValues(
                                    from: setting,
                                    units: state.units
                                ),
                                id: \.self
                            ) { value in
                                let displayValue = state.units == .mgdL
                                    ? value.description
                                    : value.formattedAsMmolL

                                Text(displayValue).tag(value)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }

                    HStack(alignment: .center) {
                        Text(
                            "Anger den låga och höga larmgränsen för glukos."
                        )
                        .lineLimit(nil)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                        Spacer()

                        Button(
                            action: {
                                hintLabel = "Låg och hög glukoslarmgräns"

                                selectedVerboseHint =
                                    AnyView(
                                        VStack(alignment: .leading, spacing: 10) {
                                            let low: Decimal = 70
                                            let high: Decimal = 180

                                            let labelLow =
                                                (
                                                    state.units == .mgdL
                                                        ? low.description
                                                        : low.formattedAsMmolL
                                                ) + " " + state.units.rawValue

                                            let labelHigh =
                                                (
                                                    state.units == .mgdL
                                                        ? high.description
                                                        : high.formattedAsMmolL
                                                ) + " " + state.units.rawValue

                                            Text("Lågt standardvärde: " + labelLow)
                                                .bold()

                                            Text("Högt standardvärde: " + labelHigh)
                                                .bold()

                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Dessa två inställningar anger det glukosintervall utanför vilket du får en pushnotis."
                                                )

                                                Text(
                                                    "Om CGM-värdet ligger under den låga gränsen eller över den höga gränsen får du ett glukoslarm."
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
                    }.padding(.top)
                }.padding(.bottom)
            }.listRowBackground(Color.chart)
        }
    }
}
