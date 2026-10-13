#!/usr/bin/env python3
"""Run production receiver gate and summary counter with a deterministic clock; no device data."""
from pathlib import Path
import tempfile
import subprocess
root = Path(__file__).resolve().parents[1]
gate = (root / 'Trio/Sources/APS/DeviceDataManager.swift').read_text().split('final class PumpReceiverValueGate {', 1)[1]
counters = (root / 'MedtrumKit/MedtrumKit/PumpManager/PumpStateSnapshot.swift').read_text().split('public final class MedtrumWorkDiagnostics {', 1)[1]
source = 'import Foundation\nfinal class PumpReceiverValueGate {' + gate
source += '\npublic final class MedtrumWorkDiagnostics {' + counters.split('/// Only an explicit, valid pump response')[0]
source += r'''
let gate = PumpReceiverValueGate()
let owner = NSObject(), replacement = NSObject()
precondition(gate.accept("value", owner: owner, value: 10, now: 0))
for i in 1...10000 { precondition(!gate.accept("value", owner: owner, value: 10, now: Double(i))) }
precondition(gate.accept("value", owner: owner, value: 11, now: 10001))
precondition(gate.accept("value", owner: replacement, value: 11, now: 10002))
precondition(gate.accept("date", owner: owner, value: AnyHashable(nil as Date?), now: 0))
precondition(!gate.accept("date", owner: owner, value: AnyHashable(nil as Date?), now: 1))
precondition(gate.accept("date", owner: owner, value: AnyHashable(Date(timeIntervalSince1970: 10)), now: 2))
precondition(gate.accept("date", owner: owner, value: AnyHashable(nil as Date?), now: 3))
precondition(gate.accept("battery", owner: owner, value: 50, maxAge: 300, now: 0))
precondition(!gate.accept("battery", owner: owner, value: 50, maxAge: 300, now: 299))
precondition(gate.accept("battery", owner: owner, value: 50, maxAge: 300, now: 300))
precondition(gate.accept("battery", owner: owner, value: 49, maxAge: 300, now: 301))
gate.invalidate("battery")
precondition(gate.accept("battery", owner: owner, value: 49, maxAge: 300, now: 302))
precondition(gate.accept("status", owner: owner, value: AnyHashable([false, false]), now: 0))
precondition(gate.accept("status", owner: owner, value: AnyHashable([true, false]), now: 1))
precondition(gate.accept("status", owner: owner, value: AnyHashable([false, true]), now: 2))
let concurrent = MedtrumWorkDiagnostics(startTime: 0)
DispatchQueue.concurrentPerform(iterations: 10000) { _ in
    precondition(concurrent.record("packets", now: 100) == nil)
}
precondition(concurrent.record("flush", now: 900)!.contains("packets=10000"))
let d = MedtrumWorkDiagnostics(startTime: 0)
for _ in 0..<1000 { precondition(d.record("packets", now: 899) == nil) }
let first = d.record("writes", count: 2, now: 900)!
precondition(first.contains("packets=1000") && first.contains("writes=2") && first.contains("windowSec=900"))
precondition(d.record("packets", now: 901) == nil)
let second = d.record("writes", now: 1800)!
precondition(second.contains("packets=1") && second.contains("writes=1") && !second.contains("1000"))
print("PASS: duplicates, changed values, new manager, nil transitions, freshness deadline, retry invalidation, 15-minute summaries and counter reset")
'''
with tempfile.TemporaryDirectory(prefix='medtrum-receivers-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', '-module-cache-path', '/tmp/trio-swift-cache', str(path)], check=True)
