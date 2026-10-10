#!/usr/bin/env python3
"""Exercise production alarm filtering/persistence and expiration caching with isolated fakes."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def method(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private ", "")

alarm = (ROOT / "Trio/Sources/Services/GlucoseAlarms/TrioAlertManager.swift").read_text()
build = (ROOT / "Trio/Sources/Helpers/BuildDetails.swift").read_text()
state_dir = ROOT / "Trio/Sources/Services/GlucoseAlarms"
source = "\n".join((state_dir / f).read_text() for f in ["GlucoseAlarmState.swift", "GlucoseAlarmConfiguration.swift"])
source += r'''
enum GlucoseUnits { case mgdL, mmolL }
struct SettingsValue { var lowGlucose: Decimal = 72; var highGlucose: Decimal = 270; var units = GlucoseUnits.mgdL }
final class Settings { var settings = SettingsValue() }
final class Defaults {
    var values: [String: Any] = [:]
    var writes = 0
    func getValue<T>(_ type: T.Type, forKey key: String) -> T? { values[key] as? T }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    func set(_ value: Any, forKey key: String) { values[key] = value; writes += 1 }
}
final class AlarmHarness {
    static let stateKey = "state", alarmIDsKey = "ids"
    let defaults = Defaults()
    let settings = Settings()
    var state = GlucoseAlarmState()
    var systemIDs: Set<UUID> = []
    var evaluations = 0
    func evaluate() { evaluations += 1 }
'''
start = alarm.index("    private var observedSnooze")
end = alarm.index("    @Published private(set) var testAlarmID")
source += alarm[start:end].replace("private ", "").replace("UserDefaults.standard", "defaults")
source += method(alarm, "    private func persist()") .replace("UserDefaults.standard", "defaults")
source += "\n}\n"
source += r'''
final class ExpirationHarness {
    let expirationLock = NSLock()
    var expirationLoaded = false
    var cachedExpiration: Date?
    var loads = 0
    var result: Date?
    init(_ result: Date?) { self.result = result }
    func loadExpirationDate() -> Date? { loads += 1; return result }
'''
source += method(build, "    func calculateExpirationDate()") + "\n}\n"
source += r'''
let alarm = AlarmHarness()
alarm.observedSnooze = alarm.globalSnooze
alarm.observedSettings = alarm.evaluationSettings
for _ in 0..<10000 { alarm.snoozeDidChange(); alarm.alarmSettingsDidChange() }
precondition(alarm.evaluations == 0, "Unrelated events must not evaluate alarms")
alarm.defaults.set(Date(timeIntervalSince1970: 1000), forKey: "UserNotificationsManager.snoozeUntilDate")
alarm.snoozeDidChange()
precondition(alarm.evaluations == 1, "Snooze change must evaluate immediately")
for _ in 0..<10000 { alarm.snoozeDidChange() }
precondition(alarm.evaluations == 1)
alarm.defaults.values.removeValue(forKey: "UserNotificationsManager.snoozeUntilDate")
alarm.snoozeDidChange()
precondition(alarm.evaluations == 2, "Removing snooze must evaluate")
alarm.settings.settings.lowGlucose = 80
alarm.alarmSettingsDidChange()
alarm.settings.settings.highGlucose = 250
alarm.alarmSettingsDidChange()
alarm.settings.settings.units = .mmolL
alarm.alarmSettingsDidChange()
precondition(alarm.evaluations == 5)
alarm.state.lastSeen = Date(timeIntervalSince1970: 1000)
alarm.persist()
let writes = alarm.defaults.writes
for _ in 0..<1000 { alarm.persist() }
precondition(alarm.defaults.writes == writes, "Unchanged state must not write defaults")
alarm.state.lowSnoozeUntil = Date(timeIntervalSince1970: 2000)
alarm.persist()
precondition(alarm.defaults.writes == writes + 1)
alarm.systemIDs.insert(UUID())
alarm.persist()
precondition(alarm.defaults.writes == writes + 2)
for result in [nil, Date(timeIntervalSince1970: 3000)] as [Date?] {
    let cache = ExpirationHarness(result)
    for _ in 0..<10000 { precondition(cache.calculateExpirationDate() == result) }
    precondition(cache.loads == 1, "Cache must include nil")
}
let nextBuild = ExpirationHarness(Date(timeIntervalSince1970: 4000))
precondition(nextBuild.calculateExpirationDate() == nextBuild.result && nextBuild.loads == 1)
print("PASS: unrelated event storms, snooze/threshold/unit changes, semantic persistence, expiration cache including nil/new instance")
'''
with tempfile.TemporaryDirectory(prefix="trio-alarm-cpu-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(source)
    subprocess.run(["swift", "-module-cache-path", "/tmp/trio-swift-cache", str(path)], check=True)
