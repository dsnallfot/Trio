#!/usr/bin/env python3
"""Exercise production activation setter and timeline across real-pump/simulator sessions."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/APS/OpenAPSSwift/BasalDeliveryTimeline.swift').read_text()
source = source.split('    static func events(from history:')[0] + '}\n'
aps = (root / 'Trio/Sources/APS/APSManager.swift').read_text()
start = aps.index('    var pumpManager: PumpManagerUI? {\n        get')
end = aps.index('\n    var bluetoothManager:', start)
setter = aps[start:end]
source += '''
struct BasalProfileEntry { let minutes: Int; let rate: Decimal }
protocol PumpManagerUI: AnyObject {}
final class MockPumpManager: PumpManagerUI {}
final class RealPump: PumpManagerUI {}
enum Component { case pump }
enum PumpEventType { case replaceComponent(componentType: Component) }
struct NewPumpEvent {
 let date: Date; let dose: Int?; let raw: Data; let title: String; let type: PumpEventType
}
final class DeviceDataManager { var pumpManager: PumpManagerUI? }
final class History {
 var events: [NewPumpEvent] = []
 func storePumpEvents(_ events: [NewPumpEvent]) { self.events += events }
}
final class Host {
 let deviceDataManager = DeviceDataManager()
 let pumpHistoryStorage = History()
''' + setter + '''
}
let host = Host()
let simulator = MockPumpManager()
host.deviceDataManager.pumpManager = RealPump()
host.pumpManager = simulator
precondition(host.pumpHistoryStorage.events.count == 1)
host.pumpManager = simulator
precondition(host.pumpHistoryStorage.events.count == 1, "same instance must not create another session")
host.pumpManager = nil
host.deviceDataManager.pumpManager = simulator
precondition(host.pumpHistoryStorage.events.count == 1, "restoration must not reset history")
host.pumpManager = RealPump()
precondition(host.pumpHistoryStorage.events.count == 1, "real pump behavior unchanged")
host.pumpManager = MockPumpManager()
precondition(host.pumpHistoryStorage.events.count == 2, "new simulator gets its own boundary")
let origin = Date(timeIntervalSince1970: 1000000)
func at(_ minute: Double) -> Date { origin.addingTimeInterval(minute * 60) }
typealias Event = BasalDeliveryTimeline.Event
func event(_ kind: Event.Kind, _ minute: Double) -> Event {
 Event(start: at(minute), end: at(minute), kind: kind)
}
let temp = Event(start: at(20), end: at(50), kind: .temp, rate: 0.4, id: "sim-temp")
let old = [event(.suspend, -6*24*60), event(.detached, -6*24*60+1)]
let history = old + [event(.attached, 10), temp]
let segments = BasalDeliveryTimeline.segments(events: history, profile: [.init(minutes: 0, rate: 0.8)], now: at(30), includeRemainingTemp: true)
precondition(segments.contains { !$0.scheduled && $0.rate == 0.4 && $0.start == at(20) && $0.end == at(50) })
precondition(!segments.contains { $0.start < at(10) })
let pauses = BasalDeliveryTimeline.suspensionIntervals(events: history, now: at(30))
precondition(pauses == [DateInterval(start: at(-6*24*60), end: at(-6*24*60+1))])
let attachmentOnly = [event(.suspend, -100), event(.attached, 10), temp]
precondition(BasalDeliveryTimeline.suspensionIntervals(events: attachmentOnly, now: at(30)) == [DateInterval(start: at(-100), end: at(10))])
let toggled = history + [event(.suspend, 25), event(.resume, 26), event(.suspend, 28)]
let expected = pauses + [DateInterval(start: at(25), end: at(26)), DateInterval(start: at(28), end: at(30))]
precondition(BasalDeliveryTimeline.suspensionIntervals(events: toggled.reversed(), now: at(30)) == expected)
let tied = [event(.suspend, 1), event(.suspend, 2), event(.detached, 2)]
precondition(BasalDeliveryTimeline.suspensionIntervals(events: tied, now: at(30)) == [DateInterval(start: at(1), end: at(2))])
precondition(BasalDeliveryTimeline.suspensionIntervals(events: [event(.suspend, 40)], now: at(30)).isEmpty)
print("PASS: activation, identity, restoration, real pumps, new sessions, old pause/removal, active temp, attachment-only, toggles, simultaneous removal and future events")
'''
with tempfile.TemporaryDirectory(prefix='simulator-boundary-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', '-module-cache-path', '/private/tmp/trio-swift-cache', str(path)], check=True)
