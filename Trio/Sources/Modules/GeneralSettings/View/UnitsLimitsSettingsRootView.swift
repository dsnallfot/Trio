import SwiftUI
import Swinject

extension UnitsLimitsSettings {
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

        var body: some View {
            List {
                Section(
                    header: Text("Trio grundinställningar"),
                    content: {
                        Picker("Glukosenhet", selection: $state.unitsIndex) {
                            Text("mg/dL").tag(0)
                            Text("mmol/L").tag(1)
                        }
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.maxIOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max IOB", comment: "Max IOB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxIOB"),
                    label: NSLocalizedString("Max IOB", comment: "Max IOB"),
                    miniHint: "Maximal mängd aktivt insulin som tillåts.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 0 enheter").bold()
                        Text(
                            "Varning: Detta värde måste vara större än 0 för att automatisk basaljustering och/eller SMB ska kunna ges."
                        ).bold()
                        Text(
                            "Detta är den maximala mängden aktivt insulin (IOB) utöver profilens basalnivåer från alla källor – positiva temporära basaler, manuella eller måltidsbolus samt SMB – som Trio tillåts ackumulera för att korrigera ett blodsocker över målvärdet."
                        )

                        Text(
                            "Om en beräknad insulindos överskrider denna gräns kommer den föreslagna och/eller levererade dosen att minskas så att den totala mängden aktivt insulin (IOB) inte överstiger denna säkerhetsgräns."
                        )

                        Text(
                            "Obs: Du kan fortfarande ge en manuell bolus över denna gräns, men den bolus som föreslås av boluskalkylatorn kommer aldrig att överstiga den."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxBolus,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Max Bolus"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBolus"),
                    label: "Max Bolus",
                    miniHint: "Största bolusdos som tillåts.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 10 enheter").bold()

                        Text(
                            "Detta är den största bolusdos som får levereras vid ett och samma tillfälle. Denna gräns gäller både manuella och automatiska boluser."
                        )

                        Text(
                            "De flesta sätter detta till storleken på sin största måltidsbolus och justerar sedan vid behov."
                        )

                        Text(
                            "Om du försöker ge en bolus som är större än denna gräns kommer bolusen inte att tillåtas."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxBasal,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Max Basal"
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBasal"),
                    label: "Max Basal",
                    miniHint: "Högsta basal som tillåts.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 2 enheter/h").bold()
                        Text(
                            "Detta är den högsta basal som får ställas in eller schemaläggas. Gränsen gäller både automatiska och manuella basaldoser."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxCOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max COB", comment: "Max COB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxCOB"),
                    label: NSLocalizedString("Max COB", comment: "Max COB"),
                    miniHint: "Maximal tillåten mängd aktiva kolhydrater (COB).",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 120 gram").bold()
                        Text(
                            "Denna inställning anger den högsta mängden aktiva kolhydrater (COB) som Trio får använda i doseringsberäkningar vid varje givet tillfälle. Om fler kolhydrater registreras än vad denna gräns tillåter kommer Trio att begränsa det aktuella COB-värdet i beräkningarna till Max COB och behålla det där tills de återstående kolhydraterna har absorberats."
                        )

                        Text(
                            "Exempel: Om Max COB är 120 g och du registrerar en måltid med 150 g kolhydrater kommer ditt COB att ligga kvar på 120 g tills de återstående 30 g har absorberats."
                        )

                        Text(
                            "Detta är en viktig säkerhetsgräns när UAM är aktiverat."
                        )
                    }
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
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Enheter & gränsvärden")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
