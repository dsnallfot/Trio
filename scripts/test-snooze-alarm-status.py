#!/usr/bin/env python3
"""Check snooze presentation against production alarm decisions and owned system IDs."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
directory = root / "Trio/Sources/Services/GlucoseAlarms"
source = "\n".join(
    (directory / filename).read_text()
    for filename in ["GlucoseAlarmState.swift", "GlucoseAlarmConfiguration.swift"]
)
source += r'''
let now = Date(timeIntervalSince1970: 1_000_000)
func evaluated(_ value: Decimal, urgent: Bool = true, enabled: Bool = true,
               snooze: Date = .distantPast) -> GlucoseAlarmState {
    var state = GlucoseAlarmState()
    _ = state.evaluate(
        .init(date: now, mgdL: value), low: 70, high: 180,
        lowEnabled: enabled, highEnabled: enabled, now: now, globalSnooze: snooze,
        urgentLow: 40, urgentHigh: 300,
        urgentLowEnabled: urgent && enabled, urgentHighEnabled: urgent && enabled
    )
    return state
}
precondition(evaluated(35).activeKind == .urgentLow)
precondition(evaluated(310).activeKind == .urgentHigh)
precondition(evaluated(60).activeKind == .low)
precondition(evaluated(200).activeKind == .high)
precondition(evaluated(100).activeKind == nil)
precondition(evaluated(35, urgent: false).activeKind == .low)
precondition(evaluated(310, urgent: false).activeKind == .high)
precondition(evaluated(35, enabled: false).activeKind == nil)
precondition(evaluated(310, snooze: now.addingTimeInterval(60)).activeKind == nil)

var glucose = evaluated(35)
_ = glucose.acknowledge(id: glucose.activeID!, now: now)
precondition(glucose.activeKind == nil, "Acknowledged glucose alarms are no longer active")
let localPause = glucose.snoozeDeadline(for: .urgentLow)
let localStatus = glucose.presentation(now: now, globalSnooze: .distantPast, enabled: true)
precondition(localStatus?.kind == .urgentLow && localStatus?.snoozeUntil == localPause,
             "An acknowledged current condition remains visible with its individual snooze")
let laterGlobalPause = localPause.addingTimeInterval(20 * 60)
precondition(glucose.presentation(now: now, globalSnooze: laterGlobalPause, enabled: true)?.snoozeUntil == laterGlobalPause)
precondition(glucose.presentation(now: now, globalSnooze: now.addingTimeInterval(60), enabled: true)?.snoozeUntil == localPause,
             "A shorter shared pause must not shorten an individual snooze")
precondition(glucose.presentation(now: now, globalSnooze: .distantPast, enabled: false) == nil)
precondition(glucose.presentation(now: now.addingTimeInterval(GlucoseAlarmState.freshness + 1),
                                 globalSnooze: laterGlobalPause, enabled: true) == nil)
_ = glucose.evaluate(.init(date: now.addingTimeInterval(1), mgdL: 100), low: 70, high: 180,
                     lowEnabled: true, highEnabled: true, now: now.addingTimeInterval(1),
                     globalSnooze: laterGlobalPause)
precondition(glucose.presentation(now: now.addingTimeInterval(1), globalSnooze: laterGlobalPause, enabled: true) == nil,
             "A recovered glucose condition disappears even while its snooze remains in force")
var expired = evaluated(310)
_ = expired.evaluate(.init(date: now, mgdL: 310), low: 70, high: 180,
                     lowEnabled: true, highEnabled: true,
                     now: now.addingTimeInterval(GlucoseAlarmState.freshness + 1),
                     globalSnooze: .distantPast)
precondition(expired.activeKind == nil, "Expired glucose must not leave an active alarm row")

var readings = MissingDataAlarmState()
var loop = MissingDataAlarmState()
readings.slots = [.init(anchor: now, minutes: 15, tone: .urgentLow, scheduled: true),
                  .init(anchor: now, minutes: 30, tone: .urgentLow, scheduled: true)]
loop.slots = [.init(anchor: now, minutes: 20, tone: .urgentLow, scheduled: true)]
let readingID = readings.slots[0].id
let loopID = loop.slots[0].id
precondition(!readings.hasActiveAlarm(in: []), "A future scheduled alarm must not be displayed")
precondition(!readings.hasActiveAlarm(in: [UUID()]), "Unrelated/test alarms must not be displayed")
for hasGlucose in [false, true] {
    for hasReadings in [false, true] {
        for hasLoop in [false, true] {
            let ids = Set((hasReadings ? [readingID] : []) + (hasLoop ? [loopID] : []))
            let glucose = evaluated(hasGlucose ? 310 : 100)
            precondition((glucose.activeKind != nil) == hasGlucose)
            precondition(readings.hasActiveAlarm(in: ids) == hasReadings)
            precondition(loop.hasActiveAlarm(in: ids) == hasLoop)
        }
    }
}
_ = readings.acknowledge(readingID)
precondition(!readings.hasActiveAlarm(in: [readingID]))
precondition(loop.hasActiveAlarm(in: [loopID]), "Acknowledging readings must not hide the loop alarm")
precondition(readings.hasActiveAlarm(in: [readings.slots[1].id]),
             "A later outage deadline can trigger independently")
readings.slots = []
precondition(!readings.hasActiveAlarm(in: [readingID]), "Resolved/replaced outages must disappear")

var outage = MissingDataAlarmState()
let config = MissingDataAlarmConfiguration(enabled: true, first: 15, second: 30)
_ = outage.reconcile(latest: now, config: config, now: now)
for index in outage.slots.indices { outage.slots[index].scheduled = true }
let originalIDs = Set(outage.slots.map(\.id))
let pauseEnd = now.addingTimeInterval(60 * 60)
precondition(!outage.hasCurrentAlarm(in: [], now: now, snoozeUntil: pauseEnd),
             "A future outage is not yet a current condition")
precondition(outage.hasCurrentAlarm(in: [], now: now.addingTimeInterval(16 * 60), snoozeUntil: pauseEnd),
             "An overdue condition remains visible while its alarm is deferred by shared snooze")
precondition(!outage.hasCurrentAlarm(in: [], now: now.addingTimeInterval(16 * 60), snoozeUntil: .distantPast))
precondition(Set(outage.rescheduleForSnooze()) == originalIDs)
precondition(outage.slots.allSatisfy { !$0.scheduled })
precondition(outage.slots.allSatisfy { outage.deliveryDate(for: $0, snoozeUntil: pauseEnd) == pauseEnd })
precondition(outage.supersededOverdue(outage.slots[0], now: now, snoozeUntil: pauseEnd))
precondition(!outage.supersededOverdue(outage.slots[1], now: now, snoozeUntil: pauseEnd),
             "One outstanding alarm must remain at the end of a long shared snooze")
let shortPause = now.addingTimeInterval(20 * 60)
precondition(outage.deliveryDate(for: outage.slots[0], snoozeUntil: shortPause) == shortPause)
precondition(outage.deliveryDate(for: outage.slots[1], snoozeUntil: shortPause) == now.addingTimeInterval(30 * 60))
precondition(!outage.supersededOverdue(outage.slots[0], now: now, snoozeUntil: shortPause))
for slot in outage.slots {
    precondition(outage.deliveryDate(for: slot, snoozeUntil: .distantPast) == slot.date,
                 "Cancelling shared snooze restores the original deadlines")
}
_ = outage.acknowledge(outage.slots[1].id)
outage.slots[1].scheduled = true
precondition(!outage.rescheduleForSnooze().contains(outage.slots[1].id))
precondition(outage.slots[1].acknowledged && outage.slots[1].scheduled)
let restored = try JSONDecoder().decode(MissingDataAlarmState.self, from: JSONEncoder().encode(outage))
precondition(restored.slots == outage.slots)
_ = outage.reconcile(latest: now.addingTimeInterval(5 * 60), config: config, now: now.addingTimeInterval(5 * 60))
precondition(Set(outage.slots.map(\.id)).isDisjoint(with: originalIDs))
precondition(outage.slots.allSatisfy { outage.deliveryDate(for: $0, snoozeUntil: pauseEnd) == pauseEnd },
             "New readings during snooze must retain the shared pause for future outage deadlines")
for value: Decimal in [35, 60, 200, 310] {
    var paused = evaluated(value)
    _ = paused.acknowledge(id: paused.activeID!, now: now, snoozeMinutes: 30)
    // Also clear pauses belonging to other alarm types and the legacy shared pause.
    paused.snoozeUntil = now.addingTimeInterval(3600)
    paused.lowSnoozeUntil = now.addingTimeInterval(3600)
    paused.highSnoozeUntil = now.addingTimeInterval(3600)
    paused.urgentLowSnoozeUntil = now.addingTimeInterval(3600)
    paused.urgentHighSnoozeUntil = now.addingTimeInterval(3600)
    paused.cancelSnoozes(now: now, globalSnooze: now.addingTimeInterval(7200))
    for kind: GlucoseAlarmState.Kind in [.low, .high, .urgentLow, .urgentHigh] {
        precondition(paused.snoozeDeadline(for: kind) <= now)
    }
    func evaluateAgain(_ state: inout GlucoseAlarmState, date: Date, at time: Date = now,
                       enabled: Bool = true) -> GlucoseAlarmState.Decision {
        state.evaluate(.init(date: date, mgdL: value), low: 70, high: 180,
                       lowEnabled: enabled, highEnabled: enabled, now: time, globalSnooze: .distantPast,
                       urgentLow: 40, urgentHigh: 300,
                       urgentLowEnabled: enabled, urgentHighEnabled: enabled)
    }
    var backfilled = paused
    precondition(evaluateAgain(&backfilled, date: now.addingTimeInterval(-60)).issued == nil)
    var stale = paused
    precondition(evaluateAgain(&stale, date: now, at: now.addingTimeInterval(GlucoseAlarmState.freshness + 1)).issued == nil)
    var disabled = paused
    precondition(evaluateAgain(&disabled, date: now, enabled: false).issued == nil)
    // Persist/relaunch must retain the explicit one-time permission to re-arm.
    paused = try JSONDecoder().decode(GlucoseAlarmState.self, from: JSONEncoder().encode(paused))
    precondition(evaluateAgain(&paused, date: now).issued != nil,
                 "Cancelling snooze must permit the current fresh reading to trigger again")
    precondition(evaluateAgain(&paused, date: now).issued == nil,
                 "Subsequent duplicate callbacks must still be suppressed")
    paused.cancelSnoozes(now: now, globalSnooze: .distantPast)
    precondition(evaluateAgain(&paused, date: now).issued == nil,
                 "Repeated cancellation without a pause must not create duplicate alarms")
}
print("PASS: severity, concurrent alarms, shared/individual snooze, cancellation re-arms once, freshness, recovery, relaunch")
'''
with tempfile.TemporaryDirectory(prefix="trio-snooze-status-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(source)
    subprocess.run(
        ["swift", "-module-cache-path", "/tmp/trio-swift-cache", str(path)],
        check=True,
        timeout=60,
    )
