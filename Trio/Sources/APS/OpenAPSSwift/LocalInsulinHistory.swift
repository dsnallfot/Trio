import Foundation

/// TDD from reconciled pump history plus inferred scheduled delivery (PR #1300).
/// Inferred intervals use the existing local pump-increment rounding; finalized totals win.
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
        clock: Date,
        since: Date? = nil
    ) throws -> Result {
        guard !basal.isEmpty else { throw JSONError.invalidString }
        let start = since ?? clock.addingTimeInterval(-24 * 3600)
        let history = history.filter { $0.timestamp <= clock }
        let events = BasalDeliveryTimeline.events(from: history)
        let segments = BasalDeliveryTimeline.segments(events: events, profile: basal, now: clock, since: start)
        let step: Decimal = increment == Decimal(string: "0.1")! ? Decimal(string: "0.1")! : Decimal(string: "0.05")!
        func rounded(_ value: Decimal) -> Decimal {
            var value = max(0, value), output = Decimal()
            NSDecimalRound(&output, &value, 5, .plain)
            return output
        }
        func inferred(_ units: Decimal) -> Decimal {
            var pulses = rounded(units) / step, whole = Decimal()
            NSDecimalRound(&whole, &pulses, 0, .down)
            return max(0, whole * step)
        }
        let bolus = history.filter { $0.type == .bolus && $0.timestamp >= start }.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
        let scheduled = segments.filter(\.scheduled).reduce(Decimal.zero) { $0 + inferred($1.units) }
        let grouped = Dictionary(grouping: segments.filter { !$0.scheduled }, by: { $0.sourceID ?? "" })
        var temp: Decimal = 0
        for event in events where event.kind == .temp {
            let covered = grouped[event.id] ?? []
            let units = covered.reduce(Decimal.zero) { $0 + $1.units }
            if let delivered = event.deliveredUnits, event.end <= clock, event.start >= start {
                // Final pump total includes pulse quantization and interruptions.
                temp += max(0, delivered)
            } else if let delivered = event.deliveredUnits, event.end <= clock, event.end > start,
                      event.end > event.start
            {
                // Only a boundary-crossing finalized dose needs time-proportional clipping.
                temp += max(0, delivered) * Decimal(event.end.timeIntervalSince(start) / event.end.timeIntervalSince(event.start))
            } else {
                temp += inferred(units)
            }
        }
        let total = rounded(bolus + temp + scheduled)
        let earliest = events.map(\.start).min() ?? clock
        let hours = max(0, clock.timeIntervalSince(max(start, earliest)) / 3600)
        return Result(insulin: Insulin(
            TDD: total,
            bolus: rounded(bolus),
            temp_basal: rounded(temp),
            scheduled_basal: rounded(scheduled)
        ), hours: hours, total: total)
    }
}
