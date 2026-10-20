import AlarmKit
import Observation
import SwiftUI

extension Snooze {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
        var alarm: GlucoseAlarmState.Kind?
        var alarmSnoozeUntil = Date.distantPast
        var now = Date()
        var missedReadings = false
        var missedLoop = false
        @ObservationIgnored private var alertingIDs: Set<UUID> = []

        @MainActor func cancelSnoozes() {
            TrioAlertManager.shared.cancelSnoozes()
            refreshPresentation()
        }

        @MainActor func observePresentation() async {
            while !Task.isCancelled {
                refreshPresentation()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }

        @MainActor private func refreshPresentation() {
            now = Date()
            let glucose = TrioAlertManager.shared.currentAlarmStatus
            alarm = glucose?.kind
            alarmSnoozeUntil = glucose?.snoozeUntil ?? .distantPast
            let missing = MissingDataAlarmManager.shared.currentAlarmStatus(for: alertingIDs, now: now)
            missedReadings = missing.missedReadings
            missedLoop = missing.missedLoop
        }

        @MainActor func observeMissingAlarms() async {
            updateMissingAlarms((try? AlarmManager.shared.alarms) ?? [])
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard !Task.isCancelled else { return }
                updateMissingAlarms(alarms)
            }
        }

        @MainActor private func updateMissingAlarms(_ alarms: [Alarm]) {
            alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
            refreshPresentation()
        }
    }
}
