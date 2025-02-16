import Charts
import Foundation
import SwiftUI

extension MainChartView {
    var cobIobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawCOBIOBChart()

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
            if let selectedIOBValue {
                let rawAmount = selectedIOBValue.iob?.doubleValue ?? 0
                let conversionFactor: Double = 20.0
                let amount = rawAmount * conversionFactor

                drawSelectedInnerPoint(
                    xValue: selectedIOBValue.deliverAt ?? Date.now,
                    yValue: amount,
                    axis: "COB" // if you want the point to align on the same scale as COB
                )
                drawSelectedOuterPoint(
                    xValue: selectedIOBValue.deliverAt ?? Date.now,
                    yValue: amount,
                    axis: "IOB",
                    color: Color.darkerBlue
                )
            }
            /*
             if let selectedIOBValue {
                 let rawAmount = selectedIOBValue.iob?.doubleValue ?? 0
                 let amount: Double = rawAmount > 0 ? rawAmount * 8 : rawAmount * 9

                 drawSelectedInnerPoint(
                     xValue: selectedIOBValue.deliverAt ?? Date.now,
                     yValue: amount,
                     axis: "COB"
                 )
                 drawSelectedOuterPoint(
                     xValue: selectedIOBValue.deliverAt ?? Date.now,
                     yValue: amount,
                     axis: "IOB",
                     color: Color.darkerBlue
                 )
             }
             */
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

    func combinedYDomain() -> ClosedRange<Double> {
        let minValue = min(state.minValueCobChart, state.minValueIobChart)
        let maxValue = max(state.maxValueCobChart, state.maxValueIobChart)
        return Double(minValue) ... Double(maxValue)
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

    /*
     func drawCOBIOBChart() -> some ChartContent {
         ForEach(state.enactedAndNonEnactedDeterminations) { item in

             // MARK: - COB line and area mark

             let amountCOB = Int(item.cob)
             let date: Date = item.deliverAt ?? Date()

             LineMark(x: .value("Time", date), y: .value("Value", amountCOB))
                 .foregroundStyle(by: .value("Type", "COB"))
                 .position(by: .value("Axis", "COB"))
             AreaMark(x: .value("Time", date), y: .value("Value", amountCOB))
                 .foregroundStyle(by: .value("Type", "COB"))
                 .position(by: .value("Axis", "COB"))
                 .opacity(0.2)

             // MARK: - IOB line and area mark

             let rawAmount = item.iob?.doubleValue ?? 0

             // as iob and cob share the same y axis and cob is usually >> iob we need to weigh iob visually
             let amountIOB: Double = rawAmount > 0 ? rawAmount * 8 : rawAmount * 9

             AreaMark(x: .value("Time", date), y: .value("Amount", amountIOB))
                 .foregroundStyle(by: .value("Type", "IOB"))
                 .position(by: .value("Axis", "IOB"))
                 .opacity(0.2)
             LineMark(x: .value("Time", date), y: .value("Amount", amountIOB))
                 .foregroundStyle(by: .value("Type", "IOB"))
                 .position(by: .value("Axis", "IOB"))
         }
     }
     */
    /*
     @ChartContentBuilder func drawCOBIOBChart() -> some ChartContent {
         // Daniel Conversion factor similar to average CR: how many COB units equal 1 IOB unit in visual line height.
         let conversionFactor: Double = 20.0

         ForEach(state.enactedAndNonEnactedDeterminations, id: \.id) { item in
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

             // IOB marks using the conversion factor
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
     */
    @ChartContentBuilder func drawCOBIOBChart() -> some ChartContent {
        // Daniel Conversion factor similar to average CR: how many COB units equal 1 IOB unit in visual line height.
        let conversionFactor: Double = 20.0

        // Filter out duplicate entries by `deliverAt`
        // We sometimes get two determinations when editing carbs – one without the entry-to-be-edited and then another one after editing.
        // Since the array is in descending order, the first one is the correct (edited) entry, so we keep that.
        var seenDates = Set<Date>()
        let filteredDeterminations = state.enactedAndNonEnactedDeterminations.filter { item in
            if let date = item.deliverAt as? Date {
                if seenDates.contains(date) {
                    // Already seen this date – filter it out.
                    return false
                } else {
                    seenDates.insert(date)
                    return true
                }
            }
            return true
        }

        // Use the filtered results for drawing the chart
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

            // IOB marks using the conversion factor
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
