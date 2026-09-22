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
    // Allow the next five-minute CGM reading despite small delivery-time variations.
    // A newer reading is still required; this is not a repeating timer on old data.
    static let repeatInterval: TimeInterval = 4.5 * 60
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
        // Explicit acknowledgement starts the selected snooze, independently of the repeat guard.
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

/// Persistent deadlines: duplicate callbacks, deletion and relaunch never move an outage forward.
struct MissingDataAlarmState: Codable {
    struct Slot: Codable, Equatable {
        var id = UUID()
        let anchor: Date
        let minutes: Int
        let tone: GlucoseAlarmTone
        var scheduled = false
        var acknowledged = false
        var date: Date { anchor.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    var latest: Date?
    var monitoringSince: Date?
    var slots: [Slot] = []

    mutating func reconcile(latest candidate: Date?, config: MissingDataAlarmConfiguration, now: Date) -> [UUID] {
        if let candidate, candidate <= now, candidate > .distantPast,
           latest.map({ candidate > $0 }) ?? true { latest = candidate }
        guard config.enabled else {
            let removed = slots.map(\.id)
            slots = []
            monitoringSince = nil
            return removed
        }
        if monitoringSince == nil { monitoringSince = now }
        let anchor = latest ?? monitoringSince!
        let previous = slots
        slots = config.intervals.map { minutes in
            previous.first { $0.anchor == anchor && $0.minutes == minutes && $0.tone == config.tone }
                ?? Slot(anchor: anchor, minutes: minutes, tone: config.tone)
        }
        return previous.filter { old in !slots.contains { $0.id == old.id } }.map(\.id)
    }

    func supersededOverdue(_ slot: Slot, now: Date) -> Bool {
        slot.date <= now && slots.contains { $0.date > slot.date && $0.date <= now }
    }

    mutating func acknowledge(_ id: UUID) -> Bool {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return false }
        slots[index].acknowledged = true
        return true
    }
}
