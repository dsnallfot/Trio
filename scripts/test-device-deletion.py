#!/usr/bin/env python3
"""Run Trio's actual pump deletion callback against a serial queue and replacement manager."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/APS/DeviceDataManager.swift').read_text()
start = source.index('    func pumpManagerWantsDeletion(')
end = source.index('\n    func pumpManager(', start)
method = source[start:end]
fixture = r'''
import Foundation
protocol PumpManager: AnyObject {}
final class Pump: PumpManager {}
protocol PumpDeactivatedObserver { func pumpDeactivatedDidChange() }
final class Observer: PumpDeactivatedObserver {
    var count = 0
    func pumpDeactivatedDidChange() { count += 1 }
}
final class Broadcaster {
    let observer = Observer()
    func notify(_ type: Any.Type, on queue: DispatchQueue,
                _ callback: @escaping (PumpDeactivatedObserver) -> Void) {
        queue.async { callback(self.observer) }
    }
}
final class Host {
    let processQueue = DispatchQueue(label: "test.deletion")
    let broadcaster = Broadcaster()
    var pumpManager: PumpManager?
    METHOD
}
@main struct Test {
    static func main() async {
        let host = Host()
        let old = Pump(), replacement = Pump()
        host.processQueue.sync { host.pumpManager = old }
        await host.pumpManagerWantsDeletion(old)
        host.processQueue.sync {
            precondition(host.pumpManager == nil, "must remove manager before returning")
            precondition(host.broadcaster.observer.count == 1)
        }
        await host.pumpManagerWantsDeletion(old)
        host.processQueue.sync {
            precondition(host.broadcaster.observer.count == 1, "duplicate deletion must not notify twice")
            host.pumpManager = replacement
        }
        await host.pumpManagerWantsDeletion(old)
        host.processQueue.sync {
            precondition(host.pumpManager === replacement, "stale callback must preserve replacement")
            precondition(host.broadcaster.observer.count == 1)
        }
        await host.pumpManagerWantsDeletion(replacement)
        host.processQueue.sync {
            precondition(host.pumpManager == nil)
            precondition(host.broadcaster.observer.count == 2)
        }
        print("PASS: async removal completion, duplicate callback, replacement identity, subsequent deletion")
    }
}
'''.replace('    METHOD', method)
with tempfile.TemporaryDirectory(prefix='trio-deletion-') as directory:
    path = Path(directory)
    (path / 'test.swift').write_text(fixture)
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(path / 'test.swift'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True, timeout=15)
