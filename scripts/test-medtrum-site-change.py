#!/usr/bin/env python3
"""Exercise Trio's production Medtrum date bridge with fresh and restored patch state."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/APS/DeviceDataManager.swift').read_text()
start = source.index('    private func updateMedtrumPatchDates(')
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end].replace('private func', 'func')
fixture = r'''
import Foundation

enum OpenAPS { enum Monitor { static let podAge = "monitor/pod-age.json" } }
final class Store {
    var dates: [String: Date] = [:]
    func save(_ date: Date, as key: String) { dates[key] = date }
}
final class DatePublisher {
    var value: Date?
    func send(_ date: Date?) { value = date }
}
struct MedtrumPumpManager {
    struct State {
        enum Mode { case `default`, extended }
        var patchActivatedAt: Date?
        var patchGracePeriodFrom: Date?
        var expiryMode: Mode
    }
    var state: State
}
final class Bridge {
    let storage: Store
    let pumpExpiresAtDate = DatePublisher()
    let pumpActivatedAtDate = DatePublisher()
    init(_ storage: Store) { self.storage = storage }
    METHOD
}
let store = Store()
let bridge = Bridge(store)
let start = ISO8601DateFormatter().date(from: "2026-10-08T19:25:00+02:00")!
let expiry = start.addingTimeInterval(3 * 24 * 3600)
var pump = MedtrumPumpManager(state: .init(
    patchActivatedAt: start, patchGracePeriodFrom: expiry, expiryMode: .default))
// First activation replaces the previously saved Omnipod date.
store.dates[OpenAPS.Monitor.podAge] = start.addingTimeInterval(-86400)
bridge.updateMedtrumPatchDates(pump)
precondition(store.dates[OpenAPS.Monitor.podAge] == start)
precondition(bridge.pumpExpiresAtDate.value == expiry)
precondition(bridge.pumpActivatedAtDate.value == nil)
// App restart: use the restored activation date, never the current time.
let restored = Bridge(Store())
restored.updateMedtrumPatchDates(pump)
precondition(restored.storage.dates[OpenAPS.Monitor.podAge] == start)
// Extended mode preserves its existing display behavior and same upload date.
pump.state.expiryMode = .extended
bridge.updateMedtrumPatchDates(pump)
precondition(bridge.pumpActivatedAtDate.value == start)
precondition(store.dates[OpenAPS.Monitor.podAge] == start)
// No activation date must not invent a Site Change.
pump.state.patchActivatedAt = nil
pump.state.patchGracePeriodFrom = nil
let unactivated = Bridge(Store())
unactivated.updateMedtrumPatchDates(pump)
precondition(unactivated.storage.dates.isEmpty)
precondition(unactivated.pumpExpiresAtDate.value == nil)
precondition(unactivated.pumpActivatedAtDate.value == nil)
print("Medtrum Site Change date bridge passed: activation, restoration, extended mode, no activation")
'''.replace('METHOD', method)
with tempfile.TemporaryDirectory(prefix='medtrum-site-change-') as directory:
    swift = Path(directory) / 'main.swift'
    swift.write_text(fixture)
    subprocess.run(['swift', '-module-cache-path', directory + '/module-cache', str(swift)], check=True)
