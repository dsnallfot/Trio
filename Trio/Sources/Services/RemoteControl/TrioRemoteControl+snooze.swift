import Foundation

extension TrioRemoteControl {
    @MainActor func handleSnoozeCommand(_ pushMessage: PushMessage) async {
        guard let duration = pushMessage.duration, (0 ... 480).contains(duration),
              pushMessage.timestamp.isFinite
        else {
            await logError(
                "Kommandot avvisades: snooze kräver en giltig tidsstämpel och duration mellan 0 och 480 minuter.",
                pushMessage: pushMessage
            )
            return
        }

        // Duration uses minutes like other remote commands. Delivery delay must not extend the pause.
        let snoozeUntil = Date(timeIntervalSince1970: pushMessage.timestamp + Double(duration) * 60)
        guard duration == 0 || snoozeUntil > Date() else {
            await logError("Kommandot avvisades: den begärda snoozetiden har redan löpt ut.", pushMessage: pushMessage)
            return
        }

        let key = remoteCommandDedupKey(for: pushMessage, scope: .snooze)
        guard beginRemoteCommandIfNotDuplicate(key) else { return }
        defer { finishRemoteCommandDedup(key) }

        // Install the observers even if this push is the first alarm-related action after launch.
        _ = TrioAlertManager.shared
        _ = MissingDataAlarmManager.shared
        let note: String
        if duration == 0 {
            // Match the local Snooze view: clear global and acknowledged-alarm pauses.
            TrioAlertManager.shared.cancelSnoozes()
            note = "Alla Trio snoozer avbrutna"
        } else {
            UserDefaults.standard.setValue(snoozeUntil, forKey: "UserNotificationsManager.snoozeUntilDate")
            BaseUserNotificationsManager.stopSound()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "sv_SE")
            formatter.dateFormat = "HH:mm"
            note = "Alla Trio larm snoozade till kl \(formatter.string(from: snoozeUntil))"
        }
        debug(.remoteControl, "\(note). \(pushMessage.humanReadableDescription())")
        await nightscoutManager.uploadNoteTreatment(note: note)
    }
}
