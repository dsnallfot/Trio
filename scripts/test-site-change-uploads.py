#!/usr/bin/env python3
"""Exercise production Site Change uploads against disk receipts and a controlled API."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Trio/Sources/Services/Network/Nightscout/NightscoutManager.swift').read_text()
start = source.index('    @MainActor func uploadPodAge()')
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
upload = source[start:end]
model = (root / 'Trio/Sources/Models/NightscoutTreatment.swift').read_text().replace(': JSON,', ': Codable,')
model = model.replace('    static let empty = NightscoutTreatment(from: "{}")!', '')
fixture = r'''
import Foundation
struct PumpHistoryEvent: Codable {}
enum PumpEventStored { enum EventType: String, Codable { case nsSiteChange = "Site Change" } }
enum OpenAPS {
    enum Monitor { static let podAge = "pod-age.json" }
    enum Nightscout { static let uploadedPodAge = "uploaded-pod-age.json" }
}
final class DiskStore {
    let directory: URL
    init(_ directory: URL) { self.directory = directory }
    func retrieve<T: Decodable>(_ file: String, as: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func retrieveAsync<T: Decodable>(_ file: String, as: T.Type) async -> T? { retrieve(file, as: T.self) }
    func save<T: Encodable>(_ value: T, as file: String) {
        try! JSONEncoder().encode(value).write(to: directory.appendingPathComponent(file), options: .atomic)
    }
    func transaction(_ body: (DiskStore) -> Void) { body(self) }
}
@MainActor class API {
    var posts: [[NightscoutTreatment]] = []
    var pauseNext = false
    var waiting: CheckedContinuation<Void, Never>?
    var failOnCall: Int?
    func uploadTreatments(_ treatments: [NightscoutTreatment]) async throws {
        posts.append(treatments)
        if pauseNext {
            pauseNext = false
            await withCheckedContinuation { waiting = $0 }
        }
        if posts.count == failOnCall { throw NSError(domain: "network", code: 1) }
    }
}
enum Category { case nightscout }
func debug(_ category: Category, _ message: String) {}
protocol JSON: Codable {}
class Pump { var localizedTitle = "Pump" }
final class OmniPumpManager: Pump {}
final class MedtrumPumpManager: Pump {
    struct State {
        var patchSessionEnded = false
        var pumpSN = Data([1])
        var patchId = Data([1])
        var patchActivatedAt: Date?
    }
    var state = State()
}
struct Device { var pumpManager: Pump? = OmniPumpManager() }
@MainActor class Manager {
    var isUploadingPodAge = false
    var isUploadEnabled = true
    var reachable = true
    var nightscoutAPI: API?
    let storage: DiskStore
    var deviceManager = Device()
    init(_ store: DiskStore, _ api: API) { storage = store; nightscoutAPI = api }
    func shouldAttemptNightscoutRequest(_ reason: String) -> Bool { reachable }
    UPLOAD
}
@main struct Check {
    @MainActor static func main() async {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = DiskStore(directory)
        let api = API()
        let manager = Manager(store, api)
        let firstDate = Date(timeIntervalSince1970: 1000.123)
        let secondDate = firstDate.addingTimeInterval(86400)
        func setDate(_ date: Date) { store.save(date, as: OpenAPS.Monitor.podAge) }
        func receipts() -> [NightscoutTreatment] {
            store.retrieve(OpenAPS.Nightscout.uploadedPodAge, as: [NightscoutTreatment].self) ?? []
        }
        await manager.uploadPodAge()
        precondition(api.posts.isEmpty, "No activation must not upload")
        setDate(firstDate)
        api.pauseNext = true
        let pending = Task { await manager.uploadPodAge() }
        while api.waiting == nil { await Task.yield() }
        await manager.uploadPodAge()
        precondition(api.posts.count == 1 && receipts().isEmpty, "Gate overlapping calls; no early receipt")
        // A patch change during the request must not be acknowledged by the old response.
        setDate(secondDate)
        api.waiting!.resume()
        await pending.value
        precondition(receipts().map(\.createdAt) == [firstDate])
        precondition(api.posts[0][0].notes == "Pump")
        api.failOnCall = 2
        await manager.uploadPodAge()
        precondition(receipts().count == 1 && !manager.isUploadingPodAge)
        api.failOnCall = nil
        await manager.uploadPodAge()
        precondition(api.posts.count == 3 && receipts().count == 2)
        await manager.uploadPodAge()
        precondition(api.posts.count == 3, "Successful session must not repeat")
        let restarted = Manager(DiskStore(directory), api)
        await restarted.uploadPodAge()
        setDate(firstDate)
        await restarted.uploadPodAge()
        precondition(api.posts.count == 3, "All receipts survive restart, including older sessions")
        setDate(secondDate.addingTimeInterval(86400))
        restarted.isUploadEnabled = false
        await restarted.uploadPodAge()
        restarted.isUploadEnabled = true
        restarted.reachable = false
        await restarted.uploadPodAge()
        precondition(api.posts.count == 3 && receipts().count == 2)
        restarted.reachable = true
        await restarted.uploadPodAge()
        precondition(api.posts.count == 4 && receipts().count == 3)
        precondition(!restarted.isUploadingPodAge)
        let medtrum = MedtrumPumpManager()
        restarted.deviceManager.pumpManager = medtrum
        medtrum.state.patchActivatedAt = firstDate
        await restarted.uploadPodAge() // Migrate the legacy date receipt.
        medtrum.state.patchActivatedAt = firstDate.addingTimeInterval(60)
        await restarted.uploadPodAge()
        precondition(api.posts.count == 4)
        medtrum.state.patchId = Data([2])
        api.pauseNext = true
        api.waiting = nil
        let inFlight = Task { await restarted.uploadPodAge() }
        while api.waiting == nil { await Task.yield() }
        medtrum.state.patchActivatedAt = firstDate.addingTimeInterval(120)
        api.waiting?.resume()
        await inFlight.value
        let fresh = Manager(DiskStore(directory), api)
        fresh.deviceManager.pumpManager = medtrum
        await fresh.uploadPodAge()
        precondition(api.posts.count == 5)
        medtrum.state.patchId = Data()
        await fresh.uploadPodAge()
        medtrum.state.patchSessionEnded = true
        medtrum.state.patchId = Data([3])
        await fresh.uploadPodAge()
        precondition(api.posts.count == 5)
        medtrum.state.patchSessionEnded = false
        await fresh.uploadPodAge()
        precondition(api.posts.count == 6 && receipts().count == 5)
        precondition(!String(decoding: try! JSONEncoder().encode(api.posts), as: UTF8.self).contains("patchKey"))
        print("Site Change uploads passed: success receipts, restart, concurrency, failures/retries, patch change during upload, disabled/offline")
    }
}
'''.replace('    UPLOAD', upload)
with tempfile.TemporaryDirectory(prefix='site-change-uploads-') as directory:
    tmp = Path(directory)
    swift = tmp / 'checks.swift'
    swift.write_text(fixture + model)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path', str(tmp / 'modules'), str(swift), '-o', str(tmp / 'checks')], check=True)
    subprocess.run([str(tmp / 'checks'), directory], check=True)
