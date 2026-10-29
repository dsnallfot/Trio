import Foundation
import Testing
@testable import Trio

@Suite("Local engine integration contracts") struct LocalOrefIntegrationTests {
    #if os(iOS)
        @Test("Older installations and malformed engine settings default to JavaScript") func settingsMigration() throws {
            for input in ["{}", #"{"useSwiftOref":null}"#, #"{"useSwiftOref":"true"}"#] {
                let settings = try JSONCoding.decoder.decode(TrioSettings.self, from: Data(input.utf8))
                #expect(!settings.useSwiftOref)
            }
            var settings = TrioSettings()
            settings.useSwiftOref = true
            #expect(try JSONCoding.decoder.decode(TrioSettings.self, from: JSONCoding.encoder.encode(settings)).useSwiftOref)
        }
    #endif

    @Test("Nightscout SMB marker starts conclusion only when SMB is disabled", arguments: [
        true,
        false
    ]) func smbReasonMarker(smbIsEnabled: Bool) {
        let meal = ComputedCarbs(
            carbs: 0, mealCOB: 0, currentDeviation: 0, maxDeviation: 0, minDeviation: 0,
            slopeFromMaxDeviation: 0, slopeFromMinDeviation: 0, allDeviations: [], lastCarbTime: 0
        )
        let forecast = ForecastResult(
            iob: [120], cob: nil, uam: nil, zt: [120], internalCob: [120], internalUam: [120],
            eventualGlucose: 120, minForecastedGlucose: 120, minIOBForecastedGlucose: 120,
            minGuardGlucose: 120, carbImpact: 0, remainingCarbImpactPeak: 0, adjustedCarbRatio: 10
        )
        let inputs = DosingEngine.prepareDosingInputs(
            profile: Profile(), mealData: meal, forecast: forecast, naiveEventualGlucose: 120,
            threshold: 65, glucoseImpact: 0, deviation: 0, currentBasal: 1, overrideFactor: 1,
            adjustedSensitivity: 50, isfReason: "ISF", tddReason: ", TDD: 20", targetLog: "100",
            smbIsEnabled: smbIsEnabled
        )
        if smbIsEnabled {
            #expect(inputs.reason.hasSuffix(", TDD: 20; "))
            #expect(!inputs.reason.contains("SMB INAKTIVERADE!"))
        } else {
            #expect(inputs.reason.hasSuffix(", TDD: 20; SMB INAKTIVERADE!, "))
        }
    }

    @Test("Core Data glucose format and manual readings decode without changing stored JSON") func glucoseInput() throws {
        let rows = #"[{"id":"manual","date":1760000000000,"dateString":"2025-10-09T08:53:20Z","glucose":123,"type":"sgv"}]"#
        let values = try JSONBridge.glucose(from: rows)
        #expect(values.first?._id == "manual")
        #expect(values.first?.glucose == 123)
        #expect(values.first?.sgv == 123)
    }

    @Test("TDD retains pump increments and incomplete-history eligibility") func insulinHistory() throws {
        let clock = Date(timeIntervalSince1970: 1_760_000_000)
        let basal = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
        let history = [
            PumpHistoryEvent(id: "d", type: .tempBasalDuration, timestamp: clock.addingTimeInterval(-900), durationMin: 30),
            PumpHistoryEvent(id: "t", type: .tempBasal, timestamp: clock.addingTimeInterval(-900), rate: 1),
            PumpHistoryEvent(id: "b", type: .bolus, timestamp: clock.addingTimeInterval(-3600), amount: 2)
        ]
        let result = try LocalInsulinHistory.calculate(history: history, basal: basal, increment: 0.1, clock: clock)
        #expect(result.insulin.temp_basal == Decimal(string: "0.2"))
        #expect(result.insulin.bolus == 2)
        #expect(result.insulin.TDD == Decimal(string: "2.2"))
        #expect(!result.allowsDynamicISF)
        let empty = try LocalInsulinHistory.calculate(history: [], basal: basal, increment: 0.05, clock: clock)
        #expect(empty.total == 0)
        #expect(!empty.allowsDynamicISF)
    }

    @Test("Overlapping calculations hold engine snapshot across suspension") func serialCalculations() async {
        let gate = OrefCalculationGate()
        let counter = ConcurrentCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 30 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    await Task.yield()
                    await counter.leave()
                    gate.release()
                }
            }
        }
        #expect(await counter.maximum == 1)
        #expect(await counter.completed == 30)
    }
}

private actor ConcurrentCounter {
    var active = 0
    var maximum = 0
    var completed = 0
    func enter() { active += 1
        maximum = max(maximum, active) }
    func leave() { active -= 1
        completed += 1 }
}
