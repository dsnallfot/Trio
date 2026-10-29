import Foundation

/// Compatibility with the TDD calculation in the app's bundled determine-basal.js.
/// Input order and per-segment pump-increment rounding are significant.
enum LocalInsulinHistory {
    struct Result {
        let insulin: Insulin
        let hours: Double
        let total: Decimal
        var allowsDynamicISF: Bool { hours >= 21 }
    }

    static func calculate(
        history: [PumpHistoryEvent],
        basal: [BasalProfileEntry],
        increment: Decimal,
        clock: Date
    ) throws -> Result {
        guard !basal.isEmpty else { throw JSONError.invalidString }
        let step = increment == 0.1 ? 0.1 : 0.05
        func rounded(_ value: Double, _ places: Int = 5) -> Decimal {
            let factor = pow(10.0, Double(places))
            return Decimal(floor(value * factor + 0.5) / factor)
        }
        func delivered(_ value: Double) -> Double {
            guard value.isFinite, value / step >= 1 else { return 0 }
            return Double(truncating: rounded(floor(value / step) * step) as NSNumber)
        }
        func scheduled(from: Date, to: Date) -> Double {
            var remaining = to.timeIntervalSince(from) / 3600
            let initial = remaining
            var cursor = from
            var total = 0.0
            // Match JS's minute-resolution schedule lookup, including 23:59:59 boundary.
            var iterations = 0
            repeat {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: cursor)
                let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60
                for index in basal.indices where remaining > 0 {
                    let start = basal[index].minutes * 60
                    let next = index + 1 < basal.count ? basal[index + 1].minutes * 60 : 86400
                    guard seconds >= start, seconds < next else { continue }
                    let end = seconds == start ? next : (index + 1 == basal.count ? 86399 : next)
                    let duration = min(remaining, Double(end - seconds) / 3600)
                    guard duration > 0 else { continue }
                    total += delivered(Double(truncating: basal[index].rate as NSNumber) * duration)
                    remaining -= duration
                    cursor = cursor.addingTimeInterval(duration * 3600)
                }
                iterations += 1
            } while remaining > 0 && remaining < initial && iterations < 1000
            return total
        }
        var hours = 0.0
        var scheduledInsulin = 0.0
        if let first = history.first, let last = history.last {
            let newest = first.type == .tempBasalDuration ? clock : first.timestamp
            hours = newest.timeIntervalSince(last.timestamp) / 3600
            if hours < 23.9, hours > 21 {
                scheduledInsulin = scheduled(from: last.timestamp.addingTimeInterval(-(24 - hours) * 3600), to: last.timestamp)
            }
        }
        let bolus = history.filter { $0.type == .bolus }.reduce(0.0) { $0 + Double(truncating: ($1.amount ?? 0) as NSNumber) }
        var temp = 0.0
        if history.count > 1 {
            for index in 1 ..< history.count where history[index].type == .tempBasal && (history[index].rate ?? 0) > 0 {
                guard let minutes = history[index - 1].durationMin else { continue }
                let original = Double(minutes) / 60
                let past = history[index - 1].timestamp
                var present = past
                var rewind = 0.0
                var j = index
                repeat {
                    j -= 1
                    if j == 0 { present = clock
                        break }
                    if history[j].type == .tempBasal || history[j].type == .pumpSuspend {
                        present = history[j].timestamp
                        break
                    }
                    var pp = j - 2
                    if pp >= 0, history[pp].type == .rewind {
                        // JS subtracts ISO timestamp strings here (NaN). Its increment
                        // guard then contributes zero for this segment. Preserve that
                        // behavior until a separately reviewed history correction.
                        while pp > 0 {
                            pp -= 1
                            guard history[pp].type == .prime else { break }
                            rewind = .nan
                        }
                    }
                } while j > 0
                let duration = min(original, present.timeIntervalSince(past) / 3600)
                temp += delivered(Double(truncating: (history[index].rate ?? 0) as NSNumber) * (duration - rewind))
            }
            for index in history.indices where history[index].durationMin == 0 || history[index].type == .pumpResume {
                if let next = history[..<index].last(where: { $0.type == .tempBasal }) {
                    scheduledInsulin += scheduled(from: history[index].timestamp, to: next.timestamp)
                }
            }
            for index in (1 ..< history.count).reversed() where history[index].type == .tempBasalDuration {
                guard let minutes = history[index].durationMin,
                      let next = history[..<index].last(where: { $0.type == .tempBasal || $0.type == .pumpSuspend })
                else { continue }
                let start = history[index].timestamp.addingTimeInterval(Double(minutes) * 60)
                if next.timestamp > start { scheduledInsulin += scheduled(from: start, to: next.timestamp) }
            }
        }
        let total = bolus + temp + scheduledInsulin
        return Result(
            insulin: Insulin(
                TDD: rounded(total),
                bolus: rounded(bolus),
                temp_basal: rounded(temp),
                scheduled_basal: rounded(scheduledInsulin)
            ),
            hours: hours,
            total: Decimal(total)
        )
    }
}
