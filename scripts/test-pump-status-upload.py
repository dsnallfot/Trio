#!/usr/bin/env python3
"""Test production status conversion and suspend correction without a device."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
model = (root / 'Trio/Sources/Models/PumpStatus.swift').read_text()
aps = (root / 'Trio/Sources/APS/APSManager.swift').read_text()
conversion = 'extension PumpManagerStatus {' + aps.split('extension PumpManagerStatus {', 1)[1].split('\nextension BaseAPSManager {', 1)[0]
network = (root / 'Trio/Sources/Services/Network/Nightscout/NightscoutManager.swift').read_text()
assert 'async let fetchedPumpStatus = pumpStatusForUpload()' in network
assert 'guard let liveStatus = deviceManager.pumpManager?.status' in network
assert 'let reservoir = deviceManager.pumpManager?.currentReservoir' in network
predicate = re.search(r'format: "(timestamp >= %@ AND type IN %@[^"\n]+)"', network).group(1)
fixture = r'''
import Foundation
protocol JSON: Codable {}
enum PumpEventStored {
    enum EventType: String { case pumpSuspend = "PumpSuspend", pumpResume = "PumpResume", tempBasal = "TempBasal", bolus = "Bolus" }
}
struct PumpManagerStatus {
    enum Basal: Equatable {
        case active(Date), suspended, pumpInoperable
        var isSuspended: Bool { self == .suspended }
    }
    enum Bolus { case noBolus, bolusing }
    var basalDeliveryState: Basal? = .active(.distantPast)
    var bolusState: Bolus = .noBolus
}
'''
checks = r'''
let now = Date()
let old = now.addingTimeInterval(-14 * 3600)
let status = PumpManagerStatus().pumpStatus
precondition(status.timestamp! >= now) // fresh conversion, even with unchanged manager status
precondition(status.status == .normal && !status.suspended)
let suspend = (type: "PumpSuspend", date: old)
let stopped = status.includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: suspend)
precondition(stopped.suspended && stopped.status == .suspended)
precondition(stopped.timestamp == status.timestamp)
for start in [old, now] {
    precondition(status.includingSuspend(deliveryActiveSince: start, lastPumpEvent: suspend) == status)
}
for type in ["PumpResume", "TempBasal", "Bolus"] {
    precondition(status.includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: (type, now)) == status)
}
precondition(status.includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: nil) == status)
for basal in [PumpManagerStatus.Basal.suspended, .pumpInoperable] {
    let halted = PumpManagerStatus(basalDeliveryState: basal).pumpStatus
    precondition(halted.suspended && halted.status == .suspended)
    precondition(halted.includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: nil) == halted)
}
precondition(PumpManagerStatus(basalDeliveryState: nil).pumpStatus.suspended)
let bolusing = PumpManagerStatus(bolusState: .bolusing).pumpStatus
precondition(bolusing.bolusing && bolusing.status == .bolusing)
precondition(bolusing.includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: suspend).bolusing)
let predicate = NSPredicate(format: PREDICATE_FORMAT, now.addingTimeInterval(-86400) as NSDate,
                            ["PumpSuspend", "PumpResume", "TempBasal", "Bolus"])
func row(_ type: String, _ date: Date = now, basal: Any = NSNull(), bolus: Any = NSNull()) -> NSDictionary {
    ["type": type, "timestamp": date, "tempBasal": basal, "bolus": bolus]
}
precondition(predicate.evaluate(with: row("PumpSuspend")))
precondition(predicate.evaluate(with: row("PumpResume")))
precondition(predicate.evaluate(with: row("Bolus", bolus: ["isExternal": false])))
precondition(!predicate.evaluate(with: row("Bolus", bolus: ["isExternal": true])))
precondition(predicate.evaluate(with: row("TempBasal", basal: ["isScheduledBasal": false])))
precondition(!predicate.evaluate(with: row("TempBasal", basal: ["isScheduledBasal": true])))
precondition(!predicate.evaluate(with: row("PumpSuspend", now.addingTimeInterval(-90000))))
precondition(!predicate.evaluate(with: row("PumpAttached")))
print("PASS: fresh status timestamp; suspend/new pod/resume/temp basal/bolus; fault/missing basal; external insulin and scheduled basal filtering")
'''
checks = checks.replace('PREDICATE_FORMAT', '"' + predicate + '"')
with tempfile.TemporaryDirectory(prefix='pump-status-') as tmp:
    source = Path(tmp) / 'main.swift'
    source.write_text(fixture + model + conversion + checks)
    subprocess.run(['swiftc', str(source), '-o', tmp + '/test'], check=True)
    subprocess.run([tmp + '/test'], check=True)
