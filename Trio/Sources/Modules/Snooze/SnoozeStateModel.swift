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
        @ObservationIgnored private var displayedSharedSnooze = Date.distantPast

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

        @MainActor func refreshPresentation() {
            let date = Date()
            let glucose = TrioAlertManager.shared.currentAlarmStatus
            let deadline = glucose?.snoozeUntil ?? .distantPast
            let sharedSnooze = snoozeUntilDate
            let missing = MissingDataAlarmManager.shared.currentAlarmStatus(for: alertingIDs, now: date)
            // The UI shows deadlines, not a seconds countdown. Only invalidate it
            // when a displayed value changes or a snooze crosses its deadline.
            guard alarm != glucose?.kind || alarmSnoozeUntil != deadline ||
                displayedSharedSnooze != sharedSnooze ||
                (alarmSnoozeUntil > now) != (deadline > date) ||
                (displayedSharedSnooze > now) != (sharedSnooze > date) ||
                missedReadings != missing.missedReadings || missedLoop != missing.missedLoop
            else { return }
            now = date
            displayedSharedSnooze = sharedSnooze
            alarm = glucose?.kind
            alarmSnoozeUntil = deadline
            missedReadings = missing.missedReadings
            missedLoop = missing.missedLoop
        }

        @MainActor func observeMissingAlarms() async {
            guard !Task.isCancelled else { return }
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
