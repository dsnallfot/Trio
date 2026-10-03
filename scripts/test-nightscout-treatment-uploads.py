#!/usr/bin/env python3
"""Compile production treatment entry points, fetch/send orchestration and workers.

Fake storage/network suspend the first POST deterministically. No server, simulator,
or third-party dependencies. Core Data persistence and server idempotency are not emulated.
"""
import ast
import re
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Trio/Sources/Services/Network/Nightscout/NightscoutManager.swift').read_text()
# Reuse only the UIKit lifetime/continuation test doubles, without running the other suite.
tree = ast.parse((ROOT / 'scripts/test-nightscout-upload-worker.py').read_text())
stubs = next(ast.literal_eval(node.value) for node in tree.body
             if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'stubs' for t in node.targets))


def method(signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end] + '\n'


names = ['ManualGlucose', 'PumpHistory', 'Carbs', 'Overrides', 'TempTargets']
methods = method('    @MainActor private func scheduleTreatmentUpload(')
for name in names:
    methods += method(f'    func upload{name}() async {{\n        let upload')
    methods += method(f'    private func perform{name}Upload(')
for name in ['ManualGlucose', 'Carbs', 'Overrides', 'OverrideRuns', 'TempTargets', 'TempTargetRuns']:
    methods += method(f'    private func upload{name}(')
chunks = source[source.index('extension Array {'):source.index('extension BaseNightscoutManager {')]
worker = source[source.index('@MainActor final class UploadBackgroundTask'):]

