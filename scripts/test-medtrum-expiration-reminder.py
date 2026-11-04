#!/usr/bin/env python3
"""Exercise the production Medtrum reminder with deterministic activation/save times."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
kit = root / 'MedtrumKit'
source = (kit / 'MedtrumKit/PumpManager/MedtrumAlert.swift').read_text().replace('import LoopKit', 'import Foundation')
time = (kit / 'Common/TimeInterval.swift').read_text()
# Use the actual LoopKit Alert model; only the pump alarm enum needs a stand-in.
alert = (root / 'LoopKit/LoopKit/AnyCodableEquatable.swift').read_text() + '\n' + (root / 'LoopKit/LoopKit/Alert.swift').read_text()
view_model = (kit / 'MedtrumKitUI/ViewModels/Settings/PatchSettingsViewModel.swift').read_text()
reschedule = view_model.split('        let activatedAt = pumpManager.state.patchActivatedAt', 1)[1].split('\n    }\n}', 1)[0]
reschedule = '        let activatedAt = pumpManager.state.patchActivatedAt' + reschedule
checks = r'''
enum PumpAlarmType { case noDelivery, occlusion, noInsulin }
let activated = Date(timeIntervalSince1970: 1000000)
func reminder(age: Double) -> Alert {
    MedtrumAlert.patchExpirationReminder(activatedAt: activated, after: .hours(72),
                                        now: activated.addingTimeInterval(.hours(age)))
}
let initial = reminder(age: 0)
precondition(initial.trigger == .delayed(interval: .hours(72)))
precondition(initial.backgroundContent.body.contains("8"))
let later = reminder(age: 24)
precondition(later.trigger == .delayed(interval: .hours(48)))
precondition(later.backgroundContent == initial.backgroundContent)
let resaved = reminder(age: 48)
precondition(resaved.trigger == .delayed(interval: .hours(24)))
precondition(resaved.identifier == initial.identifier)
precondition(reminder(age: 72).trigger == .immediate)
let overdue = reminder(age: 73)
precondition(overdue.trigger == .immediate)
precondition(overdue.backgroundContent.body.contains("7"))
let expired = reminder(age: 81)
precondition(expired.trigger == .immediate)
precondition(expired.backgroundContent.body.contains("0"))
precondition(!expired.backgroundContent.body.contains("-"))
final class Issuer {
    var issued: [Alert] = []
    var retracted: [Alert.Identifier] = []
    let retraction = DispatchSemaphore(value: 0)
    let issuance = DispatchSemaphore(value: 0)
    func retractAlert(identifier: Alert.Identifier) async { retracted.append(identifier); retraction.signal() }
    func issueAlert(_ alert: Alert) async { issued.append(alert); issuance.signal() }
}
final class Delegate {
    let issuer = Issuer()
    func notify(_ callback: (Issuer?) -> Void) { callback(issuer) }
}
final class Pump {
    enum Mode { case `default`, extended }
    struct State {
        var patchActivatedAt: Date? = Date().addingTimeInterval(-.hours(24))
        var notificationAfterActivation: TimeInterval = .hours(72)
        var expiryMode: Mode = .default
        var patchId = Data([1])
    }
    var state = State()
    let pumpDelegate = Delegate()
}
func reschedule(_ pumpManager: Pump) {
    RESCHEDULE
}
let pump = Pump()
reschedule(pump)
precondition(pump.pumpDelegate.issuer.retraction.wait(timeout: .now() + 3) == .success)
precondition(pump.pumpDelegate.issuer.retracted.count == 1)
precondition(pump.pumpDelegate.issuer.issuance.wait(timeout: .now() + 3) == .success)
let scheduled = pump.pumpDelegate.issuer.issued.last!
if case let .delayed(interval) = scheduled.trigger {
    precondition(abs(interval - .hours(48)) < 5)
} else { preconditionFailure("Expected delay until original activation + 72 hours") }
pump.state.expiryMode = .extended
reschedule(pump)
precondition(pump.pumpDelegate.issuer.retraction.wait(timeout: .now() + 3) == .success)
pump.state.expiryMode = .default
pump.state.patchActivatedAt = nil
reschedule(pump)
precondition(pump.pumpDelegate.issuer.retraction.wait(timeout: .now() + 3) == .success)
pump.state.patchActivatedAt = Date()
pump.state.patchId = Data()
reschedule(pump)
precondition(pump.pumpDelegate.issuer.retraction.wait(timeout: .now() + 3) == .success)
precondition(pump.pumpDelegate.issuer.issued.count == 1)
precondition(pump.pumpDelegate.issuer.retracted.count == 4)
print("Medtrum reminder passed: 72-hour conversion, repeated saves, due/overdue triggers, remaining-time text")
'''.replace('RESCHEDULE', reschedule)
# Exercise the Trio notification adapter with an in-memory notification center.
manager = (root / 'Trio/Sources/APS/DeviceDataManager.swift').read_text()
adapter = manager.split('private enum MedtrumExpiryNotification {', 1)[1].split('\n}', 1)[0]
checks += r'''
enum NotificationAction: String { case pumpConfig; static let key = "action" }
enum Sound { case `default` }
class UNMutableNotificationContent {
    var title = "", body = ""
    var sound: Sound?
    var userInfo: [String: Any] = [:]
}
struct UNTimeIntervalNotificationTrigger { let timeInterval: Double; let repeats: Bool }
struct UNNotificationRequest {
    let identifier: String; let content: UNMutableNotificationContent; let trigger: UNTimeIntervalNotificationTrigger?
}
class UNUserNotificationCenter {
    static let center = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { center }
    var pending: [String: UNNotificationRequest] = [:]
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { for id in ids { pending[id] = nil } }
    func removeDeliveredNotifications(withIdentifiers ids: [String]) {}
    func add(_ req: UNNotificationRequest, withCompletionHandler completion: (Error?) -> Void) {
        pending[req.identifier] = req; completion(nil)
    }
}
enum Category { case service }
func warning(_ category: Category, _ message: String, error: Error) {}
enum MedtrumExpiryNotification {
ADAPTER
}
let center = UNUserNotificationCenter.current()
let key = MedtrumExpiryNotification.identifier
precondition(MedtrumExpiryNotification.matches(initial.identifier))
MedtrumExpiryNotification.schedule(initial, enabled: true)
precondition(center.pending[key]?.trigger?.timeInterval == .hours(72))
MedtrumExpiryNotification.schedule(later, enabled: true)
precondition(center.pending.count == 1 && center.pending[key]?.trigger?.timeInterval == .hours(48))
MedtrumExpiryNotification.cancel()
precondition(center.pending.isEmpty)
MedtrumExpiryNotification.schedule(overdue, enabled: true)
precondition(center.pending[key] != nil && center.pending[key]?.trigger == nil)
MedtrumExpiryNotification.schedule(initial, enabled: false)
precondition(center.pending.isEmpty)
print("Trio notification adapter passed: deferred, replaced, cancelled, overdue, disabled")
'''.replace('ADAPTER', adapter)
with tempfile.TemporaryDirectory(prefix='medtrum-reminder-') as directory:
    swift = Path(directory) / 'main.swift'
    swift.write_text(alert + '\n' + time + '\n' + source + '\n' + checks)
    subprocess.run(['swift', '-module-cache-path', directory + '/module-cache', str(swift)], check=True)
