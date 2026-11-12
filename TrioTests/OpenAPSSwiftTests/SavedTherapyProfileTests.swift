@testable import Trio
import XCTest

final class SavedTherapyProfileTests: XCTestCase {
    private func profile(basal: [BasalProfileEntry]) -> SavedTherapyProfile {
        SavedTherapyProfile(
            name: "Känsligare period",
            basal: basal,
            sensitivities: InsulinSensitivities(
                units: .mgdL, userPreferredUnits: .mgdL,
                sensitivities: [InsulinSensitivityEntry(sensitivity: 90, offset: 0, start: "00:00")]
            ),
            carbRatios: CarbRatios(units: .grams, schedule: [CarbRatioEntry(start: "00:00", offset: 0, ratio: 20)]),
            targets: BGTargets(
                units: .mgdL, userPreferredUnits: .mgdL,
                targets: [BGTargetEntry(low: 90, high: 100, start: "00:00", offset: 0)]
            )
        )
    }

    func testDailyTotalWeightsEachSegmentIncludingLastSegment() {
        let snapshot = profile(basal: [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.5),
            BasalProfileEntry(start: "06:00", minutes: 360, rate: 1),
            BasalProfileEntry(start: "22:30", minutes: 1350, rate: 0.2)
        ])
        XCTAssertTrue(snapshot.isValid)
        XCTAssertEqual(snapshot.totalBasal, Decimal(string: "19.8"))
    }

    func testRejectsEmptyMissingMidnightDuplicateUnorderedAndNegativeBasal() {
        let entry = { (minute: Int, rate: Decimal) in
            BasalProfileEntry(start: "00:00", minutes: minute, rate: rate)
        }
        for basal in [
            [],
            [entry(60, 1)],
            [entry(0, 1), entry(0, 2)],
            [entry(0, 1), entry(120, 1), entry(60, 1)],
            [entry(0, -1)],
            [entry(0, 1), entry(1440, 1)]
        ] {
            XCTAssertFalse(profile(basal: basal).isValid)
        }
        XCTAssertTrue(profile(basal: [entry(0, 0)]).isValid)
    }

    func testSnapshotRoundTripPreservesIdentitySchedulesAndTargetRange() throws {
        let snapshot = profile(basal: [BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.125)])
        let decoded = try JSONCoding.decoder.decode(
            SavedTherapyProfile.self, from: JSONCoding.encoder.encode(snapshot)
        )
        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.name, snapshot.name)
        XCTAssertEqual(decoded.basal, snapshot.basal)
        XCTAssertEqual(decoded.sensitivities.sensitivities.first?.sensitivity, 90)
        XCTAssertEqual(decoded.carbRatios.schedule.first?.ratio, 20)
        XCTAssertEqual(decoded.targets.targets.first?.low, 90)
        XCTAssertEqual(decoded.targets.targets.first?.high, 100)
        XCTAssertTrue(decoded.isValid)
    }
}
