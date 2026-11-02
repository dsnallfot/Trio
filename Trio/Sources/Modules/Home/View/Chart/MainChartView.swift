import Charts
import CoreData
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

struct MainChartView: View {
    var geo: GeometryProxy
    var safeAreaSize: CGFloat
    var units: GlucoseUnits
    var hours: Int
    var highGlucose: Decimal
    var lowGlucose: Decimal
    var currentGlucoseTarget: Decimal
    var glucoseColorScheme: GlucoseColorScheme
    var screenHours: Int16
    var displayXgridLines: Bool
    var displayYgridLines: Bool
    var thresholdLines: Bool
    var state: Home.StateModel

    @State var basalProfiles: [BasalProfile] = []
    @State var preparedTempBasals: [(start: Date, end: Date, rate: Double, scheduled: Bool)] = []
    @State var selection: Date? = nil

    @State var mainChartHasInitialized = false

    var now: Date = .now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    private var selectionWindow: ClosedRange<Date>? {
        guard let selection else { return nil }
        return selection.addingTimeInterval(-6 * 60) ... selection
    }

    private var selectedGlucose: GlucoseStored? {
        guard let window = selectionWindow else { return nil }
        // Glucose readings are ordered oldest first.
        return state.glucoseFromPersistence.last { $0.date.map(window.contains) ?? false }
    }

    // Determinations are ordered newest first.
    private func previousDetermination(requiringIOB: Bool) -> OrefDetermination? {
        guard let window = selectionWindow else { return nil }
        return state.enactedAndNonEnactedDeterminations.first { entry in
            guard let date = entry.deliverAt, window.contains(date) else { return false }
            return !requiringIOB || entry.iob != nil
        }
    }

    var selectedCOBValue: OrefDetermination? {
        previousDetermination(requiringIOB: false)
    }

    var selectedIOBValue: OrefDetermination? {
        previousDetermination(requiringIOB: true)
    }

