#!/usr/bin/env python3
"""Exercise the production reservoir adapter without Bluetooth or a simulator."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
text = (root / 'Trio/Sources/APS/DeviceDataManager.swift').read_text()
adapter = 'extension PumpManager {' + text.split('extension PumpManager {', 1)[1].split('protocol PumpReservoirObserver', 1)[0]
gate = 'final class PumpReceiverValueGate {' + text.split('final class PumpReceiverValueGate {', 1)[1]
fixture = r'''
import Foundation
protocol PumpManager: AnyObject {}
final class MedtrumPumpManager: PumpManager {
    struct State { var patchSessionEnded = false; var reservoir: Double = 80 }
    var state = State()
}
final class OmniPumpManager: PumpManager {
    struct Measurements { var reservoirLevel: Double }
    struct Pod { var lastInsulinMeasurements: Measurements? }
    var isInoperable = false
    struct State { var podState: Pod? }
    var state = State()
}
final class DanaKitPumpManager: PumpManager {
    struct State { var pumpTime: Date?; var reservoirLevel: Double = 0 }
    var state = State()
}
final class MinimedPumpManager: PumpManager {
    struct Reading { var units: Double }
    struct State { var lastReservoirReading: Reading? }
    var state = State()
}
final class MockPumpManager: PumpManager {
    struct State { var reservoirUnitsRemaining: Double = 123 }
    var state = State()
}
final class Unknown: PumpManager {}
'''
checks = r'''
let medtrum = MedtrumPumpManager()
let gate = PumpReceiverValueGate()
precondition(medtrum.currentReservoir == 80)
precondition(gate.accept("reservoir", owner: medtrum, value: AnyHashable(medtrum.currentReservoir)))
precondition(!gate.accept("reservoir", owner: medtrum, value: AnyHashable(medtrum.currentReservoir)))
medtrum.state.patchSessionEnded = true
precondition(medtrum.currentReservoir == nil)
precondition(gate.accept("reservoir", owner: medtrum, value: AnyHashable(medtrum.currentReservoir)))
medtrum.state.patchSessionEnded = false
precondition(gate.accept("reservoir", owner: medtrum, value: AnyHashable(medtrum.currentReservoir)))
let omni = OmniPumpManager()
precondition(omni.currentReservoir == nil)
omni.state.podState = .init(lastInsulinMeasurements: .init(reservoirLevel: 70))
precondition(omni.currentReservoir == 0xDEAD_BEEF)
omni.state.podState?.lastInsulinMeasurements?.reservoirLevel = 42
precondition(omni.currentReservoir == 42)
omni.isInoperable = true
precondition(omni.currentReservoir == nil)
omni.state.podState = .init(lastInsulinMeasurements: .init(reservoirLevel: 42))
precondition(omni.currentReservoir == nil)
omni.isInoperable = false
omni.state.podState = .init(lastInsulinMeasurements: .init(reservoirLevel: 0))
precondition(omni.currentReservoir == 0)
omni.state.podState = nil
precondition(omni.currentReservoir == nil)
let dana = DanaKitPumpManager()
precondition(dana.currentReservoir == nil)
dana.state.pumpTime = Date()
precondition(dana.currentReservoir == 0)
let minimed = MinimedPumpManager()
precondition(minimed.currentReservoir == nil)
minimed.state.lastReservoirReading = .init(units: 55)
precondition(minimed.currentReservoir == 55)
precondition(MockPumpManager().currentReservoir == 123)
precondition(Unknown().currentReservoir == nil)
let absent: PumpManager? = nil
precondition(absent?.currentReservoir == nil)
print("PASS: Medtrum ended/new patch and deduplication; Omnipod active/ended/faulted/removed/empty; Dana first sync; Minimed/mock/absent")
'''
with tempfile.TemporaryDirectory(prefix='reservoir-') as tmp:
    file = Path(tmp) / 'main.swift'; file.write_text(fixture + adapter + gate + checks)
    subprocess.run(['swiftc', str(file), '-o', tmp + '/test'], check=True)
    subprocess.run([tmp + '/test'], check=True)
