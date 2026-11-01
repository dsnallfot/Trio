import Foundation

/// Reconstructs delivery only within observed history. Scheduled segments are inferred,
/// never pump commands. Both chart and TDD consume this same timeline.
enum BasalDeliveryTimeline {
    struct Event {
        enum Kind { case temp, suspend, resume, anchor, detached, attached }
        let start: Date
        let end: Date
        let kind: Kind
        var rate: Decimal = 0
        var deliveredUnits: Decimal? = nil
        var id: String = ""
    }

    struct Segment {
        let start: Date
        var end: Date
        let rate: Decimal
        let scheduled: Bool
        let sourceID: String?
        var units: Decimal { rate * Decimal(end.timeIntervalSince(start) / 3600) }
    }

    static func segments(
        events: [Event],
        profile: [BasalProfileEntry],
        now: Date,
        includeRemainingTemp: Bool = false,
        since: Date? = nil,
        calendar: Calendar = .current
    ) -> [Segment] {
        let events = events.filter { $0.start <= now }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            // At an identical instant suspension wins; anchors never change delivery state.
            func priority(_ kind: Event.Kind) -> Int {
                switch kind { case .attached: return 0
                case .anchor: return 1
                case .resume: return 2
                case .temp: return 3
                case .suspend: return 4
                case .detached: return 5 }
            }
            return priority($0.kind) < priority($1.kind)
        }
        guard let first = events.first?.start, first <= now, !profile.isEmpty else { return [] }
        let beginning = max(first, since ?? now.addingTimeInterval(-24 * 3600))
        let profile = profile.sorted { $0.minutes < $1.minutes }
        var boundaries = Set([beginning, now])
        for event in events {
            if event.start >= beginning { boundaries.insert(event.start) }
            if event.end > beginning, event.end < now { boundaries.insert(event.end) }
            // The chart also shows the remaining programmed time of the active temp.
            if includeRemainingTemp, event.kind == .temp, event.end > now { boundaries.insert(event.end) }
        }
        var day = calendar.startOfDay(for: beginning)
        while day < now {
            for entry in profile {
                if let date = calendar.date(bySettingHour: entry.minutes / 60, minute: entry.minutes % 60, second: 0, of: day),
                   date > beginning, date < now { boundaries.insert(date) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // A first resume is evidence that the window opened suspended.
        var suspended = events.first(where: { $0.kind == .suspend || $0.kind == .resume })?.kind == .resume
        var detached = false
        var current: Event?
        var cursor = 0
        var result: [Segment] = []
        let times = boundaries.sorted()
        for (start, end) in zip(times, times.dropFirst()) {
            while cursor < events.count, events[cursor].start <= start {
                let event = events[cursor]
                switch event.kind {
                case .suspend: suspended = true
                    current = nil
                case .resume: suspended = false
                    current = nil
                case .temp: current = event.end > start ? event : nil
                case .detached: detached = true
                    current = nil
                case .attached: detached = false
                    suspended = false
                    current = nil
                case .anchor: break
                }
                cursor += 1
            }
            guard !detached, !suspended, end > start else { continue }
            if let temp = current, temp.end > start {
                // Draw one chart block per temp command, even across intervening boluses.
                if includeRemainingTemp, let last = result.last, last.end == start, last.sourceID == temp.id,
                   last.rate == temp.rate, temp.start < start
                {
                    result[result.count - 1].end = end
                } else {
                    result.append(Segment(start: start, end: end, rate: temp.rate, scheduled: false, sourceID: temp.id))
                }
            } else if start < now {
                let parts = calendar.dateComponents([.hour, .minute], from: start)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                guard let rate = (profile.last(where: { $0.minutes <= minutes }) ?? profile.last)?.rate else { continue }
                // Merge incidental boundaries so pulse rounding doesn't lose insulin at bolus timestamps.
                if let last = result.last, last.scheduled, last.end == start, last.rate == rate {
                    result[result.count - 1].end = end
                } else {
                    result.append(Segment(start: start, end: end, rate: rate, scheduled: true, sourceID: nil))
                }
            }
        }
        return result
    }

    static func events(from history: [PumpHistoryEvent]) -> [Event] {
        let durations = Dictionary(
            history.filter { $0.type == .tempBasalDuration }.map { ($0.timestamp, $0.durationMin ?? 0) },
            uniquingKeysWith: { first, _ in first }
        )
        return history.compactMap { item in
            switch item.type {
            case .tempBasal:
                let end = item.endDate ?? item.timestamp
                    .addingTimeInterval(Double(durations[item.timestamp] ?? item.duration ?? 0) * 60)
                return Event(
                    start: item.timestamp,
                    end: max(item.timestamp, end),
                    kind: .temp,
                    rate: item.rate ?? item.amount ?? 0,
                    deliveredUnits: item.deliveredUnits,
                    id: item.id
                )
            case .pumpAttached: return Event(start: item.timestamp, end: item.timestamp, kind: .attached)
            case .pumpDetached: return Event(start: item.timestamp, end: item.timestamp, kind: .detached)
            case .pumpSuspend:
                return Event(start: item.timestamp, end: item.timestamp, kind: .suspend)
            case .pumpResume:
                return Event(start: item.timestamp, end: item.timestamp, kind: .resume)
            case .bolus,
                 .prime,
                 .rewind,
                 .scheduledBasal:
                return Event(start: item.timestamp, end: item.timestamp, kind: .anchor)
            default: return nil
            }
        }
    }
}
