#!/usr/bin/env python3
"""Run production calibration, history-filter and IOB-model regressions on macOS without a simulator."""
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
    return source[start:end]

calibration = (ROOT / "Trio/Sources/APS/CGM/Calibrations/CalibrationService.swift").read_text()
calibration = calibration.replace("import LibreTransmitter\n", "").replace("import Swinject\n", "")
calibration = calibration.replace("@Injected() var storage: FileStorage!", "var storage = FileStorage()")
calibration = calibration.replace("@Injected() var notificationCenter: NotificationCenter!", "var notificationCenter = NotificationCenter()")
calibration = calibration.replace("        injectServices(resolver)\n", "")
manager = (ROOT / "Trio/Sources/APS/DeviceDataManager.swift").read_text()
# Verify the actual delegate entry point selects the filter by pump type and retains commit acknowledgement.
assert "isMinimed: pumpManager is MinimedPumpManager" in manager
assert "self.processQueue.async { completion(error) }" in manager
filter_method = method(manager, "    static func storablePumpEvents")
locks = next((ROOT / "Trio/Sources/Helpers").glob("NSLock*.swift")).read_text()
iob = (ROOT / "Trio/Sources/Models/IOBEntry.swift").read_text()
source = r"""
import Foundation
protocol JSON: Codable {}
protocol Injectable {}
struct Resolver {}
struct Lifetime {}
enum OpenAPS { enum Trio { static let calibrations = "calibrations" } }
final class FileStorage {
    var snapshot: [Calibration] = []
    func save(_ value: [Calibration], as name: String) { snapshot = value }
    func retrieve(_ name: String, as type: [Calibration].Type) -> [Calibration]? { nil }
}
extension Comparable {
    func clamped(_ range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
enum EventType { case tempBasal, bolus }
struct Dose { let unitsPerHour: Double }
struct NewPumpEvent {
    let id: Int
    let type: EventType?
    let dose: Dose?
}
"""
source += method((ROOT / "Trio/Sources/Helpers/Decimal+Extensions.swift").read_text(), "extension Double")
source += "\n" + locks + calibration + iob
source += "\nenum HistoryFilter {\n" + filter_method + "\n}\n"
source += r'''
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let service = BaseCalibrationService(resolver: Resolver())
check(service.calibrate(value: 120) == 120, "Empty calibration identity")
service.addCalibration(Calibration(x: 100, y: 110))
service.addCalibration(Calibration(x: 200, y: 210))
check(abs(service.calibrate(value: 120) - 130) < 0.000001, "Regression arithmetic")
check(service.calibrate(value: 1000) == 500, "Upper clamp")
DispatchQueue.concurrentPerform(iterations: 3000) { index in
    switch index % 6 {
    case 0: service.addCalibration(Calibration(x: Double(index + 1), y: Double(index + 11)))
    case 1: service.removeAllCalibrations()
    case 2: service.removeLast()
    case 3:
        let result = service.calibrate(value: 120)
        check(result.isFinite && (0...500).contains(result), "Concurrent regression")
    case 4: _ = service.calibrations
    default:
        _ = service.slope
        _ = service.intercept
    }
}
service.removeAllCalibrations()
service.removeLast()
check(service.calibrations.isEmpty && service.storage.snapshot.isEmpty, "Persisted final state")
print("PASS calibration arithmetic, concurrent access, empty removal and persisted state")

let events = [
    NewPumpEvent(id: 1, type: .tempBasal, dose: Dose(unitsPerHour: 2.29)),
    NewPumpEvent(id: 2, type: .tempBasal, dose: Dose(unitsPerHour: 2)),
    NewPumpEvent(id: 3, type: .bolus, dose: Dose(unitsPerHour: 3)),
    NewPumpEvent(id: 4, type: nil, dose: nil)
]
check(HistoryFilter.storablePumpEvents(events, maxBasal: 2, isMinimed: false).map(\.id) == [1,2,3,4],
      "Keep all non-Minimed delivered history")
check(HistoryFilter.storablePumpEvents(events, maxBasal: 2, isMinimed: true).map(\.id) == [2,3,4],
      "Minimed drops only temp above limit")
print("PASS non-Minimed history preserved, Minimed limit and other event types")

let base = """
{"iob":1.5,"activity":0.01,"basaliob":0,"bolusiob":1.5,"netbasalinsulin":0,"bolusinsulin":1.5}
"""
let decoder = JSONDecoder()
func read(_ lastTemp: String?) throws -> IOBEntry {
    let payload = lastTemp.map { String(base.dropLast()) + ",\"lastTemp\":" + $0 + "}" } ?? base
    return try decoder.decode(IOBEntry.self, from: Data(payload.utf8))
}
let first = try read("{\"date\":0}")
check(first.iob == Decimal(string: "1.5") && first.lastTemp?.date == 0 && first.lastTemp?.rate == nil,
      "IOB before first temp")
let normal = try read("{\"date\":1234,\"rate\":0.85,\"duration\":30,\"timestamp\":0,\"started_at\":0}")
check(normal.lastTemp?.rate == Decimal(string:"0.85") && normal.lastTemp?.duration == 30, "Existing full temp")
let absent = try read(nil)
check(absent.lastTemp == nil && absent.iob == first.iob, "Absent lastTemp")
let roundtrip = try decoder.decode(IOBEntry.self, from: JSONEncoder().encode(first))
check(roundtrip.lastTemp?.date == 0 && roundtrip.iob == first.iob, "Sparse temp roundtrip")
print("PASS IOB sparse, full, absent lastTemp and roundtrip")
'''
# Swift raw source above uses Python raw strings; key paths and JSON literals need one escape.
source = source.replace("\\\\", "\\")
with tempfile.TemporaryDirectory(prefix="trio-runtime-hotspots-") as work:
    work = Path(work)
    swift = work / "main.swift"
    swift.write_text(source)
    for configuration, flags in [("Debug", ["-Onone"]), ("Release", ["-O"])]:
        binary = work / configuration
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", *flags,
                        "-module-cache-path", str(work / "cache"), str(swift), "-o", str(binary)], check=True)
        print(configuration, flush=True)
        subprocess.run([str(binary)], check=True)
