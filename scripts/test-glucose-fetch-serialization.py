#!/usr/bin/env python3
"""Run the actual PluginSource fetchIfNeeded body with macOS Combine and CGM stubs.
No phone, Bluetooth, storage, or insulin delivery. Optional: --sanitize address|thread.
"""
import argparse
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--sanitize', choices=['address', 'thread'])
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/APS/CGM/PluginSource.swift').read_text()
start = source.index('    func fetchIfNeeded()')
end = source.index('\n    private func refreshContactImages', start)
method = source[start:end]
stubs = r'''
import Foundation
import Combine
struct BloodGlucose { var glucose: Int }
enum Reading { case noData, data([BloodGlucose]), error }
enum TestError: Error { case unavailable }
class Manager {
    let callbackQueue = DispatchQueue(label: "test.callback")
    var counter = 0
    var delayed = false
    var pending: ((Reading) -> Void)?
    func fetchNewDataIfNeeded(_ completion: @escaping (Reading) -> Void) {
        if delayed { pending = completion; return }
        counter += 1
        let result: Reading
        switch counter % 4 {
        case 0: result = .noData
        case 1: result = .error
        case 2: result = .data([BloodGlucose(glucose: 100)])
        default: result = .data(Array(repeating: BloodGlucose(glucose: 100), count: 288))
        }
        if counter % 2 == 0 { completion(result) }
        else { callbackQueue.async { completion(result) } }
    }
}
final class G7CGMManager: Manager {}
final class PluginSource {
    let processQueue = DispatchQueue(label: "test.plugin")
    var cgmManager: Manager? = G7CGMManager()
    var decoded = 0
    func readCGMResult(readingResult: Reading) -> Result<[BloodGlucose], Error> {
        dispatchPrecondition(condition: .onQueue(processQueue))
        decoded += 1
        switch readingResult {
        case .data(let values): return .success(values)
        case .noData: return .success([])
        case .error: return .failure(TestError.unavailable)
        }
    }
'''
tests = r'''
}
func wait(_ semaphore: DispatchSemaphore) {
    precondition(semaphore.wait(timeout: .now() + 60) == .success, "Timed out")
}
let plugin = PluginSource()
let receiver = DispatchQueue(label: "test.receiver")
let done = DispatchSemaphore(value: 0)
var received = 0
var readings = 0
let token = (0..<20000).publisher.receive(on: receiver)
    .flatMap { _ in plugin.fetchIfNeeded() }
    .receive(on: receiver)
    .sink(receiveCompletion: { _ in done.signal() }, receiveValue: { values in
        let mapped = values.map { $0.glucose }
        precondition(mapped.allSatisfy { $0 == 100 })
        received += 1
        readings += mapped.count
    })
wait(done)
receiver.sync { precondition(received == 20000 && readings == 1445000) }
withExtendedLifetime(token) {}
print("PASS: 20000 mixed completions, 1445000 values, inline and cross-queue callbacks")

// Drain queued subscription/start work before inspecting the stub.
func drain(_ source: PluginSource) { source.processQueue.sync {}; source.processQueue.sync {} }
for (replace, cancel) in [(true, false), (true, true), (false, true)] {
    let p = PluginSource()
    let old = G7CGMManager(); old.delayed = true
    p.processQueue.sync { p.cgmManager = old }
    let finished = DispatchSemaphore(value: 0)
    var callbacks = 0
    var size = -1
    let subscription = p.fetchIfNeeded().sink(receiveCompletion: { _ in finished.signal() }, receiveValue: { values in
        callbacks += 1; size = values.count
    })
    drain(p)
    if cancel { subscription.cancel(); drain(p) }
    p.processQueue.sync {
        precondition(old.pending != nil)
        if replace { p.cgmManager = G7CGMManager() }
        old.pending?(.data([BloodGlucose(glucose: 321)]))
        old.pending = nil
    }
    drain(p)
    if !cancel { wait(finished) }
    p.processQueue.sync {
        precondition(p.decoded == (replace ? 0 : 1), "Unexpected result decoding")
        precondition(callbacks == (cancel ? 0 : 1))
        if !cancel { precondition(size == 0) }
    }
    withExtendedLifetime(subscription) {}
}
print("PASS: replaced manager ignored; cancelled fetch delivers no values")

for absentSource in [false, true] {
    var p: PluginSource? = PluginSource()
    p!.processQueue.sync { p!.cgmManager = nil }
    let publisher = p!.fetchIfNeeded()
    if absentSource { p = nil }
    let finished = DispatchSemaphore(value: 0)
    var count = 0
    let subscription = publisher.sink(receiveCompletion: { _ in finished.signal() }, receiveValue: { values in
        precondition(values.isEmpty); count += 1
    })
    wait(finished)
    precondition(count == 1)
    withExtendedLifetime(subscription) {}
}
print("PASS: missing manager and released source complete with empty response")
'''
with tempfile.TemporaryDirectory(prefix='trio-glucose-test-') as work:
    work = pathlib.Path(work)
    swift = work / 'Test.swift'
    binary = work / 'test'
    swift.write_text(stubs + method + tests)
    cmd = ['xcrun', 'swiftc', '-swift-version', '5', '-g', '-Onone', '-module-cache-path', '/tmp/trio-glucose-test-cache']
    if args.sanitize:
        cmd += ['-sanitize=' + args.sanitize]
    subprocess.run(cmd + [str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=120)
