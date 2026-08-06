import SwiftUI
import Swinject

extension AlgorithmAdvancedSettings {
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
                    header: Text("ANSVARSFRISKRIVNING"),
                    content: {
                        VStack(alignment: .leading) {
                            Text(
                                "Inställningarna i detta avsnitt behöver normalt inte ändras. Ändra dem inte om du inte har en god förståelse för vad de gör och vilken påverkan de har på algoritmen."
                            ).bold()
                        }
                    }
                ).listRowBackground(Color.tabBar)

                SettingInputSection(
                    decimalValue: $state.maxDailySafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Max daglig säkerhetsmultiplikator",
                                comment: "Max Daily Safety Multiplier"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDailySafetyMultiplier"),
                    label: NSLocalizedString(
                        "Max daglig säkerhetsmultiplikator",
                        comment: "Max Daily Safety Multiplier"
                    ),

                    miniHint: "Begränsar temporära basalhastigheter till denna procentandel av din högsta basalhastighet.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 300 %").bold()

                        Text(
                            "Den här inställningen begränsar den högsta temporära basalhastighet som Trio får sätta. Med standardvärdet 300 % begränsas den till tre gånger din högsta programmerade basalhastighet."
                        )

                        Text(
                            "Det fungerar som en säkerhetsgräns och ser till att temporära basalhastigheter aldrig överstiger säkra nivåer."
                        )

                        Text("Varning: Det rekommenderas inte att öka detta värde.").bold()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.currentBasalSafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Aktuell basal säkerhetsmultiplikator",
                                comment: "Current Basal Safety Multiplier"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("currentBasalSafetyMultiplier"),
                    label: NSLocalizedString(
                        "Aktuell basal säkerhetsmultiplikator",
                        comment: "Current Basal Safety Multiplier"
                    ),

                    miniHint: "Begränsar temporära basalhastigheter till denna procentandel av den aktuella basalhastigheten.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 400 %").bold()

                        Text(
                            "Den här inställningen begränsar den automatiska justeringen av den temporära basalhastigheten till denna procentandel av den aktuella basalhastigheten i profilen vid den aktuella loopcykeln."
                        )

                        Text(
                            "Detta förhindrar alltför höga insulindoser, särskilt under perioder med varierande insulinkänslighet, och ökar säkerheten."
                        )

                        Text("Varning: Det rekommenderas inte att öka detta värde.").bold()
                    }
                )

                SettingInputSection(
                    decimalValue: $state.insulinActionCurve,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Insulinets verkningstid"
                        }
                    ),
                    units: state.units,
                    type: .decimal("dia"),
                    label: "Insulinets verkningstid",

                    miniHint: "Hur många timmar insulinet är aktivt i kroppen.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 10 timmar").bold()

                        Text(
                            "Insulinets verkningstid (DIA) anger hur länge insulinet fortsätter att sänka glukosnivån efter att en dos har givits."
                        )

                        Text(
                            "Detta hjälper systemet att beräkna aktivt insulin (IOB) på ett korrekt sätt och minskar risken för över- eller underkorrigering genom att ta hänsyn till den sista delen av insulinets effekt."
                        )

                        Text(
                            "Tips: Det är oftast bättre att använda Anpassad topptid än att ändra insulinets verkningstid (DIA)."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.insulinPeakTime,
                    booleanValue: $state.useCustomPeakTime,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Använd anpassad topptid", comment: "Use Custom Peak Time")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("insulinPeakTime"),
                    label: NSLocalizedString(
                        "Använd anpassad topptid",
                        comment: "Use Custom Peak Time"
                    ),

                    conditionalLabel: NSLocalizedString(
                        "Insulinets topptid",
                        comment: "Insulin Peak Time"
                    ),

                    miniHint: "Ange en anpassad tidpunkt för insulinets maximala effekt.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: Bestäms av insulintyp").bold()

                        Text(
                            "Insulinets topptid anger när insulinet har sin starkaste glukossänkande effekt och anges i minuter efter att dosen har givits."
                        )

                        Text(
                            "Denna topptid hjälper systemet att förutsäga när insulinets effekt är som störst, vilket ger mer träffsäkra prognoser för glukosutvecklingen."
                        )

                        Text("Systemets standardvärden:").bold()

                        Text("Ultrasnabbverkande: 55 minuter (tillåtet intervall 35–100 minuter)")

                        Text("Snabbverkande: 75 minuter (tillåtet intervall 50–120 minuter)")
                    }
                )
                /*
                 SettingInputSection(
                     decimalValue: $decimalPlaceholder,
                     booleanValue: $state.skipNeutralTemps,
                     shouldDisplayHint: $shouldDisplayHint,
                     selectedVerboseHint: Binding(
                         get: { selectedVerboseHint },
                         set: {
                             selectedVerboseHint = $0.map { AnyView($0) }
                             hintLabel = NSLocalizedString("Hoppa över neutral temp basal", comment: "Skip Neutral Temps")
                         }
                     ),
                     units: state.units,
                     type: .boolean,
                     label: NSLocalizedString(
                         "Hoppa över neutral temp basal",
                         comment: "Skip Neutral Temps"
                     ),

                     miniHint: "Hoppar över neutrala temporära basaler för att minska larm från MDT-pumpar.",

                     verboseHint:
                     VStack(alignment: .leading, spacing: 10) {
                         Text("Standard: AV").bold()

                         Text(
                             "När Hoppa över neutrala temporära basalhastigheter är aktiverat kommer Trio inte att sätta neutrala temporära basalhastigheter strax före varje hel timme. Detta minskar de återkommande larmen från MDT-pumpar. Funktionen kan hjälpa lättväckta personer att undvika larm, men innebär också att basaljusteringar fördröjs. Den används dessutom endast när SMB av någon anledning är inaktiverat."
                         )

                         Text(
                             "För de flesta användare rekommenderas att lämna denna inställning avstängd för att säkerställa en jämn basalinsulintillförsel och korrekta loopberäkningar. Om funktionen används hoppas loopkörningar över under de sista fem minuterna av varje timme."
                         )
                     }
                 )
                 */
                /*
                                SettingInputSection(
                                    decimalValue: $decimalPlaceholder,
                                    booleanValue: $state.unsuspendIfNoTemp,
                                    shouldDisplayHint: $shouldDisplayHint,
                                    selectedVerboseHint: Binding(
                                        get: { selectedVerboseHint },
                                        set: {
                                            selectedVerboseHint = $0.map { AnyView($0) }
                                            hintLabel = NSLocalizedString("Återuppta pump om ingen temp basal är aktiv", comment: "Unsuspend If No Temp")
                                        }
                                    ),
                                    units: state.units,
                                    type: .boolean,
                                    label: NSLocalizedString(
                                        "Återuppta om ingen temp",
                                        comment: "Unsuspend If No Temp"
                                    ),

                                    miniHint: "Återupptar pumpen automatiskt efter en paus.",

                                    verboseHint:
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Standard: Av").bold()

                                        Text(
                                            "När denna funktion är aktiverad kan Trio automatiskt återuppta pumpen om du glömmer att göra det själv, förutsatt att en temporär basal på 0 E/tim först har satts. Funktionen fungerar som en extra säkerhet genom att återstarta insulintillförseln om du glömmer att återuppta pumpen manuellt."
                                        )

                                        Text(
                                            "Obs: Gäller endast pumpar med stöd för paus direkt på pumpen."
                                        )
                                    }
                                )
                 */
                /*
                 SettingInputSection(
                     decimalValue: $decimalPlaceholder,
                     booleanValue: $state.suspendZerosIOB,
                     shouldDisplayHint: $shouldDisplayHint,
                     selectedVerboseHint: Binding(
                         get: { selectedVerboseHint },
                         set: {
                             selectedVerboseHint = $0.map { AnyView($0) }
                             hintLabel = NSLocalizedString("Nollställ IOB vid paus", comment: "Suspend Zeros IOB")
                         }
                     ),
                     units: state.units,
                     type: .boolean,
                     label: NSLocalizedString(
                         "Nollställ IOB vid paus",
                         comment: "Suspend Zeros IOB"
                     ),

                     miniHint: "Rensar temporära basalhastigheter och återställer IOB när pumpen pausas.",

                     verboseHint:
                     VStack(alignment: .leading, spacing: 10) {
                         Text("Standard: AV").bold()

                         Text(
                             "När Nollställ IOB vid paus är aktiverat återställs alla aktiva temporära basalhastigheter när pumpen pausas. Nya temporära basalhastigheter på 0 E/tim läggs därefter till för att kompensera för de temporära basalhastigheter som annars skulle ha varit aktiva under pausen."
                         )

                         Text(
                             "Detta förhindrar att kvarvarande insulineffekt från temporära basalhastigheter påverkar beräkningarna när pumpen är pausad och ger en säkrare hantering av aktivt insulin (IOB)."
                         )

                         Text(
                             "Obs: Gäller endast pumpar med stöd för paus direkt på pumpen."
                         )
                     }
                 )
                 */

                SettingInputSection(
                    decimalValue: $state.min5mCarbimpact,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Minsta kolhydratpåverkan per 5 min", comment: "Min 5m Carb Impact")
                        }
                    ),
                    units: state.units,
                    type: .decimal("min5mCarbimpact"),
                    label: NSLocalizedString(
                        "Minsta kh-påverkan per 5 min",
                        comment: "Min 5m Carb Impact"
                    ),

                    miniHint: "Standardvärde för kolhydratabsorption under ett intervall på fem minuter.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Minsta kolhydratpåverkan per 5 minuter anger den förväntade glukosökningen från kolhydrater under fem minuter när absorptionen inte tydligt kan utläsas från glukosdata."
                        )

                        Text(
                            "Standardvärdet är en förväntad ökning på \(state.units == .mgdL ? "8" : 8.formattedAsMmolL) \(state.units.rawValue) per 5 minuter. Detta påverkar hur snabbt COB minskar i situationer där kolhydratabsorption inte syns i glukosavvikelserna. Standardvärdet motsvarar en lägsta absorptionshastighet på 24 g/timme vid ett CSF på \(state.units == .mgdL ? "4" : 4.formattedAsMmolL) \(state.units.rawValue)/g."
                        )

                        Text(
                            "Denna inställning hjälper systemet att uppskatta hur mycket glukos kroppen absorberar även när detta inte omedelbart syns i glukosdata, vilket ger mer träffsäkra insulindoser under kolhydratabsorptionen."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsFraction,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Återstående kolhydrater (%)", comment: "Remaining Carbs Percentage")
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsFraction"),
                    label: NSLocalizedString(
                        "Återstående kolhydrater (%)",
                        comment: "Remaining Carbs Percentage"
                    ),

                    miniHint: "Andel kolhydrater som fortfarande antas absorberas om ingen absorption upptäcks.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 100 %").bold()

                        Text(
                            "Återstående kolhydrater (%) uppskattar hur stor del av de registrerade kolhydraterna som fortfarande absorberas under en period på fyra timmar när glukosdata inte visar någon tydlig absorption."
                        )

                        Text(
                            "Denna reservberäkning minskar risken för för låg insulindosering genom att fördela en del av de registrerade kolhydraterna över tid och balansera insulinbehovet när kolhydratabsorptionen inte kan upptäckas."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsCap,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max återstående kolhydrater", comment: "Remaining Carbs Cap")
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsCap"),
                    label: NSLocalizedString(
                        "Max återstående kolhydrater",
                        comment: "Remaining Carbs Cap"
                    ),

                    miniHint: "Högsta mängd kolhydrater som fortfarande antas absorberas om ingen absorption upptäcks.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 90 g").bold()

                        Text(
                            "Max återstående kolhydrater anger den högsta mängd kolhydrater som systemet antar fortfarande absorberas under en period på fyra timmar, även när glukosvärdena inte visar några tydliga tecken på absorption."
                        )

                        Text(
                            "Denna gräns förhindrar att systemet överskattar insulinbehovet när kolhydratabsorptionen inte syns i glukosdata och fungerar som en extra säkerhetsfunktion för mer träffsäker dosering."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.noisyCGMTargetMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Ökning av glukosmål vid brusig CGM",
                                comment: "Noisy CGM Target Multiplier"
                            )
                        }
                    ),
                    units: state.units,
                    type: .decimal("noisyCGMTargetMultiplier"),
                    label: NSLocalizedString(
                        "Ökning glukosmål brusig CGM",
                        comment: "Noisy CGM Target Multiplier"
                    ),

                    miniHint: "Procentuell ökning av glukosmålet när CGM-data är opålitliga.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 130 %").bold()

                        Text(
                            "Ökning av glukosmål vid brusig CGM höjer ditt glukosmål när systemet upptäcker brusiga eller opålitliga CGM-data. Som standard höjs glukosmålet till 130 % av ditt inställda glukosmål för att kompensera för den lägre tillförlitligheten i glukosvärdena."
                        )

                        Text(
                            "Detta minskar risken för felaktig insulindosering baserad på osäkra sensordata och ger säkrare insulinjusteringar under perioder med låg CGM-noggrannhet."
                        )

                        Text(
                            "Obs: En CGM betraktas som brusig när den levererar inkonsekventa glukosvärden."
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
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Extra inställningar")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
