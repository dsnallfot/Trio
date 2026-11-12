import Foundation

/// A snapshot of the programmed therapy settings, without overrides or temporary targets.
struct SavedTherapyProfile: JSON, Identifiable {
    var id = UUID()
    var name: String
    let basal: [BasalProfileEntry]
    let sensitivities: InsulinSensitivities
    let carbRatios: CarbRatios
    let targets: BGTargets

    var totalBasal: Decimal {
        zip(basal, basal.dropFirst().map(\.minutes) + [1440]).reduce(0) {
            $0 + $1.0.rate * Decimal($1.1 - $1.0.minutes) / 60
        }
    }

    var isValid: Bool {
        func validTimes(_ times: [Int]) -> Bool {
            times.first == 0 && times.allSatisfy { (0 ..< 1440).contains($0) } &&
                zip(times, times.dropFirst()).allSatisfy { $0 < $1 }
        }
        return validTimes(basal.map(\.minutes)) &&
            validTimes(sensitivities.sensitivities.map(\.offset)) &&
            validTimes(carbRatios.schedule.map(\.offset)) &&
            validTimes(targets.targets.map(\.offset)) &&
            basal.allSatisfy { !$0.rate.isNaN && $0.rate >= 0 } &&
            sensitivities.units == .mgdL && sensitivities.userPreferredUnits == .mgdL &&
            sensitivities.sensitivities.allSatisfy { !$0.sensitivity.isNaN && $0.sensitivity > 0 } &&
            carbRatios.units == .grams && carbRatios.schedule.allSatisfy { !$0.ratio.isNaN && $0.ratio > 0 } &&
            targets.units == .mgdL && targets.userPreferredUnits == .mgdL &&
            targets.targets.allSatisfy { !$0.low.isNaN && !$0.high.isNaN && $0.low > 0 && $0.high >= $0.low }
    }
}
