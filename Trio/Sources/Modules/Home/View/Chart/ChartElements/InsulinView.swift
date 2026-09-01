import Charts
import Foundation
import SwiftUI

struct InsulinView: ChartContent {
    let glucoseData: [GlucoseStored]
    let insulinData: [PumpEventStored]
    let units: GlucoseUnits
    let maxBolus = 2.5

    var body: some ChartContent {
        drawBoluses()
    }

    private func drawBoluses() -> some ChartContent {
        ForEach(insulinData) { (insulin: PumpEventStored) in
            let amount: NSDecimalNumber = insulin.bolus?.amount ?? NSDecimalNumber.zero
            let bolusDate = insulin.timestamp ?? Date()

            if amount != 0, let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: bolusDate.timeIntervalSince1970
            )?.glucose {
                let yPosition = (
                    units == .mgdL
                        ? Decimal(glucose)
                        : Decimal(glucose).asMmolL
                )
                    + MainChartHelper.bolusOffset(units: units)

                let bolusAmount = CGFloat(truncating: amount)

                let maxBolus = max(
                    CGFloat(truncating: self.maxBolus as NSNumber),
                    0.05
                )

                let clampedBolusAmount = min(
                    max(bolusAmount, 0.05),
                    maxBolus
                )

                let size = maxBolus > 0.05
                    ? MainChartHelper.Config.bolusMinSize
                    + (clampedBolusAmount - 0.05)
                    * (
                        MainChartHelper.Config.bolusMaxSize
                            - MainChartHelper.Config.bolusMinSize
                    )
                    / (maxBolus - 0.05)
                    : MainChartHelper.Config.bolusMinSize

                PointMark(
                    x: .value("Time", bolusDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: size))
                        .foregroundStyle(Color.insulin)
                }
                .annotation(position: .top) {
                    Text(Formatter.bolusFormatter.string(from: amount) ?? "")
                        .font(.caption2)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }
}