fixtures = r'''
struct NightscoutTreatment {
    var id: String?
    var createdAt: Date? = Date(timeIntervalSince1970: 1)
}
struct NightscoutExercise {
    let id: String
    let duration: Int = 10
    var created_at: Any { id }
}
@MainActor final class Store {
    var pending: [String] = ["first"]
    var secondaryPending: [String] = []
    var fetches = 0
    var acknowledgements: [String] = []
    var events: [String] = []
    func treatments() -> [NightscoutTreatment] {
        fetches += 1
        return pending.map { NightscoutTreatment(id: $0) }
    }
    func getManualGlucoseNotYetUploadedToNightscout() async -> [NightscoutTreatment] { treatments() }
    func getPumpHistoryNotYetUploadedToNightscout(using: Int) async -> [NightscoutTreatment] { treatments() }
    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment] { treatments() }
    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment] { secondaryPending.map { NightscoutTreatment(id: $0) } }
    func getOverridesNotYetUploadedToNightscout() async -> [NightscoutExercise] {
        fetches += 1
        return pending.map { NightscoutExercise(id: $0) }
    }
    func getOverrideRunsNotYetUploadedToNightscout() async -> [NightscoutExercise] { secondaryPending.map { NightscoutExercise(id: $0) } }
    func getTempTargetsNotYetUploadedToNightscout() async -> [NightscoutTreatment] { treatments() }
    func getTempTargetRunsNotYetUploadedToNightscout() async -> [NightscoutTreatment] { secondaryPending.map { NightscoutTreatment(id: $0) } }
    func checkIfShouldDeleteNightscoutOverrideEntry(forCreatedAt: String, newDuration: Int?, using: API) async throws {
        events.append("delete:\(forCreatedAt)")
    }
    func acknowledge(_ ids: [String]) {
        acknowledgements += ids
        pending.removeAll { ids.contains($0) }
        secondaryPending.removeAll { ids.contains($0) }
    }
}
@MainActor final class API {
    let pause = Pause()
    var posts: [[String]] = []
    var active = 0
    var peak = 0
    var failFirst = false
    let store: Store
    init(_ store: Store) { self.store = store }
    func send(_ ids: [String]) async throws {
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        posts.append(ids)
        store.events.append("post:\(ids.joined(separator: ","))")
        if posts.count == 1 {
            await pause.wait()
            if failFirst { throw URLError(.timedOut) }
        }
        try Task.checkCancellation()
    }
    func uploadTreatments(_ values: [NightscoutTreatment]) async throws { try await send(values.compactMap(\.id)) }
    func uploadOverrides(_ values: [NightscoutExercise]) async throws { try await send(values.map(\.id)) }
}
@MainActor final class Harness {
    let store = Store()
    lazy var api = API(store)
    var nightscoutAPI: API? { api }
    var glucoseStorage: Store { store }
    var pumpHistoryStorage: Store { store }
    var carbsStorage: Store { store }
    var overridesStorage: Store { store }
    var tempTargetsStorage: Store { store }
    let backgroundContext = 0
    let isUploadEnabled = true
    let treatmentUploadCoordinator = NightscoutTreatmentUploadCoordinator()
    func shouldAttemptNightscoutRequest(_ operation: String) -> Bool { true }
    func updateManualGlucoseAsUploaded(_ values: [NightscoutTreatment]) async { store.acknowledge(values.compactMap(\.id)) }
    func updatePumpEventStoredsAsUploaded(_ values: [NightscoutTreatment]) async { store.acknowledge(values.compactMap(\.id)) }
    func updateCarbsAsUploaded(_ values: [NightscoutTreatment]) async { store.acknowledge(values.compactMap(\.id)) }
    func updateTempTargetsAsUploaded(_ values: [NightscoutTreatment]) async { store.acknowledge(values.compactMap(\.id)) }
    func updateTempTargetRunsAsUploaded(_ values: [NightscoutTreatment]) async { store.acknowledge(values.compactMap(\.id)) }
    func updateOverridesAsUploaded(_ values: [NightscoutExercise]) async { store.acknowledge(values.map(\.id)) }
    func updateOverrideRunsAsUploaded(_ values: [NightscoutExercise]) async { store.acknowledge(values.map(\.id)) }
    func trigger(_ kind: NightscoutTreatmentUploadKind) async {
        switch kind {
        case .manualGlucose: await uploadManualGlucose()
        case .pumpHistory: await uploadPumpHistory()
        case .carbs: await uploadCarbs()
        case .overrides: await uploadOverrides()
        case .tempTargets: await uploadTempTargets()
        }
    }
'''
tests = r'''
@main struct Tests {
    @MainActor static func main() async {
        for kind in NightscoutTreatmentUploadKind.allCases {
            let h = Harness()
            let first = Task { await h.trigger(kind) }
            await until { h.api.pause.waiting }
            // Mimic observer/direct/loop calls arriving while the server has not answered.
            var returned = 0
            let followers = (0..<8).map { _ in Task { await h.trigger(kind); returned += 1 } }
            for _ in 0..<100 { await Task.yield() }
            precondition(h.store.fetches == 1 && h.api.posts.count == 1 && returned == 0)
            h.store.pending.append("arrived-during-post")
            h.api.pause.resume()
            await first.value
            for follower in followers { await follower.value }
            precondition(h.api.posts == [["first"], ["arrived-during-post"]], "Fresh fetch must exclude acknowledged data and include new data")
            precondition(h.store.pending.isEmpty && h.api.peak == 1 && returned == 8)
            await h.trigger(kind)
            precondition(h.api.posts.count == 2, "A later trigger must not resend acknowledged records")
            if kind == .overrides {
                precondition(h.store.events == ["delete:first", "post:first", "delete:arrived-during-post", "post:arrived-during-post"], "Preserve replacement ordering and send once")
                // A later legitimate revision with the same logical id must still be sent.
                h.store.pending = ["first"]
                await h.uploadOverrides()
                precondition(h.api.posts == [["first"], ["arrived-during-post"], ["first"]])
                precondition(Array(h.store.events.suffix(2)) == ["delete:first", "post:first"])
            }
            print("PASS: \(kind) production entry/fetch/send path serializes concurrent triggers, refetches, awaits acknowledgement")
        }
        // Secondary records (FPU, completed overrides and target runs) use the same lane.
        for kind in [NightscoutTreatmentUploadKind.carbs, .overrides, .tempTargets] {
            let h = Harness()
            h.store.secondaryPending = ["completed-run"]
            let first = Task { await h.trigger(kind) }
            await until { h.api.pause.waiting }
            let follower = Task { await h.trigger(kind) }
            for _ in 0..<100 { await Task.yield() }
            precondition(h.api.posts == [["first"]])
            h.api.pause.resume()
            await first.value
            await follower.value
            precondition(h.api.posts == [["first"], ["completed-run"]] && h.api.peak == 1)
            precondition(h.store.secondaryPending.isEmpty)
            if kind == .overrides {
                precondition(h.store.events == ["delete:first", "post:first", "delete:completed-run", "post:completed-run"])
            }
            print("PASS: \(kind) secondary records share serialization and are sent exactly once")
        }
        // Failure leaves the record pending; the next explicit trigger can retry.
        let failed = Harness()
        failed.api.failFirst = true
        let attempt = Task { await failed.uploadManualGlucose() }
        await until { failed.api.pause.waiting }
        failed.api.pause.resume()
        await attempt.value
        precondition(failed.store.pending == ["first"] && failed.store.acknowledgements.isEmpty)
        await failed.uploadManualGlucose()
        precondition(failed.store.pending.isEmpty && failed.api.posts.count == 2)
        print("PASS: failed send is not acknowledged and can retry on a later trigger")

        // Independent families can progress while one family has a blocked network call.
        let coordinator = NightscoutTreatmentUploadCoordinator()
        let pause = Pause()
        let slow = coordinator.enqueue(.carbs) { await pause.wait() }
        await until { pause.waiting }
        var overrideRan = false
        let other = coordinator.enqueue(.overrides) { overrideRan = true }
        await other.value
        precondition(overrideRan && pause.waiting)
        pause.resume()
        await slow.value
        precondition(UIApplication.shared.activeCount == 0)
        print("PASS: different treatment families remain independent; no background leases leak")

        // Validate the actual SGV acknowledgement predicate: it must not claim BG Check success.
        let predicate = NSPredicate(format: ACK_PREDICATE, ["manual", "sensor"] as NSArray)
        precondition(!predicate.evaluate(with: ["id": "manual", "isManual": true]))
        precondition(predicate.evaluate(with: ["id": "sensor", "isManual": false]))
        print("PASS: SGV acknowledgement cannot suppress the separate manual treatment")
    }
}
'''
ack = method('    private func updateGlucoseAsUploaded(')
predicate = re.search(r'NSPredicate\(format: ("[^"]+")', ack).group(1)
tests = tests.replace('ACK_PREDICATE', predicate)
with tempfile.TemporaryDirectory(prefix='trio-treatment-tests-') as directory:
    path = Path(directory)
    swift = path / 'Tests.swift'
    swift.write_text(stubs + worker + chunks + fixtures + methods + '}\n' + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-module-cache-path', str(path / 'cache'), str(swift), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True, timeout=30)