    private var selectionContent: SelectionPopoverView? {
        guard let selection else { return nil }
        return SelectionPopoverView(
            selection: selection,
            selectedGlucose: selectedGlucose,
            selectedIOBValue: selectedIOBValue,
            selectedCOBValue: selectedCOBValue,
            units: units,
            highGlucose: highGlucose,
            lowGlucose: lowGlucose,
            currentGlucoseTarget: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var selectionRowHeight: CGFloat = 30
    private let selectionRowGap: CGFloat = 8

    var mainPlotMinimumHeight: CGFloat {
        let reserved = selection == nil ? 0 : selectionRowHeight + selectionRowGap
        return max(0, geo.size.height * (0.28 - safeAreaSize) - reserved)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selectionContent {
                selectionContent.selectionPopover
                    .frame(height: selectionRowHeight)
                    .padding(.horizontal, 10)
                    .padding(.bottom, selectionRowGap)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            ZStack {
                VStack(spacing: 5) {
                    dummyBasalChart
                    staticYAxisChart
                    Spacer()
                    dummyCobChart
                }

                ScrollViewReader { scroller in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 5) {
                            basalChart
                            mainChart
                            Spacer()
                            cobIobChart
                        }
                        .onChange(of: screenHours) {
                            if screenHours == 3 {
                                scroller.scrollTo("MainChart", anchor: UnitPoint(x: 0.9444, y: 0.5))
                            } else {
                                scroller.scrollTo("MainChart", anchor: .trailing)
                            }
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) {
                            if screenHours == 3 {
                                scroller.scrollTo(
                                    "MainChart",
                                    anchor: UnitPoint(x: 0.9444, y: 0.5)
                                )
                            } else {
                                scroller.scrollTo("MainChart", anchor: .trailing)
                            }

                            state.updateStartEndMarkers()
                        }
                        .onChange(of: state.enactedAndNonEnactedDeterminations.first?.deliverAt) {
                            if screenHours == 3 {
                                scroller.scrollTo(
                                    "MainChart",
                                    anchor: UnitPoint(x: 0.9444, y: 0.5)
                                )
                            } else {
                                scroller.scrollTo("MainChart", anchor: .trailing)
                            }
                        }
                        .onChange(of: units) {
                            // TODO: - Refactor this to only update the Y Axis Scale
                            state.setupGlucoseArray()
                        }
                        .onAppear {
                            if !mainChartHasInitialized {
                                if screenHours == 3 {
                                    // 24 h historik + 3 h prognos = 27 h total chart-bredd.
                                    // Vid 3 h screentime vill vi initialt visa:
                                    // 1,5 h historik + NOW + 1,5 h prognos.
                                    scroller.scrollTo(
                                        "MainChart",
                                        anchor: UnitPoint(x: 0.9444, y: 0.5)
                                    )
                                } else {
                                    scroller.scrollTo("MainChart", anchor: .trailing)
                                }

                                state.updateStartEndMarkers()
                                // The chart is recreated after backgrounding/tab changes;
                                // rebuild both locally cached basal series on every mount.
                                calculateBasals()
                                calculateTempBasalsInBackground()
                                mainChartHasInitialized = true
                            }
                        }
                    }
                }
            }
            .overlayPreferenceValue(SelectionLineTop.self) { anchor in
                GeometryReader { geometry in
                    if let anchor {
                        let end = geometry[anchor]
                        Path { path in
                            path.move(to: CGPoint(x: end.x, y: -selectionRowGap))
                            path.addLine(to: end)
                        }
                        .stroke(Color.tabBar, lineWidth: 2)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selection != nil)
    }
}

private struct SelectionLineTop: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Main Chart with selection Popover

extension MainChartView {
    private var mainChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()

                GlucoseTargetsView(
                    targetProfiles: state.targetProfiles
                )

                OverrideView(
                    state: state,
                    overrides: state.overrides,
                    overrideRunStored: state.overrideRunStored,
                    units: state.units,
                    viewContext: context
                )

                TempTargetView(
                    tempTargetStored: state.tempTargetStored,
                    tempTargetRunStored: state.tempTargetRunStored,
                    units: state.units,
                    viewContext: context
                )

                GlucoseChartView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    isSmoothingEnabled: state.isSmoothingEnabled,
                    glucoseColorScheme: state.glucoseColorScheme
                )

                InsulinView(
                    glucoseData: state.glucoseFromPersistence,
                    insulinData: state.insulinFromPersistence,
                    units: state.units
                )

                CarbView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    carbData: state.carbsFromPersistence,
                    fpuData: state.fpusFromPersistence,
                    minValue: units == .mgdL ? state.minYAxisValue : state.minYAxisValue
                        .asMmolL
                )

                ForecastView(
                    preprocessedData: state.preprocessedData,
                    minForecast: state.minForecast,
                    maxForecast: state.maxForecast,
                    units: state.units,
                    maxValue: state.maxYAxisValue,
                    forecastDisplayType: state.forecastDisplayType,
                    lastDeterminationDate: state.determinationsFromPersistence.first?.deliverAt ?? .distantPast
                )

                if let selectionContent {
                    selectionContent
                }
            }
            .id("MainChart")
            .onChange(of: state.insulinFromPersistence) {
                state.roundedTotalBolus = state.calculateTINS()
            }
            .frame(
                minHeight: mainPlotMinimumHeight
            )
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: state.startMarker ... state.endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis { mainChartYAxis }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let selection, let plot = proxy.plotFrame,
                       let x = proxy.position(forX: selection)
                    {
                        let frame = geometry[plot]
                        Color.clear.anchorPreference(
                            key: SelectionLineTop.self,
                            value: .point(CGPoint(x: frame.minX + x, y: frame.minY))
                        ) { $0 }
                    }
                }
                .allowsHitTesting(false)
            }
            .chartXSelection(value: $selection)
            .chartYScale(
                domain: units == .mgdL ? state.minYAxisValue ... state.maxYAxisValue : state.minYAxisValue
                    .asMmolL ... state.maxYAxisValue.asMmolL
            )
            .chartLegend(.hidden)
            .chartForegroundStyleScale([
                "iob": Color.insulin,
                "uam": Color.uam,
                "zt": Color.zt,
                "cob": Color.orange
            ])
        }
    }
}
