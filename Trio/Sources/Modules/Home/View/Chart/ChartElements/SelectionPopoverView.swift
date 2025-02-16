import Charts
import Foundation
import SwiftUICore

struct SelectionPopoverView: ChartContent {
    let selectedGlucose: GlucoseStored
    let selectedIOBValue: OrefDetermination?
    let selectedCOBValue: OrefDetermination?
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let glucoseColorScheme: GlucoseColorScheme

    private var glucoseToDisplay: Decimal {
        units == .mgdL ? Decimal(selectedGlucose.glucose) : Decimal(selectedGlucose.glucose).asMmolL
    }

    /// Formats the glucose value so that if the units are mmol/L, it always shows one decimal place.
    private var formattedGlucose: String {
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
        RuleMark(x: .value("Selection", selectedGlucose.date ?? Date.now, unit: .minute))
            .foregroundStyle(Color.tabBar)
            .offset(yStart: 70)
            .lineStyle(.init(lineWidth: 2))
            .annotation(
                position: .top,
                alignment: .center,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                selectionPopover
            }

        PointMark(
            x: .value("Time", selectedGlucose.date ?? Date.now, unit: .minute),
            y: .value("Value", glucoseToDisplay)
        )
        .zIndex(-1)
        .symbolSize(CGSize(width: 15, height: 15))
        .foregroundStyle(pointMarkColor)

        PointMark(
            x: .value("Time", selectedGlucose.date ?? Date.now, unit: .minute),
            y: .value("Value", glucoseToDisplay)
        )
        .zIndex(-1)
        .symbolSize(CGSize(width: 6, height: 6))
        .foregroundStyle(Color.primary)
    }

    @ViewBuilder var selectionPopover: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "clock")
                Text(selectedGlucose.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                    .font(.body).bold()
            }
            .font(.body).padding(.bottom, 5)

            HStack {
                // Use the formattedGlucose string to ensure one decimal when units are mmol/L.
                Text(formattedGlucose).bold() + Text(" \(units.rawValue)")
            }
            .foregroundStyle(pointMarkColor)
            .font(.body)

            if let selectedIOBValue, let iob = selectedIOBValue.iob {
                HStack {
                    // Image(systemName: "syringe.fill").frame(width: 15)
                    Text("IOB")
                        .bold()
                    Text(Formatter.bolusFormatter.string(from: iob) ?? "")
                        .bold()
                        + Text(NSLocalizedString(" E", comment: "Insulin unit"))
                }
                .foregroundStyle(Color.insulin).font(.body)
            }

            if let selectedCOBValue {
                HStack {
                    // Image(systemName: "fork.knife").frame(width: 15)
                    Text("COB")
                        .bold()
                    Text(Formatter.integerFormatter.string(from: selectedCOBValue.cob as NSNumber) ?? "")
                        .bold()
                        + Text(NSLocalizedString(" g", comment: "gram of carbs"))
                }
                .foregroundStyle(Color.orange).font(.body)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.chart.opacity(0.85))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary, lineWidth: 2)
                )
        }
    }
}
