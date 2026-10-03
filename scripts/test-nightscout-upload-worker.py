#!/usr/bin/env python3
"""Run the production upload worker against a deterministic UIKit lifetime fake.

No simulator or third-party packages required. This exercises concurrency/lifetime,
not actual iOS background scheduling or Nightscout HTTP behavior.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Trio/Sources/Services/Network/Nightscout/NightscoutManager.swift').read_text()
worker = source.split('// MARK: - Upload background lifetime\n', 1)[1]
models_path = ROOT / 'Trio/Sources/Models'
models = 'typealias JSON = Codable\n'
for name in ['Determination', 'Battery', 'PumpStatus', 'IOBEntry', 'Oref2_variables']:
    models += (models_path / (name + '.swift')).read_text() + '\n'
models += (models_path / 'NightscoutStatus.swift').read_text().split('struct NightscoutTimevalue:', 1)[0]
models += 'enum TempType:' + (models_path / 'PumpHistoryEvent.swift').read_text().split('enum TempType:', 1)[1].split('extension PumpHistoryEvent', 1)[0]

stubs = r'''
import Foundation
struct UIBackgroundTaskIdentifier: Equatable, Hashable {
    let rawValue: Int
    static let invalid = Self(rawValue: 0)
}
@MainActor final class UIApplication {
    static let shared = UIApplication()
    var nextID = 1
    var deny = false
    var handlers: [UIBackgroundTaskIdentifier: () -> Void] = [:]
    var ended: [UIBackgroundTaskIdentifier] = []
    var activeCount: Int { handlers.count }
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        if deny { return .invalid }
        let id = UIBackgroundTaskIdentifier(rawValue: nextID)
        nextID += 1
        handlers[id] = expirationHandler
        return id
    }
    func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {
        precondition(id != .invalid && handlers[id] != nil, "Invalid or duplicate end")
        handlers[id] = nil
        ended.append(id)
    }
    func expireAll() {
        for handler in Array(handlers.values) { handler() }
    }
}
enum Category { case nightscout }
func debug(_ category: Category, _ message: String) {}
final class BackgroundTaskDiagnostics {
    static let shared = BackgroundTaskDiagnostics()
    enum Event { case start, end, expiration }
    func record(_ event: Event, id: UIBackgroundTaskIdentifier, name: String, reason: String = "-") {}
}
@MainActor final class Pause {
    var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() {
        let saved = continuation
        continuation = nil
        saved?.resume()
    }
}
@MainActor func until(_ condition: () -> Bool) async {
    for _ in 0..<10000 {
        if condition() { return }
        await Task.yield()
    }
    preconditionFailure("Test did not reach expected state")
}
'''
tests = r'''
@main struct Tests {
    @MainActor static func main() async {
        let fixture = #"{"device":"test", "openaps":{"version":"test", "suggested":{"reason":"test","deliverAt":100,"timestamp":100}, "enacted":{"reason":"test","deliverAt":100,"timestamp":101,"received":false}}, "pump":{"clock":100,"reservoir":100}, "uploader":{"battery":75}, "additional":{"memoryUsageLatest":100,"memoryUsageMax":150}}"#
        func key(_ json: String, destination: String = "site-a") -> Data {
            let status = try! JSONDecoder().decode(NightscoutStatus.self, from: Data(json.utf8))
            return try! status.uploadComparisonKey(destination: destination)
        }
        let base = key(fixture)
        precondition(base == key(fixture.replacingOccurrences(of: "memoryUsageLatest\":100", with: "memoryUsageLatest\":120")))
        precondition(base != key(fixture.replacingOccurrences(of: "timestamp\":101", with: "timestamp\":102")), "Enacted revision with unchanged deliverAt must upload")
        precondition(base != key(fixture.replacingOccurrences(of: "received\":false", with: "received\":true")), "Changed enacted result must upload")
        precondition(base != key(fixture.replacingOccurrences(of: "reservoir\":100", with: "reservoir\":99")), "Pump update must upload")
        precondition(base != key(fixture, destination: "site-b"))
        print("PASS: real status model preserves enacted/pump/destination changes while ignoring memory-only changes")

        let app = UIApplication.shared

        // The upload lease is acquired before enqueue returns, overlapping the loop lease.
        let loopLease = UploadBackgroundTask(name: "loop")
        loopLease.begin()
        let worker = NightscoutUploadWorker(name: "status")
        let pause = Pause()
        var seen: [Int] = []
        let first = worker.enqueue {
            precondition(app.activeCount > 0)
            seen.append(1)
            await pause.wait()
        }
        precondition(app.activeCount == 2, "Handoff must acquire upload time synchronously")
        loopLease.end(reason: "handoff")
        precondition(app.activeCount == 1)
        await until { pause.waiting }
        _ = worker.enqueue { seen.append(2) }
        let latest = worker.enqueue { seen.append(3) }
        precondition(seen == [1], "No overlapping operations")
        pause.resume()
        await first.value
        await latest.value
        precondition(seen == [1, 3], "Only the newest pending trigger should run")
        precondition(app.activeCount == 0)
        print("PASS: background handoff, serial execution, newest pending trigger, await completion")

        // Expiration discards queued work and cancels the active attempt, ending exactly once.
        let expiring = NightscoutUploadWorker(name: "expiring")
        let blocked = Pause()
        var cancelled = false
        var unwanted = false
        let active = expiring.enqueue {
            await blocked.wait()
            cancelled = Task.isCancelled
        }
        await until { blocked.waiting }
        _ = expiring.enqueue { unwanted = true }
        let endedBefore = app.ended.count
        app.expireAll()
        precondition(app.activeCount == 0)
        blocked.resume()
        await active.value
        precondition(cancelled && !unwanted)
        precondition(app.ended.count == endedBefore + 1)
        print("PASS: expiration cancels active work, discards pending work, ends once")

        // A new sensor wake may arrive before the cancelled attempt has finished unwinding.
        let recovering = NightscoutUploadWorker(name: "recovering")
        let oldAttempt = Pause()
        var oldCancelled = false
        var newRan = false
        let old = recovering.enqueue {
            await oldAttempt.wait()
            oldCancelled = Task.isCancelled
        }
        await until { oldAttempt.waiting }
        app.expireAll()
        let new = recovering.enqueue {
            precondition(!Task.isCancelled && app.activeCount == 1)
            newRan = true
        }
        precondition(app.activeCount == 1, "Fresh trigger must acquire fresh background time")
        oldAttempt.resume()
        await old.value
        await new.value
        precondition(oldCancelled && newRan && app.activeCount == 0)
        print("PASS: fresh trigger survives cancellation cleanup without overlapping requests")

        app.deny = true
        let denied = NightscoutUploadWorker(name: "denied")
        var didRun = false
        let deniedTask = denied.enqueue { didRun = true }
        await deniedTask.value
        precondition(!didRun && app.activeCount == 0)
        app.deny = false
        let retry = denied.enqueue { didRun = true }
        await retry.value
        precondition(didRun && app.activeCount == 0)
        print("PASS: denied background time defers work; later trigger retries")

        // A timeout/failure must not poison future work, and treatment latency cannot block status.
        let treatments = NightscoutUploadWorker(name: "treatments")
        let slowTreatment = Pause()
        let treatment = treatments.enqueue { await slowTreatment.wait() }
        await until { slowTreatment.waiting }
        var statusRan = false
        let status = worker.enqueue { statusRan = true }
        await status.value
        precondition(statusRan && slowTreatment.waiting && app.activeCount == 1)
        slowTreatment.resume()
        await treatment.value
        precondition(app.activeCount == 0)
        print("PASS: slow treatments do not block status or leak background time")

        let lease = UploadBackgroundTask(name: "finish")
        lease.begin()
        let staleExpiration = app.handlers.values.first!
        let count = app.ended.count
        lease.end(reason: "success")
        lease.end(reason: "again")
        staleExpiration()
        precondition(app.ended.count == count + 1)
        lease.begin()
        staleExpiration()
        precondition(lease.isActive, "Old expiration must not end a new lease")
        lease.end(reason: "new-completed")
        precondition(app.activeCount == 0)
        print("PASS: repeated completion and stale expiration cannot end a newer lease")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='trio-upload-tests-') as directory:
    path = Path(directory)
    swift = path / 'Tests.swift'
    swift.write_text(stubs + models + worker + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-module-cache-path', str(path / 'cache'), str(swift), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True, timeout=30)
