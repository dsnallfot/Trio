import Foundation

@available(iOS 16.0, *) final class ManualGlucoseIntentRequest: BaseIntentsRequest {
    func addManualGlucose(
        _ glucose: Double,
        _ dateAdded: Date
    ) async throws -> String {
        guard glucose > 0 else {
            return "Registrerar inte blodsocker i Trio"
        }

        let glucoseAsInt: Int

        if settingsManager.settings.units == .mmolL {
            glucoseAsInt = NSDecimalNumber(
                decimal: glucose.asMgdL
            ).intValue
        } else {
            glucoseAsInt = Int(glucose)
        }

        await glucoseStorage.addManualGlucose(
            glucose: glucoseAsInt,
            date: dateAdded
        )

        let displayValue = formatGlucoseValue(glucose)
        let unit = settingsManager.settings.units == .mmolL
            ? "mmol/L"
            : "mg/dL"

        let dateName = dateAdded.formatted()

        return "\(displayValue) \(unit) lades till \(dateName)"
    }

    func formatGlucoseValue(_ glucose: Double) -> String {
        if settingsManager.settings.units == .mmolL {
            return String(format: "%.1f", glucose)
        } else {
            return String(format: "%.0f", glucose)
        }
    }
}
