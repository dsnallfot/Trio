import Combine
import Darwin
import Foundation
import JavaScriptCore

enum DiagnosticLogging {
    static let enabledKey = "Trio.LogDiagnostics"
    static let defaultEnabled = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil ?
            defaultEnabled : UserDefaults.standard.bool(forKey: enabledKey)
    }
}

extension String {
    var lowercasingFirst: String { prefix(1).lowercased() + dropFirst() }
    var uppercasingFirst: String { prefix(1).uppercased() + dropFirst() }
    var camelCased: String {
        guard !isEmpty else { return "" }
        let parts = components(separatedBy: .alphanumerics.inverted)
        let first = parts.first!.lowercasingFirst
        let rest = parts.dropFirst().map(\.uppercasingFirst)
        return ([first] + rest).joined()
    }

    var pascalCased: String {
        guard !isEmpty else { return "" }
        let parts = components(separatedBy: .alphanumerics.inverted)
        let first = parts.first!.uppercasingFirst
        let rest = parts.dropFirst().map(\.uppercasingFirst)
        return ([first] + rest).joined()
    }
}

final class JavaScriptWorker {
    private let virtualMachine: JSVirtualMachine
    private let contextCreationLock = NSLock()

    init() {
        virtualMachine = JSVirtualMachine()!
    }

    private func createContext() -> JSContext {
        contextCreationLock.lock()
        defer { contextCreationLock.unlock() }
        let context = JSContext(virtualMachine: virtualMachine)!
        context.exceptionHandler = { _, exception in
            if let error = exception?.toString() {
                warning(.openAPS, "JavaScript Error: \(error)")
            }
        }
        // Logging is disabled: do not retain the worker or enqueue empty log jobs.
        let consoleLog: @convention(block) (String) -> Void = { _ in }
        context.setObject(consoleLog, forKeyedSubscript: "_consoleLog" as NSString)
        return context
    }

    /// A synchronous transaction owns its context until every script and result is evaluated.
    /// Return native values only; do not let Session or JSValue escape the transaction.
    func inCommonContext<Value>(execute: (Session) -> Value) -> Value {
        RuntimeDiagnostics.shared.increment("jsContexts")
        RuntimeDiagnostics.shared.increment("jsActive")
        defer {
            RuntimeDiagnostics.shared.increment("jsActive", by: -1)
            RuntimeDiagnostics.shared.increment("jsContexts", by: -1)
        }
        // Re-evaluating bundles in a pooled context retains growing script state.
        // Drain Objective-C temporaries before ending the transaction's lifetime.
        return autoreleasepool {
            let context = createContext()
            return execute(Session(context: context))
        }
    }

    struct Session {
        fileprivate let context: JSContext

        @discardableResult func evaluate(script: Script) -> JSValue! {
            let fileName = URL(fileURLWithPath: script.name).lastPathComponent
            context.setObject(fileName, forKeyedSubscript: "scriptName" as NSString)
            let result = context.evaluateScript(script.body)
            return result
        }

        private func evaluate(string: String) -> JSValue! {
            context.evaluateScript(string)
        }

        private func json(for string: String) -> RawJSON {
            evaluate(string: "JSON.stringify(\(string), null, 4);")!.toString()!
        }

        func call(function: String, with arguments: [JSON]) -> RawJSON {
            let joined = arguments.map(\.rawJSON).joined(separator: ",")
            return json(for: "\(function)(\(joined))")
        }

        func evaluateBatch(scripts: [Script]) {
            scripts.forEach { script in
                let fileName = URL(fileURLWithPath: script.name).lastPathComponent
                context.setObject(fileName, forKeyedSubscript: "scriptName" as NSString)
                context.evaluateScript(script.body)
            }
        }
    }
}

/// Bounded counters and throttled snapshots; never reads patient payloads.
final class RuntimeDiagnostics {
    static let shared = RuntimeDiagnostics()
    private let lock = NSLock()
    private var counters: [String: Int] = [:]
    private var peaks: [String: Int] = [:]
    private var nextID: UInt64 = 0
    private var lastSample: TimeInterval = -.infinity
    private var lastObjectSamples: [String: TimeInterval] = [:]

    func sampleObjects(_ key: String, count: @autoclosure () -> Int) {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastObjectSamples[key, default: -.infinity] >= 60 else {
            lock.unlock()
            return
        }
        lastObjectSamples[key] = now
        lock.unlock()
        // Read the context only on its own queue, and avoid materializing its set on every save.
        set(key, to: count())
    }

    func set(_ key: String, to value: Int) {
        lock.lock()
        counters[key] = value
        peaks[key] = max(peaks[key, default: 0], value)
        lock.unlock()
    }

    func increment(_ key: String, by amount: Int = 1) {
        lock.lock()
        counters[key, default: 0] += amount
        peaks[key] = max(peaks[key, default: 0], counters[key, default: 0])
        lock.unlock()
    }

    func begin(_ kind: String, force: Bool = false) -> UInt64 {
        lock.lock()
        nextID += 1
        let id = nextID
        counters[kind, default: 0] += 1
        peaks[kind] = max(peaks[kind, default: 0], counters[kind, default: 0])
        lock.unlock()
        sample("begin \(kind) id=\(id)", force: force)
        return id
    }

    func end(_ kind: String, id: UInt64, force: Bool = false) {
        increment(kind, by: -1)
        sample("end \(kind) id=\(id)", force: force)
    }

    func sample(_ event: String, force: Bool = false) {
        guard DiagnosticLogging.isEnabled else { return }
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastSample >= 60 else {
            lock.unlock()
            return
        }
        lastSample = now
        let counts = counters.keys.sorted().map {
            "\($0)=\(counters[$0, default: 0])/\(peaks[$0, default: 0])"
        }.joined(separator: " ")
        lock.unlock()

        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = result == KERN_SUCCESS ? String(format: "%.1f", Double(info.phys_footprint) / 1_048_576) : "unavailable"
        if result == KERN_SUCCESS {
            let sample = RuntimeDiagnosticsDisplay.MemorySample(
                date: Date(), mebibytes: Double(info.phys_footprint) / 1_048_576
            )
            Task { @MainActor in
                RuntimeDiagnosticsDisplay.shared.record(sample)
            }
        }
        debug(
            .openAPS,
            "MEM pid=\(ProcessInfo.processInfo.processIdentifier) footprintMiB=\(footprint) \(event) active/peak: \(counts)"
        )
    }
}

@MainActor final class RuntimeDiagnosticsDisplay: ObservableObject {
    struct MemorySample: Sendable {
        let date: Date
        let mebibytes: Double
    }

    static let shared = RuntimeDiagnosticsDisplay()
    @Published private(set) var latest: MemorySample?
    @Published private(set) var peak: MemorySample?
    @Published private(set) var sessionStart: Date?

    func markSessionStart(_ date: Date) {
        if sessionStart == nil { sessionStart = date }
    }

    func record(_ sample: MemorySample) {
        if latest == nil || sample.date >= latest!.date { latest = sample }
        if peak == nil || sample.mebibytes > peak!.mebibytes { peak = sample }
    }
}
