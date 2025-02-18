import Charts
import Foundation
import SwiftUI

extension MainChartView {
    var cobIobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawCOBIOBChart()

            // Draw selected COB point (if any)
            if let selectedCOBValue {
                drawSelectedInnerPoint(
                    xValue: selectedCOBValue.deliverAt ?? Date.now,
                    yValue: Double(selectedCOBValue.cob),
                    axis: "COB"
                )
                drawSelectedOuterPoint(
                    xValue: selectedCOBValue.deliverAt ?? Date.now,
                    yValue: Double(selectedCOBValue.cob),
                    axis: "IOB",
                    color: Color.orange
                )
            }

            // Draw selected IOB point (if any)
            if let selectedIOBValue {
                let rawAmount = selectedIOBValue.iob?.doubleValue ?? 0
                // Convert our Decimal conversion factor to Double.
                let conversionFactor: Double = NSDecimalNumber(decimal: state.IobCobConversionFactor).doubleValue
                let scaledAmount = rawAmount * conversionFactor

                drawSelectedInnerPoint(
                    xValue: selectedIOBValue.deliverAt ?? Date.now,
                    yValue: scaledAmount,
                    axis: "COB" // using COB scale
                )
                drawSelectedOuterPoint(
                    xValue: selectedIOBValue.deliverAt ?? Date.now,
                    yValue: scaledAmount,
                    axis: "IOB",
                    color: Color.darkerBlue
                )
            }
        }
        .chartForegroundStyleScale([
            "COB": Color.orange,
            "IOB": Color.insulin
        ])
        .chartLegend(.hidden)
        .frame(minHeight: geo.size.height * 0.12)
        .frame(width: fullWidth(viewWidth: screenSize.width))
        .chartXScale(domain: state.startMarker ... state.endMarker)
        .chartXSelection(value: $selection)
        .chartXAxis { basalChartXAxis }
        .chartYAxis { cobIobChartYAxis }
        .chartYScale(domain: combinedYDomain())
    }

    /// Computes the y‑axis domain.
    /// - If COB exists, scale IOB values (using factor 20) and take the min/max.
    /// - Otherwise, fix the domain to 0...120.
    func combinedYDomain() -> ClosedRange<Double> {
        let maxCob = NSDecimalNumber(decimal: state.maxValueCobChart).doubleValue
        if maxCob <= 0 {
            // No COB data – force y‑axis from 0 to 120.
            return 0.0 ... 120.0
        } else {
            let conversionFactor = NSDecimalNumber(decimal: state.IobCobConversionFactor).doubleValue
            let minCob = NSDecimalNumber(decimal: state.minValueCobChart).doubleValue
            let maxCob = NSDecimalNumber(decimal: state.maxValueCobChart).doubleValue
            // Apply conversion factor to IOB bounds
            let minIobScaled = NSDecimalNumber(decimal: state.minValueIobChart).doubleValue * conversionFactor
            let maxIobScaled = NSDecimalNumber(decimal: state.maxValueIobChart).doubleValue * conversionFactor
            let minValue = min(minCob, minIobScaled)
            let maxValue = max(maxCob, maxIobScaled)
            /* print(
                 "Combined domain: \(minValue)...\(maxValue), COB: [\(minCob), \(maxCob)], IOB (scaled): [\(minIobScaled), \(maxIobScaled)]"
             ) */
            return minValue ... maxValue
        }
    }

    private func drawSelectedInnerPoint(xValue: Date, yValue: Double, axis: String) -> some ChartContent {
        PointMark(
            x: .value("Time", xValue, unit: .minute),
            y: .value("Value", yValue)
        )
        .symbolSize(CGSize(width: 6, height: 6))
        .foregroundStyle(Color.primary)
        .position(by: .value("Axis", axis))
    }

    private func drawSelectedOuterPoint(xValue: Date, yValue: Double, axis: String, color: Color) -> some ChartContent {
        PointMark(
            x: .value("Time", xValue, unit: .minute),
            y: .value("Value", yValue)
        )
        .symbolSize(CGSize(width: 15, height: 15))
        .foregroundStyle(color.opacity(0.8))
        .position(by: .value("Axis", axis))
    }

    @ChartContentBuilder func drawCOBIOBChart() -> some ChartContent {
        let conversionFactor: Double = NSDecimalNumber(decimal: state.IobCobConversionFactor).doubleValue

        // Filter out duplicate entries by deliverAt
        var seenDates = Set<Date>()
        let filteredDeterminations = state.enactedAndNonEnactedDeterminations.filter { item in
            if let date = item.deliverAt {
                if seenDates.contains(date) {
                    return false
                } else {
                    seenDates.insert(date)
                    return true
                }
            }
            return true
        }

        ForEach(filteredDeterminations, id: \.id) { item in
            // Ensure we have a Date from deliverAt; adjust the cast if needed.
            let date: Date = (item.deliverAt as? Date) ?? Date()

            // COB marks
            let amountCOB = Double(item.cob)
            LineMark(x: .value("Time", date), y: .value("Value", amountCOB))
                .foregroundStyle(by: .value("Type", "COB"))
                .position(by: .value("Axis", "COB"))
            AreaMark(x: .value("Time", date), y: .value("Value", amountCOB))
                .foregroundStyle(by: .value("Type", "COB"))
                .position(by: .value("Axis", "COB"))
                .opacity(0.2)

            // Draw IOB marks with scaling
            let rawAmount = item.iob?.doubleValue ?? 0
            let amountIOB = rawAmount * conversionFactor
            AreaMark(x: .value("Time", date), y: .value("Value", amountIOB))
                .foregroundStyle(by: .value("Type", "IOB"))
                .position(by: .value("Axis", "IOB"))
                .opacity(0.2)
            LineMark(x: .value("Time", date), y: .value("Value", amountIOB))
                .foregroundStyle(by: .value("Type", "IOB"))
                .position(by: .value("Axis", "IOB"))
        }
    }
}
