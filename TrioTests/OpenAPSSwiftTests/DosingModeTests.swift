import Foundation
import Testing
@testable import Trio

@Suite("Local dosing modes") struct DosingModeTests {
    @Test func settingsMigrationAndRoundTrip() throws {
        func decode(_ json: String) throws -> TrioSettings { try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"closedLoop":true}"#).dosingMode == .closed)
        #expect(try decode(#"{"closedLoop":false}"#).dosingMode == .open)
        #expect(try decode(#"{"closedLoop":true,"dosingMode":"unknown"}"#).dosingMode == .open)
        for mode in DosingMode.allCases {
            var settings = TrioSettings()
            settings.dosingMode = mode
            let copy = try JSONDecoder().decode(TrioSettings.self, from: JSONEncoder().encode(settings))
            #expect(copy.dosingMode == mode)
            #expect(copy.closedLoop == (mode == .closed))
            if mode.requiresSwift {
                #expect(copy.useSwiftOref)
                settings.useSwiftOref = false
                #expect(settings.useSwiftOref)
            }
        }
    }

    @Test func lowForecastCanSuspendAboveCurrentThreshold() throws {
        var profile = Profile()
        profile.currentBasal = 0.5
        profile.maxDailyBasal = 0.5
        profile.maxBasal = 3
        let value = try JSONDecoder().decode(Determination.self, from: Data(#"{"reason":""}"#.utf8))
        let outcome = try DosingEngine.lowGlucoseSuspend(
            currentGlucose: 110, minGuardGlucose: 65, iob: 0, minDelta: -2, expectedDelta: -2,
            threshold: 72, overrideFactor: 1, profile: profile, adjustedSensitivity: 40,
            targetGlucose: 100, currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date()),
            determination: value
        )
        #expect(outcome.shouldSetTempBasal)
        #expect(outcome.determination.rate == 0)
    }

    @Test func preferencesAreNotMutated() {
        var original = Preferences()
        original.maxIOB = 7
        original.autosensMin = 0.7
        original.autosensMax = 1.2
        original.useNewFormula = true
        original.sigmoid = true
        original.threshold_setting = 90
        let basal = original.clamped(for: .basalTesting)
        #expect(basal.maxIOB == 0)
        #expect(basal.autosensMin == 1 && basal.autosensMax == 1)
        #expect(!basal.useNewFormula && !basal.sigmoid)
        #expect(basal.threshold_setting == 90)
        #expect(original.maxIOB == 7 && original.useNewFormula)
        #expect(original.clamped(for: .closed) == original)
        #expect(original.clamped(for: .open) == original)
        let lgs = original.clamped(for: .lowGlucoseSuspend)
        #expect(lgs.maxIOB == 0 && lgs.autosensMax == original.autosensMax)
    }

    @Test func hardCeilingAndManualBolusFields() throws {
        let value = try JSONDecoder().decode(
            Determination.self,
            from: Data(
                #"{"reason":"TDD; SMB INAKTIVERADE!, ","units":0.5,"rate":2,"duration":30,"iob":-1,"insulinForManualBolus":1.2}"#
                    .utf8
            )
        )
        let schedule = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.8)]
        for mode in [DosingMode.basalTesting, .lowGlucoseSuspend] {
            let capped = try mode.constrain(value, schedule: schedule, at: Date())
            #expect(capped.rate == 0.8)
            #expect(capped.units == nil)
            #expect(capped.insulinForManualBolus == value.insulinForManualBolus)
            #expect(capped.reason.hasPrefix(value.reason))
            #expect(throws: DosingModeError.self) { try mode.constrain(value, schedule: [], at: Date()) }
            var suspend = value
            suspend.rate = 0
            #expect(try mode.constrain(suspend, schedule: schedule, at: Date()).rate == 0)
        }
        #expect(try DosingMode.closed.constrain(value, schedule: [], at: Date()) == value)
        #expect(try DosingMode.open.constrain(value, schedule: [], at: Date()) == value)
    }

    @Test func pendingActivationCannotSurviveModeChange() throws {
        let policy = AdjustmentActivationPolicy()
        policy.update(.closed)
        let token = policy.token
        #expect(policy.accepts(token))
        policy.beginTransition()
        #expect(!policy.allowsActivation)
        #expect(throws: DosingModeError.self) { try policy.validateActivation() }
        policy.update(.basalTesting)
        policy.endTransition()
        #expect(!policy.allowsActivation)
        policy.update(.closed)
        #expect(policy.allowsActivation)
        #expect(!policy.accepts(token))
        #expect(policy.accepts(policy.token))
    }

    @Test func suspendOnlyIsRuntimeOnly() throws {
        var profile = Profile()
        profile.suspendOnly = true
        let data = try JSONEncoder().encode(profile)
        #expect(!String(decoding: data, as: UTF8.self).contains("suspendOnly"))
        #expect(try JSONDecoder().decode(Profile.self, from: data).suspendOnly == false)
    }
}
