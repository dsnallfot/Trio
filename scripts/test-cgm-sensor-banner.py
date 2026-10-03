#!/usr/bin/env python3
"""Exercise PluginSource's production error mapping/throttling and recovery branches.

Uses small Swift doubles for the host and uploader; no BLE or Nightscout traffic.
Does not render SwiftUI or emulate app persistence.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/APS/CGM/PluginSource.swift').read_text()
start = source.index('        if case let .error(err) = readingResult {')
errors = source[start:source.index('        if glucoseManager?.glucoseSource == nil', start)]
start = source.index('            // Old backfill or display-only readings')
recovery = source[start:source.index('            if values.isNotEmpty', start)]

harness = r'''
import Foundation

enum SensorReadingError: Error { case invalidG7GlucoseResponse }
struct AlgorithmError: Error, CustomStringConvertible {
    let token: String
    var description: String { "unreliableState(\(token))" }
}
class G7CGMManager {}
struct Reading { let date: Date; let isDisplayOnly: Bool }
enum CGMReadingResult { case error(Error), newData([Reading]), noData }
actor Uploader {
    var notes: [String] = []
    func uploadNoteTreatment(note: String) { notes.append(note) }
    func count() -> Int { notes.count }
}
final class Harness {
    var cgmManager: AnyObject? = G7CGMManager()
    let nightscoutManager: Uploader? = Uploader()
    var lastUploadedNote: (message: String, date: Date)?
    let noteThrottleInterval: TimeInterval = 300
    var reportedSensorIssueNotes: Set<String> = []
    var banner: String?
    func publishSensorIssue(_ message: String?) { banner = message }
    func read(_ readingResult: CGMReadingResult) -> Result<[Reading], Error> {
''' + errors + '''
        if case let .newData(values) = readingResult {
''' + recovery + '''
        }
        return .success([])
    }
}
''' + r'''
@main struct Tests {
    static func settle() async { try? await Task.sleep(nanoseconds: 30_000_000) }
    static func main() async {
        let h = Harness()
        _ = h.read(.error(AlgorithmError(token: "temporarySensorIssue")))
        assert(h.banner == "⚠️ Dexcom G7: Tillfälligt sensorfel!")
        await settle()
        let initialCount = await h.nightscoutManager!.count()
        assert(initialCount == 1)
        h.lastUploadedNote = (h.banner!, Date(timeIntervalSinceNow: -3600))
        _ = h.read(.error(AlgorithmError(token: "temporarySensorIssue")))
        await settle()
        let repeatedCount = await h.nightscoutManager!.count()
        assert(repeatedCount == 1 && h.banner != nil)

        _ = h.read(.error(SensorReadingError.invalidG7GlucoseResponse))
        let parserBanner = h.banner
        assert(parserBanner?.contains("Kunde inte tolka") == true)
        await settle()
        let parserCount = await h.nightscoutManager!.count()
        assert(parserCount == 2)
        h.lastUploadedNote = (parserBanner!, Date(timeIntervalSinceNow: -3600))
        _ = h.read(.error(SensorReadingError.invalidG7GlucoseResponse))
        _ = h.read(.error(AlgorithmError(token: "temporarySensorIssue")))
        _ = h.read(.error(SensorReadingError.invalidG7GlucoseResponse))
        _ = h.read(.noData)
        _ = h.read(.newData([]))
        _ = h.read(.newData([Reading(date: Date(timeIntervalSinceNow: -600), isDisplayOnly: false)]))
        _ = h.read(.newData([Reading(date: Date(), isDisplayOnly: true)]))
        _ = h.read(.error(AlgorithmError(token: "ok")))
        await settle()
        let outageCount = await h.nightscoutManager!.count()
        assert(h.banner == parserBanner && outageCount == 2)

        _ = h.read(.newData([Reading(date: Date(), isDisplayOnly: false)]))
        assert(h.banner == nil && h.reportedSensorIssueNotes.isEmpty)
        await settle()
        let recoveredNotes = await h.nightscoutManager!.notes
        assert(recoveredNotes.count == 3)
        assert(recoveredNotes.last == "✅ Dexcom G7: Sensor återställd!")
        _ = h.read(.newData([Reading(date: Date(), isDisplayOnly: false)]))
        await settle()
        let healthyCount = await h.nightscoutManager!.count()
        assert(healthyCount == 3)
        _ = h.read(.error(SensorReadingError.invalidG7GlucoseResponse))
        await settle()
        let nextOutageCount = await h.nightscoutManager!.count()
        assert(h.banner == parserBanner && nextOutageCount == 4)

        for token in ["stopped", "warmup", "expired", "sensorFailed", "unknown"] {
            _ = h.read(.error(AlgorithmError(token: token)))
            assert(h.banner != nil)
        }
        let other = Harness()
        _ = other.read(.newData([Reading(date: Date(), isDisplayOnly: false)]))
        await settle()
        let startupCount = await other.nightscoutManager!.count()
        assert(startupCount == 0)
        other.cgmManager = NSObject()
        _ = other.read(.error(AlgorithmError(token: "temporarySensorIssue")))
        assert(other.banner == nil)
        print("PASS: error banners, note throttling, recovery, recurrence and non-G7 isolation")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='trio-cgm-banner-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(harness)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path',
                    str(path / 'cache'), str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
