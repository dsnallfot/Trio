import CoreData
import Foundation
import Swinject
import UserNotifications

class TrioRemoteControl: Injectable {
    static var pendingRemoteBolusNote: (note: String, timestamp: Date)?
    static let shared = TrioRemoteControl()

    @Injected() internal var tempTargetsStorage: TempTargetsStorage!
    @Injected() internal var carbsStorage: CarbsStorage!
    @Injected() internal var glucoseStorage: GlucoseStorage!
    @Injected() internal var nightscoutManager: NightscoutManager!
    @Injected() internal var overrideStorage: OverrideStorage!
    @Injected() internal var settings: SettingsManager!
    @Injected() public var notificationManager: BaseUserNotificationsManager!

    private let timeWindow: TimeInterval = 300 // Defines how old messages that are accepted, 5 minutes

    private static var pendingRemoteCommandKeys = Set<String>()
    private static var processedRemoteCommandKeys = [String: Date]()
    private static let remoteCommandDedupQueue = DispatchQueue(label: "TrioRemoteControl.remoteCommandDedup")
    private static let remoteCommandDedupRetention: TimeInterval = 10 * 60

    private static let pendingRemoteCommandsUserDefaultsKey = "TrioRemoteControl.pendingRemoteCommands.v1"
    private static let pendingRemoteCommandsQueue = DispatchQueue(label: "TrioRemoteControl.pendingRemoteCommands")
    private static let pendingRemoteCommandMaxAge: TimeInterval = 30 * 60

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
            if pushMessage.bolusAmount != nil {
                persistPendingRemoteCommandIfNeeded(for: pushMessage)
                await handleBolusCommand(pushMessage)
            }

            await handleMealCommand(pushMessage)
            markPendingRemoteCommandMealHandled(for: pushMessage)
            clearPendingRemoteCommandIfCompleted(for: pushMessage)
        case .deleteMeal:
            await handleDeleteMealCommand(pushMessage)

        case .combo:
            persistPendingRemoteCommandIfNeeded(for: pushMessage)

            if pushMessage.bolusAmount != nil {
                await handleBolusCommand(pushMessage)
            }

            await handleMealCommand(pushMessage)
            markPendingRemoteCommandMealHandled(for: pushMessage)

