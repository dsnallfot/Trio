import SwiftUI
import Swinject

extension DynamicSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useNewFormula,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Aktivera dynamisk insulinkänslighet (Dynamisk ISF)"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Aktivera dynamisk ISF",
                    miniHint: "Dynamisk justering av insulinkänslighet genom användning av dynamisk ratio istället för Autosens ratio.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text(
                            "När denna funktion är aktiverad beräknar Trio en ny insulinkänslighetsfaktor (ISF) vid varje loopcykel. Beräkningen baseras bland annat på ditt aktuella glukosvärde, den viktade totala dygnsdosen insulin (TDD), den inställda justeringsfaktorn och flera andra parametrar. Detta gör att insulinresponsen kan anpassas mer exakt i realtid."
                        )

                        Text(
                            "Dynamisk ISF beräknar ett dynamiskt förhållande som ersätter Autosens-förhållandet. Detta avgör hur mycket din profil-ISF ska justeras vid varje loopcykel, samtidigt som justeringarna hålls inom de säkra gränser som anges av Autosens Min och Autosens Max. Resultatet blir en mer exakt insulindosering som anpassar sig efter förändringar i insulinbehovet under dagen."
                        )

                        Text(
                            "Du kan främst påverka hur Dynamisk ISF justerar insulinbehovet genom att ändra Autosens Max, Autosens Min och Justeringsfaktorn. Även andra inställningar påverkar Dynamisk ISF, till exempel Glukosmål, Profil-ISF, Insulinets topptid och Viktat genomsnitt av TDD."
                        )

                        Text(
                            "Varning: Innan du ändrar dessa inställningar bör du vara helt säker på vilken påverkan ändringarna kommer att ha."
                        )
                        .bold()
                    },
                    headerText: "Dynamiska inställningar"
                )

                if state.useNewFormula {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableDynamicCR,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Aktivera Dynamisk CR (Insulinkvot)"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Aktivera dynamisk CR",
                        miniHint: "Dynamisk justering av din insulinkvot (CR).",
                        verboseHint:

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "Dynamisk CR justerar ditt kolhydratförhållande utifrån det dynamiska förhållandet och anpassar det automatiskt efter förändringar i din insulinkänslighet."
                            )

                            Text(
                                "När det dynamiska förhållandet ökar, vilket innebär att du behöver mer insulin, minskas kolhydratförhållandet så att insulindoseringen blir mer effektiv."
                            )

                            Text(
                                "När det dynamiska förhållandet minskar, vilket innebär att du behöver mindre insulin, ökas kolhydratförhållandet för att undvika att för mycket insulin ges."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.sigmoid,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Använd Sigmoid formel"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Använd Sigmoid formel",
                        miniHint: "Justera insulinkänsligheten utifrån en sigmoid-formad kurva.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "När inställningen *Använd Sigmoid formel' är aktiverad ändras hur det dynamiska förhållandet, och därmed din nya ISF och nya insulinkvot, beräknas. I stället för den vanliga logaritmiska funktionen används en sigmoidkurva."
                            )

                            Text(
                                "Kurvans branthet påverkas av Justeringsfaktorn, medan Autosens Min och Autosens Max anger gränserna för förhållandets justering. Dessa inställningar kan också påverka sigmoidkurvans branthet."
                            )

                            Text(
                                "När Sigmoid formeln används har den viktade totala dygnsdosen insulin (TDD) betydligt mindre påverkan på de dynamiska justeringarna av insulinkänsligheten."
                            )

                            Text(
                                "Noggrann finjustering är viktig för att undvika alltför aggressiva förändringar av insulindoseringen."
                            )

                            Text(
                                "För att bibehålla en säker insulindosering rekommenderas det inte att sätta Autosens Max högre än 150 %."
                            )
                            .bold()
                        }
                    )

                    if !state.sigmoid {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactor,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = "Justeringsfaktor (AF)"
                                }
                            ),
                            // TODO?: include conditional links to Desmos logarithmic graphs based on which .glucose setting is used
                            units: state.units,
                            type: .decimal("adjustmentFactor"),
                            label: "Justeringsfaktor (AF)",
                            miniHint: "Justera aggressiviteten för dynamisk ISF.",
                            verboseHint:
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Standard: 80%").bold()
                                Text(
                                    "Justeringsfaktorn (AF) låter dig styra hur snabbt och effektivt Dynamisk ISF reagerar på förändringar i glukosnivån."
                                )

                                Text(
                                    "Genom att ändra detta värde kan du inte bara påverka hur snabbt insulinkänsligheten anpassas till förändrade glukosvärden, utan även vid vilka glukosnivåer Autosens Max- och Autosens Min-gränserna uppnås."
                                )

                                Text(
                                    "Om du ökar detta värde sker ISF-justeringarna snabbare, men det ändrar också vilka glukosvärden som motsvarar den ISF som används vid Autosens Max och Autosens Min. Om du i stället sänker värdet sker ISF-justeringarna långsammare, och även då förändras vilka glukosvärden som motsvarar ISF vid Autosens Max och Autosens Min. För bästa resultat rekommenderas att använda Desmos-graferna på TrioDocs.org för att optimera alla dynamiska inställningar."
                                )
                            }
                        )
                    } else {
                        SettingInputSection(
                            decimalValue: $state.adjustmentFactorSigmoid,
                            booleanValue: $booleanPlaceholder,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = "Sigmoid justeringsfaktor"
                                }
                            ),
                            units: state.units,
                            type: .decimal("adjustmentFactorSigmoid"),
                            label: "Sigmoid justeringsfaktor",
                            miniHint: "Justera aggressiviteten för Sigmoid dynamisk ISF.",
                            verboseHint:
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Standard: 50%").bold()
                                Text(
                                    "Sigmoid-justeringsfaktorn (AF) låter dig styra hur snabbt Sigmoid Dynamic ISF reagerar på förändringar i glukosnivån och vid vilket glukosvärde Autosens Max- och Autosens Min-gränserna uppnås."
                                )

                                Text(
                                    "Sigmoid-justeringsfaktorn påverkar både hur snabbt dina ISF-värden förändras och hur snabbt Autosens Max- och Autosens Min-gränserna nås. Om du ökar Sigmoid-justeringsfaktorn förändras ISF snabbare samtidigt som intervallet av glukosvärden mellan Autosens Max och Autosens Min blir mindre."
                                )

                                Text(
                                    "Denna inställning gör systemet mer responsivt, men effekten begränsas av inställningarna Autosens Min och Autosens Max."
                                )

                                Text(
                                    "På grund av hur kurvan beräknas när Sigmoid-formeln används påverkar en ökning av denna inställning kurvans branthet på ett annat sätt än vid den vanliga logaritmiska beräkningen i Dynamisk ISF. Var försiktig när du justerar denna inställning."
                                )
                            }
                        )
                    }

                    SettingInputSection(
                        decimalValue: $state.weightPercentage,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Viktad total daglig dos (TDD)"
                            }
                        ),
                        units: state.units,
                        type: .decimal("weightPercentage"),
                        label: "Viktad total daglig dos (TDD)",
                        miniHint: "Viktning mellan 24h TDD vs 10 dagars TDD.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: 35%").bold()
                            Text(
                                "Denna inställning justerar hur stor vikt som ges åt din senaste totala dygnsdos insulin (TDD) vid beräkningen av Dynamisk ISF och Dynamisk CR."
                            )

                            Text(
                                "Med standardinställningen baseras 35 % av beräkningen på de senaste 24 timmarnas insulinanvändning, medan de återstående 65 % baseras på data från de senaste 10 dagarna."
                            )

                            Text(
                                "Om värdet sätts till 100 % används endast de senaste 24 timmarnas data."
                            )

                            Text(
                                "Ett lägre värde jämnar ut dessa variationer och ger ett stabilare resultat."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.tddAdjBasal,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Justera basal"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Justera basal",
                        miniHint: "Använd dynamisk ratio för att justera basal.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "Aktivera denna inställning för att göra basaljusteringarna mer responsiva. Låt den vara avstängd om ditt basalbehov normalt inte varierar särskilt mycket."
                            )

                            Text(
                                "När Justera basal är aktiverad ersätts den vanliga beräkningen av Autosens-förhållandet med följande beräkning:"
                            )

                            Text("Autosens-förhållande =\n(Viktat genomsnitt av TDD) ÷ (10-dagars genomsnitt av TDD)")

                            Text("Ny basalprofil =\n(Aktuell basalprofil) × (Autosens-förhållande)")
                        }
                    )

                    SettingInputSection(
                        decimalValue: $state.threshold_setting,
                        booleanValue: $booleanPlaceholder,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Minsta glukos säkerhetströskel"
                            }
                        ),
                        units: state.units,
                        type: .decimal("threshold_setting"),
                        label: "Minsta säkerhetströskel",
                        miniHint: "Justera säkerhetströskeln som används för att pausa insulintillförsel.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: Sätts av algoritmen").bold()
                            Text(
                                "Den lägsta säkerhetströskeln bestäms som standard av ditt inställda glukosmål. Om ditt glukos förväntas sjunka under denna nivå kommer insulintillförseln automatiskt att pausas. Funktionen är utformad för att skydda mot hypoglykemi, särskilt under sömn eller andra känsliga situationer."
                            )

                            Text(
                                "Trio använder det högsta av det standardberäknade värdet nedan och det värde som du själv anger här."
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Standardvärdet beräknas enligt följande:").bold()
                                    Text("Målglukos - 0,5 × (Målglukos - 40)")
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(
                                        "Om ditt glukosmål är \(state.units == .mgdL ? "110" : 110.formattedAsMmolL) \(state.units.rawValue) kommer Trio att använda en säkerhetströskel på \(state.units == .mgdL ? "75" : 75.formattedAsMmolL) \(state.units.rawValue), om du inte anger ett högre värde än \(state.units == .mgdL ? "75" : 75.formattedAsMmolL) \(state.units.rawValue) för Lägsta säkerhetströskel."
                                    )

                                    Text(
                                        "\(state.units == .mgdL ? "110" : 110.formattedAsMmolL) - 0,5 × (\(state.units == .mgdL ? "110" : 110.formattedAsMmolL) - \(state.units == .mgdL ? "40" : 40.formattedAsMmolL)) = \(state.units == .mgdL ? "75" : 75.formattedAsMmolL)"
                                    )
                                }

                                Text(
                                    "Denna inställning kan sättas till ett värde mellan \(state.units == .mgdL ? "60" : 60.formattedAsMmolL) och \(state.units == .mgdL ? "120" : 120.formattedAsMmolL) \(state.units.rawValue)."
                                )

                                Text(
                                    "Obs: Basalinsulinet kan återupptas om IOB är negativt och glukoset stiger snabbare än prognosen förutser."
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
            .navigationBarTitle("Dynamisk dosering")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
