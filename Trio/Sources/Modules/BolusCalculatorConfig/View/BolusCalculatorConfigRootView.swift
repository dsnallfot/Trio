import SwiftUI
import Swinject

extension BolusCalculatorConfig {
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
        @Environment(AppState.self) var appState

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.displayPresets,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Sparade måltider"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Sparade måltider",
                    miniHint: "Tillåt att måltider sparas som förval.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: PÅ").bold()
                        Text("Aktivera denna funktion för att kunna skapa och spara förvalda måltider.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.overrideFactor,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Rekommenderad bolusprocent"
                        }
                    ),
                    units: state.units,
                    type: .decimal("overrideFactor"),
                    label: "Rekommenderad bolusprocent",
                    miniHint: "Procent av beräknat totalt bolusbehov som föreslås i boluskalkylatorn.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 80%").bold()
                        Text(
                            "Rekommenderad bolusprocent är en inbyggd säkerhetsfunktion i Trio. Först beräknar Trio hur mycket insulin som behövs, vilket motsvarar den fullständigt beräknade dosen. Därefter multipliceras denna dos med din inställda rekommenderade bolusprocent för att beräkna den bolus som föreslås i boluskalkylatorn."
                        )

                        Text(
                            "Eftersom Trio använder SMB och UAM-SMB för att hjälpa dig att nå ditt glukosmål, och andra AID-system inte doserar för COB på samma sätt som Trio, är standardvärdet satt till 80 % av den beräknade dosen. När SMB och UAM-SMB är aktiverade kan du märka att ditt nuvarande kolhydratförhållande (CR) leder till låga glukosvärden. I så fall kan CR behöva höjas innan du ökar denna inställning mot eller upp till 100 %."
                        )

                        Text(
                            "Tips: Om du är ny användare av Trio rekommenderas det att inte höja denna inställning till 100 % förrän du har verifierat att dina grundinställningar – basalhastigheter, ISF och CR – inte behöver justeras."
                        )
                    },
                    headerText: "Boluskalkylator konfiguration"
                )

                SettingInputSection(
                    decimalValue: $state.fattyMealFactor,
                    booleanValue: $state.fattyMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Fet mat"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("fattyMealFactor"),
                    label: "Aktivera val för fet mat",
                    conditionalLabel: "Bolusprocent för fet mat",
                    miniHint: "Lägg till ett val för måltider som absorberas långsamt.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text("Standardprocent: 70%").bold()
                        Text("Aktivera endast denna funktion om du har testat och optimerat din insulinkvot (CR).").bold()
                        Text(
                            "När denna inställning är aktiverad läggs alternativet 'Fet mat' till i boluskalkylatorn. När funktionen har aktiverats visas även en inställning där du kan välja en procentandel för Fet mat."
                        )

                        Text(
                            "Om 'Fet mat' är valt i boluskalkylatorn multipliceras den rekommenderade bolusen både med 'Bolusprocent för fet mat' och med 'Rekommenderad bolusprocent'."
                        )

                        Text(
                            "Om du har en rekommenderad bolusprocent på 80 % och en bolusprocent för fet mat på 70 % beräknas den rekommenderade bolusen enligt: (80 × 70) ÷ 100 = 56 %."
                        )

                        Text(
                            "Detta kan vara användbart för måltider som absorberas långsamt, till exempel pizza."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.sweetMealFactor,
                    booleanValue: $state.sweetMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Superbolus"
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("sweetMealFactor"),
                    label: "Aktivera val för superbolus",

                    conditionalLabel: "Superbolusprocent",

                    miniHint: "Lägg till ett val för måltider som absorberas snabbt.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text("Standardprocent: 100 %").bold()

                        Text("Aktivera inte denna funktion förrän du har testat och optimerat din insulinkvot (CR).").bold()

                        Text(
                            "När denna inställning är aktiverad läggs alternativet 'Superbolus' till i boluskalkylatorn. När funktionen har aktiverats visas även en inställning där du kan välja en superbolusprocent."
                        )

                        Text(
                            "När 'Superbolus' är valt i boluskalkylatorn läggs den aktuella basalhastigheten, multiplicerad med superbolusprocenten, till den rekommenderade bolusen."
                        )

                        Text(
                            "Om din aktuella basalhastighet är 0,8 E/timme och superbolusprocenten är inställd på 200 %: 0,8 × (200 ÷ 100) = 1,6 E läggs till den rekommenderade bolusen."
                        )

                        Text(
                            "Detta kan vara användbart för måltider som absorberas snabbt, till exempel sötade frukostflingor."
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
            .navigationBarTitle("Boluskalkylator")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
