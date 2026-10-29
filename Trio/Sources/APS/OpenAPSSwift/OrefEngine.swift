import Foundation

enum OrefEngine: String, JSON {
    case javascript
    case swift
    static let cacheKey = "settings/oref-engine-cache.json"
    var title: String { self == .swift ? "Swift" : "JavaScript" }
}

struct OrefRunStatus: JSON {
    static let storageKey = "monitor/oref-engine-run.json"
    static let historyKey = "monitor/oref-engine-timing.json"
    let engine: OrefEngine
    let date: Date
    let duration: TimeInterval
}

/// Async FIFO mutex. Unlike an actor method alone, it holds ownership across
/// suspension points. Cancellation is checked after acquisition by the caller.
final class OrefCalculationGate {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if busy {
                waiters.append(continuation)
                lock.unlock()
            } else {
                busy = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()
        if waiters.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}
