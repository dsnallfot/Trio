import Foundation
import Testing
@testable import Trio

@Suite("Finalized and scheduled basal history") struct BasalHistoryRegressionTests {
    let start = Date(timeIntervalSince1970: 1_793_318_400) // fixed clock
    var profile: [BasalProfileEntry] { [.init(start: "00:00:00", minutes: 0, rate: Decimal(string: "0.35")!)] }
    func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }
    func temp(_ id: String, _ from: Double, _ to: Double, _ rate: Decimal, delivered: Decimal? = nil) -> PumpHistoryEvent {
        .init(id: id, type: .tempBasal, timestamp: at(from), rate: rate, endDate: at(to), deliveredUnits: delivered)
    }

    func marker(_ type: EventType, _ hours: Double) -> PumpHistoryEvent {
        .init(id: "\(type)-\(hours)", type: type, timestamp: at(hours))
    }

    func result(_ events: [PumpHistoryEvent], now: Double) throws -> LocalInsulinHistory.Result {
        try LocalInsulinHistory.calculate(history: events, basal: profile, increment: Decimal(string: "0.05")!, clock: at(now))
    }

    @Test func twelveHourBasalTestCountsScheduledDelivery() throws {
        let value = try result([temp("zero", 0, 0.5, 0)], now: 12.5)
        #expect(value.insulin.scheduled_basal == Decimal(string: "4.2")!)
        #expect(value.total == Decimal(string: "4.2")!)
        #expect(value.hours == 12.5)
    }

    @Test func earlyCancellationUsesExactEndAndFinalDelivery() throws {
        let value = try result([temp("cancelled", 0, 0.25, 1, delivered: Decimal(string: "0.2")!)], now: 1.25)
        #expect(value.insulin.temp_basal == Decimal(string: "0.2")!)
        #expect(value.insulin.scheduled_basal == Decimal(string: "0.35")!)
        #expect(value.total == Decimal(string: "0.55")!)
    }

    @Test func noDoubleCountBetweenTemps() throws {
        let events = [temp("first", 0, 0.5, 1), temp("second", 1.5, 2, 2)]
        let value = try result(events, now: 2)
        #expect(value.insulin.temp_basal == Decimal(string: "1.5")!)
        #expect(value.insulin.scheduled_basal == Decimal(string: "0.35")!)
        #expect(try result(events.reversed(), now: 2).total == value.total)
    }

    @Test func suspendEndsTempAndResumeRestoresSchedule() throws {
        let events = [temp("t", 0, 2, 1), marker(.pumpSuspend, 0.5), marker(.pumpResume, 1.5)]
        let value = try result(events, now: 2.5)
        #expect(value.insulin.temp_basal == Decimal(string: "0.5")!)
        #expect(value.insulin.scheduled_basal == Decimal(string: "0.35")!)
    }

    @Test func openSuspensionDoesNotInventBasal() throws {
        let value = try result([marker(.scheduledBasal, 0), marker(.pumpSuspend, 1)], now: 13)
        #expect(value.total == Decimal(string: "0.35")!)
    }

    @Test func firstResumeMeansInitiallySuspended() throws {
        let value = try result([marker(.scheduledBasal, 0), marker(.pumpResume, 12)], now: 13)
        #expect(value.total == Decimal(string: "0.35")!)
    }

    @Test func scheduleProgrammingDoesNotCancelRunningTemp() throws {
        let value = try result([temp("t", 0, 2, 1), marker(.scheduledBasal, 1)], now: 3)
        #expect(value.insulin.temp_basal == 2)
        #expect(value.insulin.scheduled_basal == Decimal(string: "0.35")!)
    }

    @Test func zeroDurationCancellationReturnsToSchedule() throws {
        let value = try result([temp("t", 0, 2, 1), temp("cancel", 0.5, 0.5, 0)], now: 1.5)
        #expect(value.insulin.temp_basal == Decimal(string: "0.5")!)
        #expect(value.insulin.scheduled_basal == Decimal(string: "0.35")!)
    }

    @Test func clipsToLast24HoursAndIgnoresFutureBolus() throws {
        let events = [marker(.scheduledBasal, 0), PumpHistoryEvent(id: "future", type: .bolus, timestamp: at(49), amount: 10)]
        let value = try result(events, now: 48)
        #expect(value.total == Decimal(string: "8.4")!)
        #expect(value.hours == 24)
    }

    @Test func scheduleChangesSplitAndIntegrateExactly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: start)
        let segments = BasalDeliveryTimeline.segments(
            events: [.init(start: day, end: day, kind: .anchor)],
            profile: [.init(start: "00:00:00", minutes: 0, rate: 1), .init(start: "12:00:00", minutes: 720, rate: 2)],
            now: day.addingTimeInterval(24 * 3600), calendar: calendar
        )
        #expect(segments.count == 2)
        #expect(segments.reduce(Decimal.zero) { $0 + $1.units } == 36)
    }

    @Test func dstDayUsesWallClockSchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let segments = BasalDeliveryTimeline.segments(
            events: [.init(start: day, end: day, kind: .anchor)],
            profile: [.init(start: "00:00:00", minutes: 0, rate: 1)],
            now: end,
            calendar: calendar
        )
        #expect(segments.reduce(Decimal.zero) { $0 + $1.units } == 23)
    }

    @Test func emptyHistoryDoesNotInvent24Hours() throws {
        let value = try result([], now: 12)
        #expect(value.total == 0)
        #expect(value.hours == 0)
    }

    @Test func bolusDoesNotFragmentScheduledPulseRounding() throws {
        let events = [marker(.scheduledBasal, 0)] + (1 ... 11).map {
            PumpHistoryEvent(id: "b\($0)", type: .bolus, timestamp: at(Double($0) / 12), amount: 0)
        }
        #expect(try result(events, now: 1).insulin.scheduled_basal == Decimal(string: "0.35")!)
    }

    @Test func podReplacementGapIsExcluded() throws {
        let history = [marker(.scheduledBasal, 0), marker(.pumpDetached, 2), marker(.pumpAttached, 8)]
        #expect(try result(history, now: 10).insulin.scheduled_basal == Decimal(string: "1.4")!)
    }
}
