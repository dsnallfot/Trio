import SwiftUI
import Swinject

extension TargetBehavoir {
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
                    booleanValue: $state.highTemptargetRaisesSensitivity,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Högt tillfälligt mål ökar känsligheten",
                                comment: "High Temp Target Raises Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "Högt tillfälligt mål ökar känsligheten",
                        comment: "High Temp Target Raises Sensitivity"
                    ),

                    miniHint: "Ökar insulinkänsligheten vid höga tillfälliga mål.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "När denna funktion är aktiverad kommer ett manuellt tillfälligt mål över \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) att minska Autosens-förhållandet som används för justering av ISF och basalinsulin. Resultatet blir att mindre insulin ges totalt. Effekten anpassas efter det valda tillfälliga målet – ju högre målvärde, desto lägre Autosens-förhållande används."
                        )

                        Text(
                            "Om halv basal träningsmål är satt till \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue) används ett Autosens-förhållande på 0,75 vid ett tillfälligt mål på \(state.units == .mgdL ? "120" : 120.formattedAsMmolL) \(state.units.rawValue). Ett tillfälligt mål på \(state.units == .mgdL ? "140" : 140.formattedAsMmolL) \(state.units.rawValue) använder ett Autosens-förhållande på 0,6."
                        )

                        Text(
                            "Obs: Hur stor denna effekt blir kan justeras med inställningen 'Halv basal träningsmål'."
                        )
                    },
                    headerText: "Algoritmiska målinställningar"
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.lowTemptargetLowersSensitivity,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Lågt tillfälligt mål minskar känsligheten",
                                comment: "Low Temp Target Lowers Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "Lågt tillfälligt mål minskar känsligheten",
                        comment: "Low Temp Target Lowers Sensitivity"
                    ),

                    miniHint: "Minskar insulinkänsligheten vid låga tillfälliga mål.",

                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "När denna funktion är aktiverad kommer ett tillfälligt mål under \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) att öka Autosens-förhållandet som används för justering av ISF och basalinsulin. Resultatet blir att mer insulin ges totalt. Effekten anpassas efter det valda tillfälliga målet – ju lägre målvärde, desto högre Autosens-förhållande används."
                        )

                        Text(
                            "Om Målet för halv basal vid aktivitet är satt till \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue) används ett Autosens-förhållande på 1,09 vid ett tillfälligt mål på \(state.units == .mgdL ? "95" : 95.formattedAsMmolL) \(state.units.rawValue). Ett tillfälligt mål på \(state.units == .mgdL ? "85" : 85.formattedAsMmolL) \(state.units.rawValue) använder ett Autosens-förhållande på 1,33."
                        )

                        Text(
                            "Obs: Hur stor denna effekt blir kan justeras med inställningen Målet för halv basal vid aktivitet."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.sensitivityRaisesTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Känslighet höjer mål", comment: "Sensitivity Raises Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Känslighet höjer mål", comment: "Sensitivity Raises Target"),
                    miniHint: "Höjer glukosmålnivån vid känslighet",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text(
                            "Om denna funktion aktiveras höjs ditt glukosmål om Trio upptäcker en ökad insulinkänslighet jämfört med din normala insulinkänslighet."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.resistanceLowersTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Resistens sänker mål", comment: "Resistance Lowers Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Resistens sänker mål", comment: "Resistance Lowers Target"),
                    miniHint: "Sänker glukosmålnivån vid resistens",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()
                        Text(
                            "Om denna funktion aktiveras sänks ditt glukosmål om Trio upptäcker en minskad insulinkänslighet jämfört med din normala insulinkänslighet."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.halfBasalExerciseTarget,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Halv basal träningsmål", comment: "Half Basal Exercise Target")
                        }
                    ),
                    units: state.units,
                    type: .decimal("halfBasalExerciseTarget"),
                    label: NSLocalizedString("Halv basal träningsmål", comment: "Half Basal Exercise Target"),
                    miniHint: "Skalar ner din basal till 50% vid detta värde.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Standard: \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue)"
                        )
                        .bold()
                        Text(
                            "Halv basal träningsmål gör det möjligt att minska basalinsulinet vid träning eller öka basalinsulinet inför en måltid när ett tillfälligt glukosmål är inställt."
                        )

                        Text(
                            "Om ett tillfälligt glukosmål på \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue) används minskas exempelvis basalinsulinet till 50 %. Minskningen anpassas dock efter det valda målet, till exempel 75 % vid \(state.units == .mgdL ? "120" : 120.formattedAsMmolL) \(state.units.rawValue) och 60 % vid \(state.units == .mgdL ? "140" : 140.formattedAsMmolL) \(state.units.rawValue)."
                        )

                        Text(
                            "Obs: Den här inställningen används endast om inställningen \"Lågt tillfälligt mål minskar känsligheten\" eller \"Högt tillfälligt mål ökar känsligheten\" är aktiverad."
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
            .navigationTitle("Målbeteende")
            .navigationBarTitleDisplayMode(.automatic)
//            .onDisappear {
//                state.saveIfChanged()
//            }
        }
    }
}
