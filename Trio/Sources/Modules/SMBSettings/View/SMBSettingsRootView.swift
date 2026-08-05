import SwiftUI
import Swinject

extension SMBSettings {
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
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBAlways,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always"),
                    miniHint: "Använd alltid SMB, förutom när ett högt tillfälligt mål är aktivt.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text(
                            "När detta är aktiverat kommer super mikrobolus (SMB) alltid att tillåtas om doseringsberäkningarna visar att insulin behöver ges via SMB, förutom när ett högt tillfälligt mål är inställt. När 'ANvänd alltid SMB' är aktiverat döljs de överflödiga alternativen för att aktivera SMB."
                        )

                        Text(
                            "Obs: Om du vill tillåta SMB även när ett högt tillfälligt mål är inställt aktiverar du inställningen 'Tillåt SMB vid högt tillfälligt mål'."
                        )
                    },
                    headerText: "Super mikrobolus"
                )

                if !state.enableSMBAlways {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithCOB,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB"),
                        miniHint: "Använd SMB vid aktiva kolhydrater.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "När prognoslinjen för aktiva kolhydrater (COB) visas kan Trio, om denna inställning är aktiverad, använda Super mikrobolus (SMB) för att leverera den insulinmängd som behövs."
                            )

                            Text(
                                "Obs: Om denna inställning är aktiverad och villkoren är uppfyllda kan SMB användas oavsett om övriga SMB-inställningar är aktiverade eller inte."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithTemptarget,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With Temptarget", comment: "Enable SMB With Temptarget"),
                        miniHint: "Använd SMB när ett tillfälligt mål är inställt under \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue).",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "När denna inställning är aktiverad kan Trio använda Super mikrobolus (SMB) för att leverera den insulinmängd som behövs när ett manuellt tillfälligt mål under \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) är inställt."
                            )

                            Text(
                                "Obs: Om denna inställning är aktiverad och villkoren är uppfyllda kan SMB användas oavsett om övriga SMB-inställningar är aktiverade eller inte."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBAfterCarbs,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB After Carbs", comment: "Enable SMB After Carbs"),
                        miniHint: "Använd SMB i 6h efter en måltid.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "När denna inställning är aktiverad kan Trio använda Super mikrobolus (SMB) för att leverera den insulinmängd som behövs under 6 timmar efter att en måltid med kolhydrater har registrerats, oavsett om det finns aktiva kolhydrater ombord (COB) eller inte."
                            )

                            Text(
                                "Obs: Om denna inställning är aktiverad och villkoren är uppfyllda kan SMB användas oavsett om övriga SMB-inställningar är aktiverade eller inte."
                            )
                        }
                    )

                    SettingInputSection(
                        decimalValue: $state.enableSMB_high_bg_target,
                        booleanValue: $state.enableSMB_high_bg,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = NSLocalizedString("Enable SMB With High BG", comment: "Enable SMB With High BG")
                            }
                        ),
                        units: state.units,
                        type: .conditionalDecimal("enableSMB_high_bg_target"),
                        label: NSLocalizedString("Använd SMB vid högt glukosvärde", comment: "Enable SMB With High BG"),
                        conditionalLabel: "Högt glukosvärde",
                        miniHint: "Använd SMB när glukos överstiger 'Högt glukosvärde'.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()
                            Text(
                                "När denna inställning är aktiverad kan Trio använda Super mikrobolus (SMB) för att leverera den insulinmängd som behövs när blodsockret ligger över det värde som har angetts som 'Högt glukosvärde'."
                            )

                            Text(
                                "Obs: Om denna inställning är aktiverad och villkoren är uppfyllda kan SMB användas oavsett om övriga SMB-inställningar är aktiverade eller inte."
                            )
                        }
                    )
                }

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowSMBWithHighTemptarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Allow SMB With High Temptarget",
                                comment: "Allow SMB With High Temptarget"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "Allow SMB With High Temptarget",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    miniHint: "Tillåt även SMB när ett tillfälligt mål är satt högre än \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue).",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text(
                            "När denna inställning är aktiverad kan Trio använda Super mikrobolus (SMB) för att leverera den insulinmängd som behövs när ett manuellt tillfälligt mål över \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) är inställt."
                        )

                        Text(
                            "Obs: Om denna inställning är aktiverad och villkoren är uppfyllda kan SMB användas oavsett om övriga SMB-inställningar är aktiverade eller inte."
                        )

                        Text(
                            "Varning: Höga tillfälliga mål används ofta vid återhämtning efter ett lågt blodsocker. Om du använder höga tillfälliga mål för detta ändamål bör denna inställning förbli avstängd."
                        ).bold()
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableUAM,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Enable UAM", comment: "Enable UAM")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Enable UAM", comment: "Enable UAM"),
                    miniHint: "Aktivera UAM (oannonserade måltider) SMB.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text(
                            "När UAM (Unannounced Meals) är aktiverat kan Trio upptäcka och reagera på oväntade ökningar i blodsockret som orsakas av oregistrerade eller felberäknade kolhydrater, måltider med högt innehåll av fett eller protein eller andra faktorer, såsom adrenalin."
                        )

                        Text(
                            "Funktionen använder SMB-algoritmen (Super mikrobolus) för att ge insulin i små doser och korrigera stigande blodsocker. UAM fungerar även åt andra hållet genom att minska eller stoppa SMB om blodsockret sjunker oväntat."
                        )

                        Text(
                            "Detta ger mer träffsäkra insulinjusteringar när kolhydrater inte har registrerats eller har registrerats felaktigt."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxSMBBasalMinutes,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxSMBBasalMinutes"),
                    label: NSLocalizedString("Max SMB Basalminuter", comment: "Max SMB Basal Minutes"),
                    miniHint: "Begränsar storleken på en enskild SMB-dos.",
                    verboseHint: VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Standard: 30 minuter").bold()
                                Text("(50% nuvarande basal)").bold()
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Detta är en begränsning för storleken på en enskild SMB-dos. En SMB kan maximalt vara lika stor som angivet antal minuter av din nuvarande basal."
                                )
                                Text(
                                    "För att beräkna maximal tillåten SMB utifrån denna inställning, anvämnd följande formel:"
                                )
                            }
                        }
                        VStack(alignment: .center, spacing: 5) {
                            Text(
                                "𝒳 = Max SMB Basalminuter"
                            )
                            Text("(𝒳 ÷ 60) × nuvarande basal")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Varning: Om värdet sätts högre än 90 minuter påverkas Trios möjlighet att använda nollbasaler för att förebygga lågt blodsocker om trenden plötsligt vänder ner."
                            ).bold()
                            Text("Notera: SMB måste vara aktivt för att denna gräns ska aktiveras.")
                        }
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxUAMSMBBasalMinutes,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max UAM Basal Minutes", comment: "Max UAM Basal Minutes")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxUAMSMBBasalMinutes"),
                    label: NSLocalizedString("Max UAM Basalminuter", comment: "Max UAM Basal Minutes"),
                    miniHint: "Begränsar storleken på en enskild UAM-SMB-dos.",
                    verboseHint: VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Standard: 30 minutes").bold()
                                Text("(50% nuvarande basal)").bold()
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Detta är en begränsning för storleken på en enskild UAM SMB-dos. En SMB kan maximalt vara lika stor som angivet antal minuter av din nuvarande basal."
                                )
                                Text(
                                    "För att beräkna maximal tillåten UAM SMB utifrån denna inställning, anvämnd följande formel:"
                                )
                            }
                        }
                        VStack(alignment: .center, spacing: 5) {
                            Text(
                                "𝒳 = Max UAM SMB Basalminuter"
                            )
                            Text("(𝒳 ÷ 60) × nuvarande basal")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Varning: Om värdet sätts högre än 60 minuter påverkas Trios möjlighet att använda nollbasaler för att förebygga lågt blodsocker om trenden plötsligt vänder ner."
                            ).bold()
                            Text("Notera: UAM SMB måste vara aktivt för att denna gräns ska aktiveras.")
                        }
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxDeltaBGthreshold,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDeltaBGthreshold"),
                    label: NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold"),
                    miniHint: "Inaktiverar SMB om de två senaste glukosvärdena skiljer sig mer än angiven procent.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 20% ökning").bold()
                        Text(
                            "Maximal tillåten procentuell ökning av glukosvärdet för att SMB ska tillåtas. Om skillnaden är större än angivet värde kommer Trio tillfälligt att inaktivera SMB."
                        )
                        Text("Notera: Denna inställning har ett hårdkodat tak på 40%")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.smbDeliveryRatio,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("SMB Delivery Ratio", comment: "SMB Delivery Ratio")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbDeliveryRatio"),
                    label: NSLocalizedString("SMB ratio", comment: "SMB Delivery Ratio"),
                    miniHint: "Procent av det beräknade insulonbehovet som kan ges som en enskild SMB.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 50%").bold()
                        Text(
                            "När det totala insulnbehovet har beräknats, så används denna säkerhetsgräns för att avgöra hur stor del av det totala beräknade insulinbehovet som maximalt kan levereras med en enskild SMB."
                        )
                        Text(
                            "Eftersom SMB kan ges vid varje loop-cykel, så är det viktigt att sätta detta värde till en rimlig nivå som ger Trio möjlighet att använda nollbasaler för att förebygga låga värden om blodsockret plötsligt faller. Öka detta värde med försiktighet."
                        )
                        Text("Notera: Tillåtet spann är 30 - 70%")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.smbInterval,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("SMB Interval", comment: "SMB Interval")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbInterval"),
                    label: NSLocalizedString("SMB Interval", comment: "SMB Interval"),
                    miniHint: "Minsta antalet minuter sedan föregående SMB/Bolus innan en ny SMB tillåts.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: 3 min").bold()
                        Text(
                            "Detta är det minsta antalet minuter som måste passera sedan föregående manuella eller automatiska bolus (SMB) innan Trio tillåter att en ny SMB ges."
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
            .navigationTitle("SMB Inställningar")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
