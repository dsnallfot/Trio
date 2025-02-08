import Foundation

extension TrioRemoteControl {
    func logError(_ errorMessage: String, pushMessage: PushMessage? = nil) async {
        var note = errorMessage
        if let pushMessage = pushMessage {
            note += " Details: \(pushMessage.humanReadableDescription())"
        }
        debug(.remoteControl, note)
        await nightscoutManager.uploadNoteTreatment(note: note)

        // Send local notification
        notificationManager.notifyTrioRemoteControl(title: "Remote misslyckades ❌", body: note)
    }
}
