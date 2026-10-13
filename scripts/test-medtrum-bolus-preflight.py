#!/usr/bin/env python3
"""Exercise production preflight control flow with fake transport; never sends pump commands."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func')
manager = (root / 'MedtrumKit/MedtrumKit/PumpManager/MedtrumPumpManager.swift').read_text()
decision = (root / 'MedtrumKit/MedtrumKit/PumpManager/PumpStateSnapshot.swift').read_text().split('enum BolusVerificationDecision: Equatable {')[1]
source = r'''
import Foundation
enum MedtrumConnectError: Error { case failedToConnectToDevice, failedToFindDevice, bolusCompletionUnconfirmed, isBolussing }
enum PumpManagerError: Error { case communication(MedtrumConnectError), deviceState(MedtrumConnectError) }
struct BolusData { let completed: Bool }
struct SynchronizePacketResponse {
    var invalidPayload = false, truncated = false
    var bolus: BolusData?
    func validated(expectedPatchId: UInt64) -> Self { self }
}
struct SynchronizePacket {}
enum WriteResult { case success(Any), failure }
final class Transport {
    var writes = 0
    var response: WriteResult = .failure
    func write(_ packet: SynchronizePacket) -> WriteResult { writes += 1; return response }
}
enum BolusState { case noBolus, inProgress }
struct PatchState { var isSetup = false }
struct PatchID { func toUInt64() -> UInt64 { 109 } }
final class State {
    var bolusState = BolusState.inProgress
    var patchId = PatchID()
    var pumpState = PatchState()
}
struct Logger { func error(_ message: String) {} }
enum StateSyncer {
    static func sync(syncResponse: SynchronizePacketResponse, state: State, pumpManager: Harness,
                     duringReconnect: Bool, fullSync: Bool) {
        pumpManager.syncs += 1
        if syncResponse.bolus?.completed == true { state.bolusState = .noBolus }
    }
}
enum BolusVerificationDecision: Equatable {
'''
source += decision
source += r'''
final class Harness {
    let state = State(), bluetooth = Transport(), log = Logger()
    var connectionError: MedtrumConnectError?
    var connects = 0, syncs = 0
    func recordWork(_ event: String) {}
    func ensureConnectedAndActive(_ completion: (MedtrumConnectError?) -> Void) {
        connects += 1; completion(connectionError)
    }
'''
source += method(manager, '    private func prepareForDeliveryCommand(') + '\n}\n'
source += r'''
func outcome(_ h: Harness) -> String {
    var result = "not-called"
    var calls = 0
    h.prepareForDeliveryCommand { error in
        calls += 1
        switch error {
        case nil: result = "ready"
        case .communication(.bolusCompletionUnconfirmed): result = "unconfirmed"
        case .deviceState(.isBolussing): result = "bolusing"
        default: result = "connection"
        }
    }
    precondition(calls == 1)
    return result
}
let disconnected = Harness()
disconnected.connectionError = .failedToConnectToDevice
precondition(outcome(disconnected) == "unconfirmed")
precondition(disconnected.bluetooth.writes == 0 && disconnected.state.bolusState == .inProgress)
// An earlier failure must not latch the gate: next successful sync clears it.
disconnected.connectionError = nil
disconnected.bluetooth.response = .success(SynchronizePacketResponse(bolus: BolusData(completed: true)))
precondition(outcome(disconnected) == "ready" && disconnected.state.bolusState == .noBolus)
let timedOut = Harness()
precondition(outcome(timedOut) == "unconfirmed" && timedOut.state.bolusState == .inProgress)
let absent = Harness()
absent.bluetooth.response = .success(SynchronizePacketResponse())
precondition(outcome(absent) == "unconfirmed" && absent.syncs == 0)
let malformed = Harness()
malformed.bluetooth.response = .success(SynchronizePacketResponse(truncated: true, bolus: BolusData(completed: true)))
precondition(outcome(malformed) == "unconfirmed" && malformed.state.bolusState == .inProgress)
let active = Harness()
active.bluetooth.response = .success(SynchronizePacketResponse(bolus: BolusData(completed: false)))
precondition(outcome(active) == "bolusing" && active.state.bolusState == .inProgress)
let finished = Harness()
finished.bluetooth.response = .success(SynchronizePacketResponse(bolus: BolusData(completed: true)))
precondition(outcome(finished) == "ready" && finished.state.bolusState == .noBolus && finished.syncs == 1)
let noBolus = Harness()
noBolus.state.bolusState = .noBolus
precondition(outcome(noBolus) == "ready" && noBolus.bluetooth.writes == 0)
noBolus.connectionError = .failedToConnectToDevice
precondition(outcome(noBolus) == "connection")
print("PASS: disconnected / failed read / absent / truncated preserve pending dose; fresh active blocks; explicit completion permits; no-bolus path preserves communication error")
'''
# Check that both command paths use preflight and that reconnection cannot guess completion.
for signature, packet in [('    func enactBolus(', 'SetBolusPacket'), ('    func enactTempBasal(\n        unitsPerHour: Double,\n        duration:', 'CancelTempBasalPacket')]:
    body = method(manager, signature)
    assert 'prepareForDeliveryCommand' in body and packet in body, body
fallback = method(manager, '    func checkBolusDone()')
assert 'state.bolusDose = nil' not in fallback and 'doseEntry.deliveredUnits =' not in fallback
with tempfile.TemporaryDirectory(prefix='medtrum-bolus-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', '-module-cache-path', '/tmp/trio-swift-cache', str(path)], check=True)
