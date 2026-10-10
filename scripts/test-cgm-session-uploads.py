#!/usr/bin/env python3
"""Run production CGM selection and upload acknowledgement with disk receipts and a fake API."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
storage_source = (root / 'Trio/Sources/APS/Storage/GlucoseStorage.swift').read_text()
manager_source = (root / 'Trio/Sources/Services/Network/Nightscout/NightscoutManager.swift').read_text()
def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
helper = storage_source[storage_source.index('enum CGMSessionUploadState {'):]
getter = method(storage_source, '    func getCGMStateNotYetUploadedToNightscout() async -> [NightscoutTreatment] {')
upload = method(manager_source, '    @MainActor private func uploadCGMState()').replace('private func', 'func')
chunks = manager_source[manager_source.index('extension Array {'):manager_source.index('extension BaseNightscoutManager {')]
fixture = r'''
import Foundation
struct NightscoutTreatment: Codable { var createdAt: Date?; var notes: String = "sensor" }
enum OpenAPS {
    enum Monitor { static let cgmState = "pending.json" }
    enum Nightscout { static let uploadedCGMState = "uploaded.json" }
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
class GlucoseStore {
    let storage: DiskStore
    init(_ storage: DiskStore) { self.storage = storage }
    GETTER
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
@MainActor class Manager {
    var isUploadingCGMState = false
    var isUploadEnabled = true
    var reachable = true
    var nightscoutAPI: API?
    let storage: DiskStore
    let glucoseStorage: GlucoseStore
    init(_ storage: DiskStore, _ api: API) {
        self.storage = storage; glucoseStorage = GlucoseStore(storage); nightscoutAPI = api
    }
    func shouldAttemptNightscoutRequest(_ reason: String) -> Bool { reachable }
    UPLOAD
}
@main struct Check {
    @MainActor static func main() async {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = DiskStore(directory)
        func session(_ seconds: Double) -> NightscoutTreatment {
            NightscoutTreatment(createdAt: Date(timeIntervalSince1970: seconds))
        }
        let original = session(1000)
        store.save([original, session(1020), original], as: OpenAPS.Monitor.cgmState)
        let api = API()
        let manager = Manager(store, api)
        api.pauseNext = true
        let first = Task { await manager.uploadCGMState() }
        while api.waiting == nil { await Task.yield() }
        await manager.uploadCGMState()
        precondition(api.posts.count == 1 && api.posts[0].count == 1, "Concurrent triggers and duplicate sessions must produce one POST")
        precondition(store.retrieve(OpenAPS.Nightscout.uploadedCGMState, as: [NightscoutTreatment].self) == nil,
                     "No receipt before server success")
        api.waiting!.resume()
        await first.value
        await manager.uploadCGMState()
        precondition(api.posts.count == 1)

        // Recreate storage and manager from disk, as after an app restart/rebuild.
        let restartedStore = DiskStore(directory)
        let restarted = Manager(restartedStore, api)
        await restarted.uploadCGMState()
        precondition(api.posts.count == 1, "Receipt must survive restart")
        store.save([session(2000), original, session(1010)], as: OpenAPS.Monitor.cgmState)
        api.failOnCall = 2
        await restarted.uploadCGMState()
        let pending = await restarted.glucoseStorage.getCGMStateNotYetUploadedToNightscout()
        precondition(pending.count == 1 && pending[0].createdAt == session(2000).createdAt)
        api.failOnCall = nil
        await restarted.uploadCGMState()
        precondition(api.posts.count == 3 && api.posts.last!.count == 1, "Only failed new session retries")
        await restarted.uploadCGMState()
        precondition(api.posts.count == 3)

        // Keep successful earlier chunks acknowledged if a later chunk fails.
        store.save((0..<101).map { session(10000 + Double($0) * 120) }, as: OpenAPS.Monitor.cgmState)
        api.failOnCall = 5
        await restarted.uploadCGMState()
        let remaining = await restarted.glucoseStorage.getCGMStateNotYetUploadedToNightscout()
        precondition(remaining.count == 1)
        api.failOnCall = nil
        restarted.isUploadEnabled = false
        await restarted.uploadCGMState()
        precondition(api.posts.count == 5)
        restarted.isUploadEnabled = true
        await restarted.uploadCGMState()
        precondition(api.posts.count == 6 && api.posts.last!.count == 1)
        precondition(!restarted.isUploadingCGMState)
        precondition(CGMSessionUploadState.pending([NightscoutTreatment(createdAt: nil)], uploaded: []).isEmpty)
        precondition(!CGMSessionUploadState.matches(original, startedAt: Date(timeIntervalSince1970: 1060)))
        print("CGM uploads: persistent receipts, restart, deduplication, concurrency, retries, partial success and disabled upload passed")
    }
}
'''.replace('    GETTER', getter).replace('    UPLOAD', upload)
with tempfile.TemporaryDirectory(prefix='cgm-uploads-') as tmp:
    tmp = Path(tmp)
    source = tmp / 'checks.swift'
    source.write_text(fixture + helper + chunks)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path', str(tmp / 'modules'), str(source), '-o', str(tmp / 'checks')], check=True)
    subprocess.run([str(tmp / 'checks'), str(tmp)], check=True)