            if let overrideName = pushMessage.overrideName,
               !overrideName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                await handleStartOverrideCommand(pushMessage)
                markPendingRemoteCommandOverrideHandled(for: pushMessage)
            }

            clearPendingRemoteCommandIfCompleted(for: pushMessage)
        case .startOverride:
            await handleStartOverrideCommand(pushMessage)
        case .cancelOverride:
            await handleCancelOverrideCommand(pushMessage)
        case .glucose:
            await handleGlucoseCommand(pushMessage)
        }
    }

    internal func remoteCommandDedupKey(for pushMessage: PushMessage, scope: CommandType) -> String {
        let scopeValue = scope.rawValue
        let user = pushMessage.user
        let timestamp = String(format: "%.3f", pushMessage.timestamp)

        let scheduledTime: String
        if let scheduledTimeValue = pushMessage.scheduledTime {
            scheduledTime = String(format: "%.3f", scheduledTimeValue)
        } else {
            scheduledTime = "nil"
        }

        let bolusAmount: String
        if let bolusAmountValue = pushMessage.bolusAmount {
            bolusAmount = NSDecimalNumber(decimal: bolusAmountValue).stringValue
        } else {
            bolusAmount = "nil"
        }

        let glucose: String
        if let glucoseValue = pushMessage.glucose {
            glucose = NSDecimalNumber(decimal: glucoseValue).stringValue
        } else {
            glucose = "nil"
        }

        let carbs: String
        if let carbsValue = pushMessage.carbs {
            carbs = String(carbsValue)
        } else {
            carbs = "nil"
        }

        let fat: String
        if let fatValue = pushMessage.fat {
            fat = String(fatValue)
        } else {
            fat = "nil"
        }

        let protein: String
        if let proteinValue = pushMessage.protein {
            protein = String(proteinValue)
        } else {
            protein = "nil"
        }

        let target: String
        if let targetValue = pushMessage.target {
            target = String(targetValue)
        } else {
            target = "nil"
        }

        let duration: String
        if let durationValue = pushMessage.duration {
            duration = String(durationValue)
        } else {
            duration = "nil"
        }

        let overrideName = pushMessage.overrideName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = pushMessage.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let keyParts: [String] = [
            scopeValue,
            user,
            timestamp,
            scheduledTime,
            bolusAmount,
            glucose,
            carbs,
            fat,
            protein,
            target,
            duration,
            overrideName,
            notes
        ]

        return keyParts.joined(separator: "|")
    }

    internal func beginRemoteCommandIfNotDuplicate(_ key: String) -> Bool {
        Self.remoteCommandDedupQueue.sync {
            let now = Date()
            Self.processedRemoteCommandKeys = Self.processedRemoteCommandKeys.filter {
                now.timeIntervalSince($0.value) <= Self.remoteCommandDedupRetention
            }

            if Self.pendingRemoteCommandKeys.contains(key) || Self.processedRemoteCommandKeys[key] != nil {
                return false
            }

            Self.pendingRemoteCommandKeys.insert(key)
            return true
        }
    }

    internal func finishRemoteCommandDedup(_ key: String) {
        Self.remoteCommandDedupQueue.sync {
            Self.pendingRemoteCommandKeys.remove(key)
            Self.processedRemoteCommandKeys[key] = Date()
        }
    }

    internal func cancelRemoteCommandDedup(_ key: String) {
        Self.remoteCommandDedupQueue.sync {
            Self.pendingRemoteCommandKeys.remove(key)
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
        case deleteMeal
        case combo
        case startOverride = "start_override"
        case cancelOverride = "cancel_override"
        case glucose

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
            case .deleteMeal:
                return "Radera Måltid"
            case .combo:
                return "Kombination"
            case .startOverride:
                return "Starta Override"
            case .cancelOverride:
                return "Avbryt Override"
            case .glucose:
                return "Blodsocker"
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

// MARK: - Remote Command Recovery

extension TrioRemoteControl {
    private struct PendingRemoteCommand: Codable {
        let id: String
        let pushMessage: PushMessage
        var mealHandled: Bool
        var overrideHandled: Bool
        let createdAt: Date

        var containsMeal: Bool {
            pushMessage.carbs != nil || pushMessage.fat != nil || pushMessage.protein != nil
        }

        var containsOverride: Bool {
            guard let overrideName = pushMessage.overrideName else { return false }
            return !overrideName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var isCompleted: Bool {
            (!containsMeal || mealHandled) && (!containsOverride || overrideHandled)
        }
    }

    private func remoteRecoveryID(for pushMessage: PushMessage) -> String {
        remoteCommandDedupKey(for: pushMessage, scope: pushMessage.commandType)
    }

    private func loadPendingRemoteCommands() -> [PendingRemoteCommand] {
        Self.pendingRemoteCommandsQueue.sync {
            guard let data = UserDefaults.standard.data(forKey: Self.pendingRemoteCommandsUserDefaultsKey) else {
                return []
            }

            do {
                return try JSONDecoder().decode([PendingRemoteCommand].self, from: data)
            } catch {
                debug(.remoteControl, "Kunde inte läsa pending remote commands: \(error.localizedDescription)")
                UserDefaults.standard.removeObject(forKey: Self.pendingRemoteCommandsUserDefaultsKey)
                return []
            }
        }
    }

    private func savePendingRemoteCommands(_ commands: [PendingRemoteCommand]) {
        Self.pendingRemoteCommandsQueue.sync {
            do {
                let data = try JSONEncoder().encode(commands)
                UserDefaults.standard.set(data, forKey: Self.pendingRemoteCommandsUserDefaultsKey)
            } catch {
                debug(.remoteControl, "Kunde inte spara pending remote commands: \(error.localizedDescription)")
            }
        }
    }

    private func persistPendingRemoteCommandIfNeeded(for pushMessage: PushMessage) {
        let containsMeal = pushMessage.carbs != nil || pushMessage.fat != nil || pushMessage.protein != nil
        let containsOverride = pushMessage.overrideName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        guard containsMeal || containsOverride else { return }

        let id = remoteRecoveryID(for: pushMessage)
        var commands = loadPendingRemoteCommands()

        let now = Date()
        commands = commands.filter { now.timeIntervalSince($0.createdAt) <= Self.pendingRemoteCommandMaxAge }

        guard !commands.contains(where: { $0.id == id }) else { return }

        commands.append(
            PendingRemoteCommand(
                id: id,
                pushMessage: pushMessage,
                mealHandled: !containsMeal,
                overrideHandled: !containsOverride,
                createdAt: now
            )
        )

        savePendingRemoteCommands(commands)
        debug(.remoteControl, "Sparade remote command för recovery. \(pushMessage.humanReadableDescription())")
    }

    private func markPendingRemoteCommandMealHandled(for pushMessage: PushMessage) {
        let id = remoteRecoveryID(for: pushMessage)
        var commands = loadPendingRemoteCommands()

        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[index].mealHandled = true
        savePendingRemoteCommands(commands)
    }

    private func markPendingRemoteCommandOverrideHandled(for pushMessage: PushMessage) {
        let id = remoteRecoveryID(for: pushMessage)
        var commands = loadPendingRemoteCommands()

        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[index].overrideHandled = true
        savePendingRemoteCommands(commands)
    }

    private func clearPendingRemoteCommandIfCompleted(for pushMessage: PushMessage) {
        let id = remoteRecoveryID(for: pushMessage)
        var commands = loadPendingRemoteCommands()

        guard let command = commands.first(where: { $0.id == id }), command.isCompleted else { return }
        commands.removeAll { $0.id == id }
        savePendingRemoteCommands(commands)
        debug(.remoteControl, "Rensade färdigbehandlad remote command från recovery. \(pushMessage.humanReadableDescription())")
    }

    func resumePendingRemoteCommands() async {
        let now = Date()
        let commandsToResume = loadPendingRemoteCommands().filter {
            now.timeIntervalSince($0.createdAt) <= Self.pendingRemoteCommandMaxAge
        }

        savePendingRemoteCommands(commandsToResume)

        guard !commandsToResume.isEmpty else { return }

        debug(.remoteControl, "Återupptar \(commandsToResume.count) pending remote command(s) efter omstart.")

        for command in commandsToResume {
            let pushMessage = command.pushMessage

            if command.containsMeal, !command.mealHandled {
                debug(.remoteControl, "Recovery kör måltidsdelen. \(pushMessage.humanReadableDescription())")
                await handleMealCommand(pushMessage)
                markPendingRemoteCommandMealHandled(for: pushMessage)
            }

            if command.containsOverride, !command.overrideHandled {
                debug(.remoteControl, "Recovery kör override-delen. \(pushMessage.humanReadableDescription())")
                await handleStartOverrideCommand(pushMessage)
                markPendingRemoteCommandOverrideHandled(for: pushMessage)
            }

            clearPendingRemoteCommandIfCompleted(for: pushMessage)
        }
    }
}
