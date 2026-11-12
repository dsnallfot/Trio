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

    func testMatchingIgnoresIdentityNameAndTimeFormattingButChecksEverySchedule() {
        let original = profile(basal: [.init(start: "00:00", minutes: 0, rate: 0.5)])
        func variant(
            rate: Decimal = 0.5, sensitivity: Decimal = 90, ratio: Decimal = 20,
            low: Decimal = 90, high: Decimal = 100, offset: Int = 0, units: GlucoseUnits = .mgdL
        ) -> SavedTherapyProfile {
            SavedTherapyProfile(
                name: "Annat namn",
                basal: [.init(start: "00:00:00", minutes: offset, rate: rate)],
                sensitivities: .init(
                    units: units, userPreferredUnits: units,
                    sensitivities: [.init(sensitivity: sensitivity, offset: offset, start: "00:00:00")]
                ),
                carbRatios: .init(units: .grams, schedule: [.init(start: "00:00:00", offset: offset, ratio: ratio)]),
                targets: .init(
                    units: units, userPreferredUnits: units,
                    targets: [.init(low: low, high: high, start: "00:00:00", offset: offset)]
                )
            )
        }
        XCTAssertTrue(original.hasSameSettings(as: variant()))
        for changed in [
            variant(rate: 0.6),
            variant(sensitivity: 91),
            variant(ratio: 21),
            variant(low: 91),
            variant(high: 101),
            variant(offset: 30),
            variant(units: .mmolL)
        ]
        {
            XCTAssertFalse(original.hasSameSettings(as: changed))
        }
        XCTAssertFalse(original.hasSameSettings(as: profile(basal: [])))
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
