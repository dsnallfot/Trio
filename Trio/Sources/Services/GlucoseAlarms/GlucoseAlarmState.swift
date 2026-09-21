import Foundation

/// Pure, persisted alarm decisions. No sensor, UI, notification or dosing dependencies.
struct GlucoseAlarmState: Codable {
    enum Kind: String, Codable { case low, high, urgentLow, urgentHigh }
    struct Reading {
        let date: Date
        let mgdL: Decimal
    }

    struct Event {
        let id: UUID
        let kind: Kind
        let reading: Reading
    }

    struct Decision {
        var cancelled: UUID?
        var issued: Event?
    }

    static let freshness: TimeInterval = 12 * 60
    static let repeatInterval: TimeInterval = 15 * 60
    var lastSeen: Date?
    var lastAlertReading: Date?
    var lastAlertAt: Date?
    var kind: Kind?
    var activeID: UUID?
    // Preserve an already-running shared pause from older builds until it expires.
    var snoozeUntil: Date = .distantPast
    var lowSnoozeUntil: Date?
    var highSnoozeUntil: Date?

    var urgentLowSnoozeUntil: Date?
    var urgentHighSnoozeUntil: Date?

    func snoozeDeadline(for kind: Kind?) -> Date {
        let specific: Date?
        switch kind {
        case .low: specific = lowSnoozeUntil
        case .high: specific = highSnoozeUntil
        case .urgentLow: specific = urgentLowSnoozeUntil
        case .urgentHigh: specific = urgentHighSnoozeUntil
        case nil: specific = nil
        }
        return max(snoozeUntil, specific ?? .distantPast)
    }

    mutating func acknowledge(id: UUID, now: Date, snoozeMinutes: Int = 15) -> UUID? {
        guard activeID == id, let kind else { return nil }
        activeID = nil
        let until = now.addingTimeInterval(TimeInterval(GlucoseAlarmConfiguration.validatedSnooze(snoozeMinutes) * 60))
        switch kind {
        case .low: lowSnoozeUntil = until
        case .high: highSnoozeUntil = until
        case .urgentLow: urgentLowSnoozeUntil = until
        case .urgentHigh: urgentHighSnoozeUntil = until
        }
        // An explicit short snooze must not be extended by the automatic 15-minute repeat limit.
        lastAlertAt = nil
        return id
    }

    mutating func evaluate(
        _ reading: Reading?, low: Decimal, high: Decimal,
        lowEnabled: Bool, highEnabled: Bool, now: Date, globalSnooze: Date,
        urgentLow: Decimal = 40, urgentHigh: Decimal = 400,
        urgentLowEnabled: Bool = false, urgentHighEnabled: Bool = false
    ) -> Decision {
        var decision = Decision()
        func valid(_ reading: Reading) -> Bool {
            reading.mgdL > 0 && reading.date <= now && now.timeIntervalSince(reading.date) <= Self.freshness
        }
        guard let reading = reading, valid(reading), low < high else {
            decision.cancelled = activeID
            activeID = nil
            return decision
        }
        // A deleted latest reading can reveal an older row. Never re-arm from it.
        if let lastSeen = lastSeen, reading.date < lastSeen {
            decision.cancelled = activeID
            activeID = nil
            return decision
        }
        lastSeen = reading.date
        // Choose severity before snooze: a snoozed urgent alarm must not fall back to a normal alarm.
        let nextKind: Kind?
        if urgentLowEnabled && reading.mgdL <= GlucoseAlarmConfiguration.urgentLowThreshold(urgentLow, low: low) {
            nextKind = .urgentLow
        } else if urgentHighEnabled && reading.mgdL >= GlucoseAlarmConfiguration.urgentHighThreshold(urgentHigh, high: high) {
            nextKind = .urgentHigh
        } else {
            nextKind = reading.mgdL <= low ? .low : (reading.mgdL >= high ? .high : nil)
        }
        let enabled: Bool
        switch nextKind {
        case .low: enabled = lowEnabled
        case .high: enabled = highEnabled
        case .urgentLow: enabled = urgentLowEnabled
        case .urgentHigh: enabled = urgentHighEnabled
        case nil: enabled = false
        }
        let changed = nextKind != kind
        let effectiveSnooze = max(snoozeDeadline(for: nextKind), globalSnooze)
        // A different alarm type must not inherit the previous type's repeat limit.
        if changed { lastAlertAt = nil }
        if changed || !enabled || effectiveSnooze > now {
            decision.cancelled = activeID
            activeID = nil
        }
        kind = nextKind
        guard enabled, let kind = nextKind, effectiveSnooze <= now else { return decision }
        // Backfill, duplicate callbacks and relaunches cannot repeat a reading's alarm.
        guard lastAlertReading.map({ reading.date > $0 }) ?? true else { return decision }
        guard changed || lastAlertAt.map({ now.timeIntervalSince($0) >= Self.repeatInterval }) ?? true else {
            return decision
        }
        if let id = activeID { decision.cancelled = id }
        let id = UUID()
        activeID = id
        lastAlertAt = now
        lastAlertReading = reading.date
        decision.issued = Event(id: id, kind: kind, reading: reading)
        return decision
    }
}
