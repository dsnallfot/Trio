import Foundation
import Testing
@testable import Trio

@Suite("Basal readout PR1556") struct BasalDeliveryReadoutTests {
    let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    let profile = [BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.5)]
    @Test func cancelledOrExpiredTempShowsSchedule() {
        let old = BasalDeliveryReadout.Event(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(1800), rate: 2)
        #expect(
            BasalDeliveryReadout
                .resolve(status: .active, events: [old], suspensions: [], profile: profile, now: now) == .scheduled(0.5)
        )
        #expect(
            BasalDeliveryReadout
                .resolve(status: nil, events: [old], suspensions: [], profile: profile, now: old.end) == .scheduled(0.5)
        )
        #expect(
            BasalDeliveryReadout
                .resolve(status: nil, events: [], suspensions: [], profile: profile, now: now) == .scheduled(0.5)
        )
    }

    @Test func suspendedResumedAndManual() {
        let old = BasalDeliveryReadout.Event(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(1800), rate: 2)
        #expect(
            BasalDeliveryReadout
                .resolve(status: nil, events: [old], suspensions: [(now, true)], profile: profile, now: now) == .suspended
        )
        #expect(
            BasalDeliveryReadout
                .resolve(status: nil, events: [old], suspensions: [(now, false)], profile: profile, now: now) == .scheduled(0.5)
        )
        #expect(BasalDeliveryReadout.resolve(
            status: .temp(start: old.start, end: old.end, rate: 2, manual: true),
            events: [],
            suspensions: [],
            profile: profile,
            now: now
        ) == .temp(rate: 2, manual: true))
        #expect(
            BasalDeliveryReadout
                .resolve(status: .suspended, events: [], suspensions: [], profile: profile, now: now) == .suspended
        )
    }

    @Test func newTempAndScheduleBoundaries() {
        let old = BasalDeliveryReadout.Event(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(1800), rate: 2)
        let new = BasalDeliveryReadout.Event(start: now, end: now.addingTimeInterval(600), rate: 0.1)
        #expect(
            BasalDeliveryReadout
                .resolve(status: nil, events: [new, old], suspensions: [], profile: profile, now: now) ==
                .temp(rate: 0.1, manual: false)
        )
        let stepped = profile + [BasalProfileEntry(start: "12:00", minutes: 720, rate: 0.8)]
        #expect(
            BasalDeliveryReadout
                .resolve(status: .active, events: [], suspensions: [], profile: stepped, now: now) == .scheduled(0.8)
        )
        #expect(BasalDeliveryReadout.resolve(status: .active, events: [], suspensions: [], profile: [], now: now) == nil)
    }
}
