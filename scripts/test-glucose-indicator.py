#!/usr/bin/env python3
"""Exercise production glucose-indicator policy with isolated settings and clock."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
folder = root / 'Trio/Sources/Services/GlucoseAlarms'

def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

source = '\n'.join((folder / f).read_text() for f in ['GlucoseAlarmState.swift', 'GlucoseAlarmConfiguration.swift'])
source += '''
final class Preferences {
    var lowEnabled = true, highEnabled = true, urgentLowEnabled = true, urgentHighEnabled = true
    var lowActivePeriod = AlarmActivePeriod.always, highActivePeriod = AlarmActivePeriod.always
    var urgentLowActivePeriod = AlarmActivePeriod.always, urgentHighActivePeriod = AlarmActivePeriod.always
    var urgentLowThreshold: Decimal = 40, urgentHighThreshold: Decimal = 300
    var dayStartMinutes = 7 * 60, nightStartMinutes = 22 * 60
'''
preferences = (folder / 'GlucoseAlarmPreferences.swift').read_text()
source += method(preferences, '    func isDaytime(') + '\n'
source += method(preferences, '    func isAllowed(') + '\n}\n'
source += '''
struct SettingsValue { var lowGlucose: Decimal = 70; var highGlucose: Decimal = 180 }
final class Settings { var settings = SettingsValue() }
final class Manager {
    var state = GlucoseAlarmState()
    let preferences = Preferences()
    let settings = Settings()
    var globalSnooze = Date.distantPast
'''
source += method((folder / 'TrioAlertManager.swift').read_text(), '    func indicatorSymbol(') + '\n}\n'
source += '''
let manager = Manager()
let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 8))!
let night = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
func symbol(_ value: Decimal, at date: Date = day, age: TimeInterval = 0) -> String? {
    manager.indicatorSymbol(for: .init(date: date.addingTimeInterval(-age), mgdL: value), at: date)
}
for value: Decimal in [35, 60, 200, 310] { precondition(symbol(value) == "bell.fill") }
precondition(symbol(100) == nil)
manager.preferences.highActivePeriod = .night
manager.preferences.urgentHighActivePeriod = .night
precondition(symbol(200) == "bell.slash.fill")
precondition(symbol(310) == "bell.slash.fill")
precondition(symbol(310, at: night) == "bell.fill")
manager.preferences.highEnabled = false
manager.preferences.urgentHighEnabled = false
precondition(symbol(310, at: night) == "bell.slash.fill")
manager.preferences.lowEnabled = false
manager.preferences.urgentLowEnabled = false
precondition(symbol(35) == "bell.slash.fill")
manager.globalSnooze = day.addingTimeInterval(3600)
precondition(symbol(100) == "moon.zzz.fill")
precondition(symbol(35) == "moon.zzz.fill")
manager.globalSnooze = .distantPast
manager.preferences.lowEnabled = true
manager.state.lowSnoozeUntil = day.addingTimeInterval(3600)
precondition(symbol(60) == "moon.zzz.fill")
precondition(symbol(60, at: day.addingTimeInterval(3601)) == "bell.fill")
precondition(symbol(200, age: GlucoseAlarmState.freshness + 1) == nil)
precondition(symbol(200, age: -60) == nil)
// When a normal high alarm is enabled but urgent high is restricted,
// the indicator must match the normal alarm that the engine can actually issue.
manager.preferences.highEnabled = true
manager.preferences.highActivePeriod = .always
manager.preferences.urgentHighEnabled = true
precondition(symbol(310) == "bell.fill")
manager.preferences.dayStartMinutes = 20 * 60
manager.preferences.nightStartMinutes = 6 * 60
manager.preferences.highActivePeriod = .day
manager.preferences.urgentHighActivePeriod = .day
precondition(symbol(310, at: night) == "bell.fill")
precondition(symbol(310) == "bell.slash.fill")
print("PASS: thresholds, enabled/disabled, day/night including midnight, global/local snooze, expiry, stale readings, severity fallback")
'''
with tempfile.TemporaryDirectory(prefix='trio-indicator-') as temporary:
    path = Path(temporary) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', '-module-cache-path', '/tmp/trio-swift-cache', str(path)], check=True, timeout=60)
