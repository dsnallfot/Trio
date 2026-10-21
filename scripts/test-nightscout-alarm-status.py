#!/usr/bin/env python3
"""Exercise production schedule/code generation, using isolated preference values."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
directory = root / 'Trio/Sources/Services/GlucoseAlarms'
preferences = (directory / 'GlucoseAlarmPreferences.swift').read_text()
def method(signature):
    start = preferences.index(signature)
    opening = preferences.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (preferences[end] == '{') - (preferences[end] == '}')
        end += 1
    return preferences[start:end] + '\n'
source = (directory / 'GlucoseAlarmConfiguration.swift').read_text()
source += '''
struct Preferences {
    var dayStartMinutes = 420
    var nightStartMinutes = 1320
    var urgentLowEnabled = true
    var lowEnabled = true
    var highEnabled = true
    var urgentHighEnabled = true
    var urgentLowActivePeriod: AlarmActivePeriod = .always
    var lowActivePeriod: AlarmActivePeriod = .always
    var highActivePeriod: AlarmActivePeriod = .always
    var urgentHighActivePeriod: AlarmActivePeriod = .always
'''
for signature in ['    func isDaytime(', '    func isAllowed(', '    func activeAlarmCodes(']:
    source += method(signature)
source += '''
}
func time(_ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute))!
}
var preferences = Preferences()
precondition(preferences.activeAlarmCodes(at: time(12)) == "AL, L, H, AH")
preferences.highEnabled = false; preferences.urgentHighEnabled = false
precondition(preferences.activeAlarmCodes(at: time(12)) == "AL, L")
preferences.lowEnabled = false; preferences.urgentLowEnabled = false
precondition(preferences.activeAlarmCodes(at: time(12)).isEmpty)
preferences = Preferences()
preferences.urgentLowActivePeriod = .night; preferences.lowActivePeriod = .night
preferences.highActivePeriod = .day; preferences.urgentHighActivePeriod = .day
precondition(preferences.activeAlarmCodes(at: time(6, 59)) == "AL, L")
precondition(preferences.activeAlarmCodes(at: time(7)) == "H, AH")
precondition(preferences.activeAlarmCodes(at: time(21, 59)) == "H, AH")
precondition(preferences.activeAlarmCodes(at: time(22)) == "AL, L")
preferences.dayStartMinutes = 1200; preferences.nightStartMinutes = 360
precondition(preferences.activeAlarmCodes(at: time(23)) == "H, AH")
precondition(preferences.activeAlarmCodes(at: time(6)) == "AL, L")
preferences.nightStartMinutes = 1200
precondition(preferences.activeAlarmCodes(at: time(12)) == "H, AH")
print("PASS: alarm codes, toggles, exact day/night boundaries, midnight schedules and equal boundaries")
'''
with tempfile.TemporaryDirectory(prefix='trio-alarm-status-') as directory:
    path = Path(directory)
    (path / 'test.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(path / 'modules'),
                    str(path / 'test.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
