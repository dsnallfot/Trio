import Charts
import CoreData
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var paddingAmount: CGFloat? = 10
        @State var headline: Color = .secondary
        @State var days: Double = 0
        @State var pointSize: CGFloat = 3
        @State var conversionFactor = 0.0555

        @ViewBuilder func stats() -> some View {
            ZStack {
                Color.clear.ignoresSafeArea(.all)
                let filter = DateFilter()
                switch state.selectedDuration {
                case .Today:
                    StatsView(
                        filter: filter.today,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                        showInsulin: true,
                        insulin: state.insulinToday
                    )
                case .Day:
                    StatsView(
                        filter: filter.day,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                        showInsulin: true,
                        insulin: state.insulinDay
                    )
                case .Week:
                    StatsView(
                        filter: filter.week,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                case .Month:
                    StatsView(
                        filter: filter.month,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                    // case .Total:
                    // EmptyView()
                }
            }
        }

        @ViewBuilder func chart() -> some View {
            switch state.selectedDuration {
            case .Today:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Day:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Week:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Month:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
                // case .Total:
                // EmptyView()
            }
        }

        var body: some View {
            VStack(alignment: .center) {
                chart().padding(.top, 20)
                StatsDurationPicker(selection: $state.selectedDuration)
                    .padding(.horizontal, 10)
                    .onChange(of: state.selectedDuration) { _, newValue in
                        state.setupGlucoseArray(for: newValue)
                    }
                stats()
                    .padding(.top, 6)
            }.background(appState.trioBackgroundColor(for: colorScheme))
                .task(id: state.selectedDuration) {
                    configureView()
                    await state.loadInsulinStatistics()
                }
                .navigationBarTitle("Statistics")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading, content: {
                        Button(
                            action: { state.hideModal() },
                            label: {
                                HStack {
                                    Text("Close")
                                }
                            }
                        )
                    })
                }
        }
    }
}

/// Mirrors the Home time picker, committing a scrub only when the finger is released.
private struct StatsDurationPicker: View {
    @Binding var selection: Stat.StateModel.Duration
    @GestureState private var scrubbedDuration: Stat.StateModel.Duration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var pickerHeight = 32.0

    private let options = Stat.StateModel.Duration.selectableCases
    private var displayedDuration: Stat.StateModel.Duration { scrubbedDuration ?? selection }

    var body: some View {
        if #available(iOS 26.0, *) {
            segments.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            segments.background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var segments: some View {
        GeometryReader { geometry in
            let segmentWidth = geometry.size.width / CGFloat(options.count)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.16))
                    .frame(width: segmentWidth, height: geometry.size.height)
                    .offset(x: CGFloat(options.firstIndex(of: displayedDuration) ?? 0) * segmentWidth)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: displayedDuration)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(options) { duration in
                        Button {
                            selection = duration
                        } label: {
                            Text(NSLocalizedString(duration.rawValue, comment: ""))
                                .font(.footnote)
                                .fontWeight(displayedDuration == duration ? .semibold : .regular)
                                .foregroundStyle(displayedDuration == duration ? .primary : .secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == duration ? .isSelected : [])
                    }
                }
            }
            .contentShape(Capsule())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .updating($scrubbedDuration) { value, preview, _ in
                        preview = option(at: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { value in
                        selection = option(at: value.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: pickerHeight)
        .accessibilityIdentifier("statsDurationPicker")
    }

    private func option(at x: CGFloat, width: CGFloat) -> Stat.StateModel.Duration {
        let index = Int((max(0, min(x, width)) / max(width, 1) * CGFloat(options.count)).rounded(.down))
        return options[min(index, options.count - 1)]
    }
}
