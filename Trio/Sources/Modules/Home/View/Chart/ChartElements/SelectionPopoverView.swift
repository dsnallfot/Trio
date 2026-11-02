import Charts
import Foundation
import SwiftUI

struct SelectionPopoverView: ChartContent {
    let selection: Date
    let selectedGlucose: GlucoseStored?
    let selectedIOBValue: OrefDetermination?
    let selectedCOBValue: OrefDetermination?
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let glucoseColorScheme: GlucoseColorScheme

    private var glucoseToDisplay: Decimal? {
        guard let selectedGlucose else { return nil }
        return units == .mgdL ? Decimal(selectedGlucose.glucose) : Decimal(selectedGlucose.glucose).asMmolL
    }

    /// Formats the glucose value so that if the units are mmol/L, it always shows one decimal place.
    private var formattedGlucose: String {
        guard let glucoseToDisplay else { return "--" }
        if units == .mmolL {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            return formatter.string(from: glucoseToDisplay as NSDecimalNumber) ?? "\(glucoseToDisplay)"
        } else {
            return "\(glucoseToDisplay)"
        }
    }

    private var pointMarkColor: Color {
        guard let selectedGlucose else { return .secondary }
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

        return Trio.getDynamicGlucoseColor(
            glucoseValue: Decimal(selectedGlucose.glucose),
            highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
            lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
            targetGlucose: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    var body: some ChartContent {
        RuleMark(x: .value("Selection", selection))
            .foregroundStyle(Color.tabBar)
            .lineStyle(.init(lineWidth: 2))

        if let date = selectedGlucose?.date, let glucoseToDisplay {
            PointMark(
                x: .value("Time", date),
                y: .value("Value", glucoseToDisplay)
            )
            .zIndex(-1)
            .symbolSize(CGSize(width: 15, height: 15))
            .foregroundStyle(pointMarkColor)

            PointMark(
                x: .value("Time", date),
                y: .value("Value", glucoseToDisplay)
            )
            .zIndex(-1)
            .symbolSize(CGSize(width: 6, height: 6))
            .foregroundStyle(Color.primary)
        }
    }

    var selectionPopover: some View {
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text(selection.formatted(.dateTime.hour().minute(.twoDigits)))
            }
            .frame(maxWidth: .infinity)

            Text("\(formattedGlucose) \(units.rawValue)")
                .foregroundStyle(pointMarkColor)
                .frame(maxWidth: .infinity)

            let iob = selectedIOBValue?.iob.flatMap { Formatter.bolusFormatter.string(from: $0) } ?? "--"
            (Text("IOB") + Text(verbatim: " " + iob + NSLocalizedString(" E", comment: "Insulin unit")))
                .foregroundStyle(Color.insulin)
                .frame(maxWidth: .infinity)

            let cob = selectedCOBValue.flatMap { Formatter.integerFormatter.string(from: $0.cob as NSNumber) } ?? "--"
            (Text("COB") + Text(verbatim: " " + cob + NSLocalizedString(" g", comment: "gram of carbs")))
                .foregroundStyle(Color.orange)
                .frame(maxWidth: .infinity)
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassPanel()
        .accessibilityElement(children: .combine)
    }
}
