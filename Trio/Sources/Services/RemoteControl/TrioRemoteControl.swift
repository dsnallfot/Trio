import CoreData
import Foundation
import Swinject
import UserNotifications

class TrioRemoteControl: Injectable {
    static var pendingRemoteBolusNote: (note: String, timestamp: Date)?
    static let shared = TrioRemoteControl()

    @Injected() internal var tempTargetsStorage: TempTargetsStorage!
    @Injected() internal var carbsStorage: CarbsStorage!
    @Injected() internal var nightscoutManager: NightscoutManager!
    @Injected() internal var overrideStorage: OverrideStorage!
    @Injected() internal var settings: SettingsManager!
    @Injected() public var notificationManager: BaseUserNotificationsManager!

    private let timeWindow: TimeInterval = 300 // Defines how old messages that are accepted, 5 minutes

    internal let pumpHistoryFetchContext: NSManagedObjectContext
    internal let viewContext: NSManagedObjectContext

    private init() {
        pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        viewContext = CoreDataStack.shared.persistentContainer.viewContext
        injectServices(TrioApp.resolver)

        // Validera att notificationshanteraren är injicerad
        assert(notificationManager != nil, "NotificationManager är inte injicerad. Kontrollera Swinject-registrering.")
    }

    func handleRemoteNotification(pushMessage: PushMessage) async {
        let isTrioRemoteControlEnabled = UserDefaults.standard.bool(forKey: "isTrioRemoteControlEnabled")
        guard isTrioRemoteControlEnabled else {
            await logError("Fjärrkommando mottogs, men fjärrkontroll är inaktiverad i inställningarna. Kommandot ignoreras.")
            return
        }

        let currentTime = Date().timeIntervalSince1970
        let timeDifference = currentTime - pushMessage.timestamp

        if timeDifference > timeWindow {
            await logError(
                "Kommandot avvisades: meddelandet är för gammalt (skickades för \(Int(timeDifference)) sekunder sedan, vilket överskrider den tillåtna gränsen).",
                pushMessage: pushMessage
            )
            return
        } else if timeDifference < -timeWindow {
            await logError(
                "Kommandot avvisades: meddelandet har en ogiltig framtida tidsstämpel (tidsstämpeln är \(Int(-timeDifference)) sekunder före aktuell tid).",
                pushMessage: pushMessage
            )
            return
        }

        debug(.remoteControl, "Kommando mottogs med acceptabel tidsdifferens: \(Int(timeDifference)) sekunder.")

        let storedSecret = UserDefaults.standard.string(forKey: "trioRemoteControlSharedSecret") ?? ""
        guard !storedSecret.isEmpty else {
            await logError(
                "Kommandot avvisades: delad hemlighet saknas i inställningarna. Kommandot kan inte autentiseras.",
                pushMessage: pushMessage
            )
            return
        }

        guard pushMessage.sharedSecret == storedSecret else {
            await logError(
                "Kommandot avvisades: delad hemlighet matchar inte. Kommandot kan inte autentiseras.",
                pushMessage: pushMessage
            )
            return
        }

        switch pushMessage.commandType {
        case .bolus:
            await handleBolusCommand(pushMessage)
        case .tempTarget:
            await handleTempTargetCommand(pushMessage)
        case .cancelTempTarget:
            await cancelTempTarget(pushMessage)
        case .meal:
            // Execute meal command first.
            await handleMealCommand(pushMessage)
            // Then execute the bolus command.
            if pushMessage.bolusAmount != nil {
                await handleBolusCommand(pushMessage)
            }

        case .combo:
            await handleMealCommand(pushMessage)

            if let overrideName = pushMessage.overrideName,
               !overrideName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                await handleStartOverrideCommand(pushMessage)
            }

            if pushMessage.bolusAmount != nil {
                await handleBolusCommand(pushMessage)
            }
        case .startOverride:
            await handleStartOverrideCommand(pushMessage)
        case .cancelOverride:
            await handleCancelOverrideCommand(pushMessage)
        }
    }
}

// MARK: - CommandType Enum

extension TrioRemoteControl {
    enum CommandType: String, Codable {
        case bolus
        case tempTarget = "temp_target"
        case cancelTempTarget = "cancel_temp_target"
        case meal
        case combo
        case startOverride = "start_override"
        case cancelOverride = "cancel_override"

        var description: String {
            switch self {
            case .bolus:
                return "Bolus"
            case .tempTarget:
                return "Temporärt mål"
            case .cancelTempTarget:
                return "Avbryt temporärt mål"
            case .meal:
                return "Måltid"
            case .combo:
                return "Kombination"
            case .startOverride:
                return "Starta Override"
            case .cancelOverride:
                return "Avbryt Override"
            }
        }
    }
}

extension BaseUserNotificationsManager {
    func notifyTrioRemoteControl(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Create a unique identifier based on the title
        let identifier = "FreeAPS.trioRemote.\(title.replacingOccurrences(of: " ", with: "").lowercased())"

        addRequest(
            identifier: identifier,
            content: content,
            deleteOld: false
        )
    }
}
