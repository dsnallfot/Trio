#!/usr/bin/env python3
"""Run production snooze payload, dispatch, dedup and storage code with isolated services."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / 'Trio/Sources' / path).read_text()

def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end] + '\n'

remote = read('Services/RemoteControl/TrioRemoteControl.swift')
source = r'''
import Foundation
extension Decimal { var formattedAsMmolL: String { "test" } }
enum LogCategory { case remoteControl }
func debug(_ category: LogCategory, _ message: String) {}
final class Defaults {
    static let standard = Defaults()
    var values: [String: Any] = [:]
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
@MainActor final class TrioAlertManager {
    static let shared = TrioAlertManager()
    var cancellations = 0
    func cancelSnoozes() {
        cancellations += 1
        Defaults.standard.setValue(Date.distantPast, forKey: "UserNotificationsManager.snoozeUntilDate")
    }
}
@MainActor final class MissingDataAlarmManager { static let shared = MissingDataAlarmManager() }
enum BaseUserNotificationsManager {
    static var stops = 0
    static func stopSound() { stops += 1 }
}
final class Nightscout {
    var notes: [String] = []
    func uploadNoteTreatment(note: String) async { notes.append(note); await Task.yield() }
}
final class TrioRemoteControl {
    let nightscoutManager = Nightscout()
    var errors: [String] = []
    private let timeWindow: TimeInterval = 300
    private static var pendingRemoteCommandKeys = Set<String>()
    private static var processedRemoteCommandKeys = [String: Date]()
    private static let remoteCommandDedupQueue = DispatchQueue(label: "test.dedup")
    private static let remoteCommandDedupRetention: TimeInterval = 600
    func logError(_ message: String, pushMessage: PushMessage? = nil) async { errors.append(message) }
'''
for name in ['handleBolusCommand', 'handleTempTargetCommand', 'cancelTempTarget', 'handleMealCommand',
             'handleDeleteMealCommand', 'handleEditMealCommand', 'handleGlucoseCommand',
             'handleDeleteGlucoseCommand', 'handleStartOverrideCommand', 'handleCancelOverrideCommand']:
    source += f'func {name}(_ message: PushMessage) async {{ fatalError("Unexpected dispatch") }}\n'
for name in ['persistPendingRemoteCommandIfNeeded', 'markPendingRemoteCommandMealHandled',
             'clearPendingRemoteCommandIfCompleted', 'markPendingRemoteCommandOverrideHandled']:
    source += f'func {name}(for message: PushMessage) {{ fatalError("Unexpected recovery") }}\n'
for signature in ['    func handleRemoteNotification(', '    internal func remoteCommandDedupKey(',
                  '    internal func beginRemoteCommandIfNotDuplicate(', '    internal func finishRemoteCommandDedup(']:
    source += method(remote, signature)
source += '}\nextension TrioRemoteControl {\n' + method(remote, '    enum CommandType:') + '}\n'
source += read('Models/PushMessage.swift')
source += read('Services/RemoteControl/TrioRemoteControl+snooze.swift')
for path in ['Services/Storage/KeyValueStorage.swift', 'Services/Storage/Cache/Cache.swift',
             'Services/Storage/Cache/UserDefaults+Cache.swift']:
    source += read(path)
source = source.replace('UserDefaults', 'Defaults')
source += r'''
func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: " + name) }
@main struct Tests {
    @MainActor static func main() async throws {
        let controller = TrioRemoteControl()
        let defaults = Defaults.standard
        let key = "UserNotificationsManager.snoozeUntilDate"
        defaults.set(true, forKey: "isTrioRemoteControlEnabled")
        defaults.set("test-secret", forKey: "trioRemoteControlSharedSecret")
        let timestamp = Date().timeIntervalSince1970 - 120
        let json = """
        {"user":"parent","command_type":"snooze","duration":30,"shared_secret":"test-secret","timestamp":\(timestamp)}
        """
        let message = try JSONDecoder().decode(PushMessage.self, from: Data(json.utf8))
        let roundtrip = try JSONDecoder().decode(PushMessage.self, from: JSONEncoder().encode(message))
        check(roundtrip.commandType == .snooze && roundtrip.duration == 30, "wire payload roundtrip")
        check(!message.humanReadableDescription().contains("test-secret"), "description excludes secret")
        await controller.handleRemoteNotification(pushMessage: message)
        let expected = Date(timeIntervalSince1970: timestamp + 1800)
        check(defaults.getValue(Date.self, forKey: key) == expected, "deadline uses sending time, persisted in production format")
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "sv_SE"); formatter.dateFormat = "HH:mm"
        check(controller.nightscoutManager.notes == ["Alla Trio larm snoozade till kl \(formatter.string(from: expected))"], "Nightscout note text and time")
        await controller.handleRemoteNotification(pushMessage: message)
        check(controller.nightscoutManager.notes.count == 1 && BaseUserNotificationsManager.stops == 1, "duplicate is ignored")

        var invalid = message
        for duration: Int? in [nil, -1, 481, Int.max, 1] {
            invalid.duration = duration
            await controller.handleRemoteNotification(pushMessage: invalid)
        }
        invalid = message; invalid.sharedSecret = "wrong"
        await controller.handleRemoteNotification(pushMessage: invalid)
        for time in [timestamp - 600, timestamp + 900, Double.nan, Double.infinity] {
            invalid = message; invalid.timestamp = time
            await controller.handleRemoteNotification(pushMessage: invalid)
        }
        defaults.set(false, forKey: "isTrioRemoteControlEnabled")
        await controller.handleRemoteNotification(pushMessage: message)
        defaults.set(true, forKey: "isTrioRemoteControlEnabled")
        defaults.set("", forKey: "trioRemoteControlSharedSecret")
        await controller.handleRemoteNotification(pushMessage: message)
        defaults.set("test-secret", forKey: "trioRemoteControlSharedSecret")
        check(controller.errors.count == 12, "invalid duration, expired deadline, timestamp and authentication rejected")
        check(defaults.getValue(Date.self, forKey: key) == expected && controller.nightscoutManager.notes.count == 1,
              "rejected commands leave snooze and success notes unchanged")
        for duration in [1, 480] {
            var valid = message; valid.timestamp = Date().timeIntervalSince1970; valid.duration = duration
            await controller.handleRemoteNotification(pushMessage: valid)
            check(defaults.getValue(Date.self, forKey: key) == Date(timeIntervalSince1970: valid.timestamp + Double(duration) * 60), "valid boundary \(duration) minutes")
        }
        var concurrent = message; concurrent.user = "concurrent"
        let delivery = concurrent
        async let first: Void = controller.handleRemoteNotification(pushMessage: delivery)
        async let second: Void = controller.handleRemoteNotification(pushMessage: delivery)
        _ = await (first, second)
        check(controller.nightscoutManager.notes.count == 4, "overlapping deliveries upload once")
        var cancel = message; cancel.duration = 0
        let stops = BaseUserNotificationsManager.stops
        await controller.handleRemoteNotification(pushMessage: cancel)
        await controller.handleRemoteNotification(pushMessage: cancel)
        check(TrioAlertManager.shared.cancellations == 1, "remote cancellation calls local cancel-all method exactly once")
        check(defaults.getValue(Date.self, forKey: key) == .distantPast, "remote cancellation clears shared snooze")
        check(controller.nightscoutManager.notes.last == "Alla Trio snoozer avbrutna" && controller.nightscoutManager.notes.count == 5,
              "cancellation uploads distinct Nightscout receipt once")
        check(BaseUserNotificationsManager.stops == stops, "cancellation must not silence re-armed alarms")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='trio-snooze-') as directory:
    path = Path(directory)
    (path / 'test.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(path / 'cache'), '-parse-as-library',
                    '-o', str(path / 'tests'), str(path / 'test.swift')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
