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
    func retractAlert(identifier: Alert.Identifier) { retracted.append(identifier) }
    func issueAlert(_ alert: Alert) { issued.append(alert) }
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
precondition(pump.pumpDelegate.issuer.retracted.count == 1)
let scheduled = pump.pumpDelegate.issuer.issued.last!
if case let .delayed(interval) = scheduled.trigger {
    precondition(abs(interval - .hours(48)) < 5)
} else { preconditionFailure("Expected delay until original activation + 72 hours") }
pump.state.expiryMode = .extended
reschedule(pump)
pump.state.expiryMode = .default
pump.state.patchActivatedAt = nil
reschedule(pump)
pump.state.patchActivatedAt = Date()
pump.state.patchId = Data()
reschedule(pump)
precondition(pump.pumpDelegate.issuer.issued.count == 1)
precondition(pump.pumpDelegate.issuer.retracted.count == 4)
print("Medtrum reminder passed: 72-hour conversion, repeated saves, due/overdue triggers, remaining-time text")
'''.replace('RESCHEDULE', reschedule)
with tempfile.TemporaryDirectory(prefix='medtrum-reminder-') as directory:
    swift = Path(directory) / 'main.swift'
    swift.write_text(alert + '\n' + time + '\n' + source + '\n' + checks)
    subprocess.run(['swift', '-module-cache-path', directory + '/module-cache', str(swift)], check=True)
