import AudioToolbox
import Combine
import CoreData
import Foundation
import LoopKit
import SwiftUI
import Swinject
import UIKit
import UserNotifications

protocol UserNotificationsManager {}

enum GlucoseSourceKey: String {
    case transmitterBattery
    case nightscoutPing
    case description
}

enum NotificationAction: String {
    static let key = "action"

    case snooze
    case pumpConfig
    case none
}

protocol BolusFailureObserver {
    func bolusDidFail()
}

protocol alertMessageNotificationObserver {
    func alertMessageNotification(_ message: MessageContent)
}

protocol pumpNotificationObserver {
    func pumpNotification(alert: AlertEntry)
    func pumpRemoveNotification()
}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    public enum Identifier: String {
        case glucoseNotification = "Trio.glucoseNotification"
        case carbsRequiredNotification = "Trio.carbsRequiredNotification"
        case noLoopFirstNotification = "Trio.noLoopFirstNotification"
        case noLoopSecondNotification = "Trio.noLoopSecondNotification"
        case bolusFailedNotification = "Trio.bolusFailedNotification"
        case trioRemoteLocalNotification = "FreeAPS.trioRemoteLocalNotification"
        case pumpNotification = "Trio.pumpNotification"
        case alertMessageNotification = "Trio.alertMessageNotification"
    }

    @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var router: Router!
    @Injected() private var nightscout: NightscoutManager!

    @Injected(as: FetchGlucoseManager.self) private var sourceInfoProvider: SourceInfoProvider!

    @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast

    private let center = UNUserNotificationCenter.current()
    private var lifetime = Lifetime()

    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseUserNotificationsManager.queue", qos: .userInitiated)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    @MainActor private var glucoseUpdateRunning = false
    @MainActor private var glucoseUpdatePending = false
    @MainActor private var notificationPending = false
    @MainActor private var lastBadgePreferences: String?

    private var firstInterval: Int { MissingDataAlarmConfiguration.savedLoop.intervals.first! }
    private var secondInterval: Int { MissingDataAlarmConfiguration.savedLoop.intervals.last! }
    @MainActor private var lastMissingLoopPlan: String?

    init(resolver: Resolver) {
        super.init()
        center.delegate = self
        Task { @MainActor in _ = TrioAlertManager.shared }
        injectServices(resolver)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        broadcaster.register(SettingsObserver.self, observer: self)
        broadcaster.register(DeterminationObserver.self, observer: self)
        broadcaster.register(BolusFailureObserver.self, observer: self)
        broadcaster.register(pumpNotificationObserver.self, observer: self)
        broadcaster.register(alertMessageNotificationObserver.self, observer: self)
        requestNotificationPermissionsIfNeeded()
        Task {
            await sendGlucoseNotification()
        }
        registerHandlers()
        registerSubscribers()
        subscribeOnLoop()
    }

    private func subscribeOnLoop() {
        apsManager.lastLoopDateSubject
            .sink { [weak self] date in
                Task { @MainActor in self?.scheduleMissingLoopNotifications(date: date) }
            }
            .store(in: &lifetime)
        Foundation.NotificationCenter.default.publisher(for: GlucoseAlarmPreferences.changed)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.scheduleMissingLoopNotifications(date: self.apsManager.lastLoopDate)
                }
            }.store(in: &lifetime)
        Task { @MainActor in self.scheduleMissingLoopNotifications(date: self.apsManager.lastLoopDate) }
    }

    private func registerHandlers() {
        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.sendGlucoseNotification()
            }
        }.store(in: &subscriptions)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.sendGlucoseNotification()
                }
            }
            .store(in: &subscriptions)
        Foundation.NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.sendGlucoseNotification(updateNotification: false)
                }
            }
            .store(in: &subscriptions)
    }

    @MainActor private func refreshBadgePreferences() async {
        let settings = settingsManager.settings
        let key = "\(settings.glucoseBadge)-\(settings.units.rawValue)"
        guard key != lastBadgePreferences else { return }
        lastBadgePreferences = key
        await sendGlucoseNotification(updateNotification: false)
    }

    @MainActor private func addAppBadge(glucose: Int?, date _: Date?) async {
        let badge: Int
        if let glucose, settingsManager.settings.glucoseBadge {
            badge = settingsManager.settings.units == .mmolL
                ? Int(round(Double((glucose * 10).asMmolL))) : glucose
        } else {
            badge = 0
        }
        do {
            // Wait for iOS before releasing background time or starting the next update.
            try await center.setBadgeCount(badge)
            // debug(.service, "Glucose badge updated: count=\(badge), reading=\(String(describing: date))")
        } catch {
            warning(.service, "Glucose badge failed: count=\(badge), error=\(error)")
        }
    }

    private func notifyCarbsRequired(_ carbs: Int) {
        guard Decimal(carbs) >= settingsManager.settings.carbsRequiredThreshold,
              settingsManager.settings.showCarbsRequiredBadge, settingsManager.settings.notificationsCarb else { return }

        var titles: [String] = []

        let content = UNMutableNotificationContent()

        if snoozeUntilDate > Date() {
            return
        }
        content.sound = .default
        playSoundIfNeeded()

        titles.append(String(format: NSLocalizedString("Carbs required: %d g", comment: "Carbs required"), carbs))

        content.title = titles.joined(separator: " ")
        content.body = String(
            format: NSLocalizedString(
                "To prevent LOW required %d g of carbs",
                comment: "To prevent LOW required %d g of carbs"
            ),
            carbs
        )
        addRequest(
            identifier: Identifier.carbsRequiredNotification.rawValue,
            content: content,
            deleteOld: true,
            messageSubtype: .carb
        )
    }

    @MainActor private func scheduleMissingLoopNotifications(date: Date) {
        guard date > .distantPast, date <= Date() else { return }
        let firstInterval = self.firstInterval
        let secondInterval = self.secondInterval
        let plan = "\(date.timeIntervalSince1970)-\(firstInterval)-\(secondInterval)"
        guard plan != lastMissingLoopPlan else { return }
        lastMissingLoopPlan = plan
        let title = NSLocalizedString("Trio Not Active", comment: "Trio Not Active")
        let body = NSLocalizedString("Last loop was more than %d min ago", comment: "Last loop was more than %d min ago")

        let firstContent = UNMutableNotificationContent()
        firstContent.title = title
        firstContent.body = String(format: body, firstInterval)
        firstContent.sound = .default

        let secondContent = UNMutableNotificationContent()
        secondContent.title = title
        secondContent.body = String(format: body, secondInterval)
        secondContent.sound = .default

        let firstTrigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.addingTimeInterval(60 * TimeInterval(firstInterval)).timeIntervalSinceNow),
            repeats: false
        )
        let secondTrigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.addingTimeInterval(60 * TimeInterval(secondInterval)).timeIntervalSinceNow),
            repeats: false
        )

        addRequest(
            identifier: Identifier.noLoopFirstNotification.rawValue,
            content: firstContent,
            deleteOld: true,
            trigger: firstTrigger,
            messageType: .error,
            messageSubtype: .algorithm
        )
        if firstInterval == secondInterval {
            center.removePendingNotificationRequests(withIdentifiers: [Identifier.noLoopSecondNotification.rawValue])
            center.removeDeliveredNotifications(withIdentifiers: [Identifier.noLoopSecondNotification.rawValue])
            return
        }
        addRequest(
            identifier: Identifier.noLoopSecondNotification.rawValue,
            content: secondContent,
            deleteOld: true,
            trigger: secondTrigger,
            messageType: .error,
            messageSubtype: .algorithm
        )
    }

    private func notifyBolusFailure() {
        let title = NSLocalizedString("Bolus failed", comment: "Bolus failed")
        let body = NSLocalizedString(
            "Bolus failed or inaccurate. Check pump history before repeating.",
            comment: "Bolus failed or inaccurate. Check pump history before repeating."
        )
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        addRequest(
            identifier: Identifier.bolusFailedNotification.rawValue,
            content: content,
            deleteOld: true,
            trigger: nil,
            messageType: .error,
            messageSubtype: .pump
        )
    }

    private struct GlucoseNotificationReading: Sendable {
        let glucose: Int
        let date: Date?
        let direction: String?
    }

    private func fetchGlucoseReadings() async throws -> [GlucoseNotificationReading] {
        try await backgroundContext.perform {
            let request = GlucoseStored.fetchRequest()
            request.predicate = NSPredicate.predicateFor20MinAgo
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 3
            request.shouldRefreshRefetchedObjects = true
            // Read scalar values on the fetching context; no dependency on viewContext history merges.
            return try self.backgroundContext.fetch(request).map {
                GlucoseNotificationReading(glucose: Int($0.glucose), date: $0.date, direction: $0.directionEnum?.symbol)
            }
        }
    }

    @MainActor private func sendGlucoseNotification(updateNotification: Bool = true) async {
        glucoseUpdatePending = true
        notificationPending = notificationPending || updateNotification
        guard !glucoseUpdateRunning else { return }
        glucoseUpdateRunning = true
        // debug(.service, "Glucose badge refresh started: appState=\(UIApplication.shared.applicationState.rawValue)")
        let backgroundTask = GlucoseBadgeBackgroundTask()
        defer {
            backgroundTask.end()
            glucoseUpdateRunning = false
        }
        // Coalesce concurrent save/deletion/foreground events and serialize badge writes.
        while glucoseUpdatePending {
            glucoseUpdatePending = false
            let shouldNotify = notificationPending
            notificationPending = false
            await updateGlucoseNotification(updateNotification: shouldNotify)
        }
    }

    @MainActor private func updateGlucoseNotification(updateNotification: Bool) async {
        do {
            let readings = try await fetchGlucoseReadings()
            let latest = readings.first
            // Do not clear before fetching: errors must not erase a previously valid badge.
            await addAppBadge(glucose: latest?.glucose, date: latest?.date)
            guard updateNotification, let lastReading = latest?.glucose else { return }
            let secondLastReading = readings.dropFirst().first?.glucose
            let lastDirection = latest?.direction
            // Informational glucose notifications are independent of low/high alarms.
            // Their existing preference still controls banners; TrioAlertManager owns alarm audio.

            var titles: [String] = []
            var notificationAlarm = false
            var messageType = MessageType.info

            switch glucoseStorage.alarm {
            case .none:
                titles.append(NSLocalizedString("Glucose", comment: "Glucose"))
            case .low:
                titles.append(NSLocalizedString("LOWALERT!", comment: "LOWALERT!"))
                messageType = MessageType.warning
                notificationAlarm = true
            case .high:
                titles.append(NSLocalizedString("HIGHALERT!", comment: "HIGHALERT!"))
                messageType = MessageType.warning
                notificationAlarm = true
            }

            let delta = secondLastReading.map { lastReading - $0 }
            let body = glucoseText(
                glucoseValue: Int(lastReading),
                delta: Int(delta ?? 0),
                direction: lastDirection
            ) + infoBody()

            if snoozeUntilDate > Date() {
                titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
                notificationAlarm = false
            } else {
                titles.append(body)
                let content = UNMutableNotificationContent()
                content.title = titles.joined(separator: " ")
                content.body = body

                if notificationAlarm {
                    // Low/high audio is owned by TrioAlertManager.
                    content.userInfo[NotificationAction.key] = NotificationAction.snooze.rawValue
                }

                addRequest(
                    identifier: Identifier.glucoseNotification.rawValue, content: content,

                    deleteOld: true,
                    messageType: messageType,
                    messageSubtype: .glucose,
                    action: NotificationAction.snooze
                )
            }
        } catch {
            warning(.service, "Glucose badge/notification fetch failed: \(error)")
        }
    }

    private func glucoseText(glucoseValue: Int, delta: Int?, direction: String?) -> String {
        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)! + " " + NSLocalizedString(units.rawValue, comment: "units")
        let directionText = direction ?? "↔︎"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return glucoseText + " " + directionText + " " + deltaText
    }

    private func infoBody() -> String {
        var body = ""

        if settingsManager.settings.addSourceInfoToGlucoseNotifications,
           let info = sourceInfoProvider.sourceInfo()
        {
            // Description
            if let description = info[GlucoseSourceKey.description.rawValue] as? String {
                body.append("\n" + description)
            }

            // NS ping
            if let ping = info[GlucoseSourceKey.nightscoutPing.rawValue] as? TimeInterval {
                body.append(
                    "\n"
                        + String(
                            format: NSLocalizedString("Nightscout ping: %d ms", comment: "Nightscout ping"),
                            Int(ping * 1000)
                        )
                )
            }

            // Transmitter battery
            if let transmitterBattery = info[GlucoseSourceKey.transmitterBattery.rawValue] as? Int {
                body.append(
                    "\n"
                        + String(
                            format: NSLocalizedString("Transmitter: %@%%", comment: "Transmitter: %@%%"),
                            "\(transmitterBattery)"
                        )
                )
            }
        }
        return body
    }

    private func requestNotificationPermissionsIfNeeded() {
        center.getNotificationSettings { settings in
            debug(.service, "UNUserNotificationCenter.authorizationStatus: \(String(describing: settings.authorizationStatus))")
            if ![.authorized, .provisional].contains(settings.authorizationStatus) {
                self.requestNotificationPermissions()
            }
        }
    }

    private func requestNotificationPermissions() {
        debug(.service, "requestNotificationPermissions")
        center.requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if granted {
                debug(.service, "requestNotificationPermissions was granted")
            } else {
                warning(.service, "requestNotificationPermissions failed", error: error)
            }
        }
    }

    internal func addRequest(
        identifier: String,
        content: UNMutableNotificationContent,
        deleteOld: Bool = false,
        trigger: UNNotificationTrigger? = nil,
        messageType: MessageType = MessageType.other,
        messageSubtype: MessageSubtype = MessageSubtype.misc,
        action: NotificationAction = NotificationAction.none
    ) {
        let messageCont = MessageContent(
            content: content.body,
            type: messageType,
            subtype: messageSubtype,
            title: content.title,
            useAPN: false,
            trigger: trigger,
            action: action
        )

        if alertPermissionsChecker.notificationsDisabled {
            router.alertMessage.send(messageCont)
            return
        }

        guard router.allowNotify(messageCont, settingsManager.settings) else { return }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        if deleteOld {
            DispatchQueue.main.async {
                self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
                self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.center.add(request) { error in
                if let error = error {
                    warning(.service, "Unable to addNotificationRequest", error: error)
                    return
                }

                debug(.service, "Sending notification with identifier \(identifier)")
            }
        }
    }

    internal func addRequest(
        identifier: Identifier,
        content: UNMutableNotificationContent,
        deleteOld: Bool = false,
        trigger: UNNotificationTrigger? = nil,
        messageType: MessageType = MessageType.other,
        messageSubtype: MessageSubtype = MessageSubtype.misc,
        action: NotificationAction = NotificationAction.none
    ) {
        addRequest(
            identifier: identifier.rawValue,
            content: content,
            deleteOld: deleteOld,
            trigger: trigger,
            messageType: messageType,
            messageSubtype: messageSubtype,
            action: action
        )
    }

    /*
        internal func addRequest(
            identifier: String,
            content: UNMutableNotificationContent,
            deleteOld: Bool = false,
            trigger: UNNotificationTrigger? = nil,
            messageType: MessageType = MessageType.other,
            messageSubtype: MessageSubtype = MessageSubtype.misc,
            action: NotificationAction = NotificationAction.none
        ) {
            let messageCont = MessageContent(
                content: content.body,
                type: messageType,
                subtype: messageSubtype,
                title: content.title,
                useAPN: false,
                trigger: trigger,
                action: action
            )

            // Just use 'identifier' directly instead of 'identifier.rawValue'
            var alertIdentifier = identifier

            // If you used to write something like:
            //   if identifier == .pumpNotification { ... }
            // just switch to a string compare:
            if identifier == "pumpNotification" {
                // If you want to concatenate the notification body
                // (assuming content.body is a String):
                alertIdentifier += content.body
            } else if identifier == "alertMessageNotification" {
                // If your old code did something special for that case
                alertIdentifier += content.body
            }

            // remove old notifications if asked
            if deleteOld {
                DispatchQueue.main.async {
                    self.center.removeDeliveredNotifications(withIdentifiers: [alertIdentifier])
                    self.center.removePendingNotificationRequests(withIdentifiers: [alertIdentifier])
                }
            }
            /*
             var alertIdentifier = identifier.rawValue
             alertIdentifier = identifier == .pumpNotification ? alertIdentifier + content
                 .title : (identifier == .alertMessageNotification ? alertIdentifier + content.body : alertIdentifier)
             if deleteOld {
                 DispatchQueue.main.async {
                     self.center.removeDeliveredNotifications(withIdentifiers: [alertIdentifier])
                     self.center.removePendingNotificationRequests(withIdentifiers: [alertIdentifier])
                 }
             }
             */
            if alertPermissionsChecker.notificationsDisabled {
                router.alertMessage.send(messageCont)
                return
            }
            guard router.allowNotify(messageCont, settingsManager.settings) else { return }

            let request = UNNotificationRequest(identifier: alertIdentifier , content: content, trigger: trigger)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.center.add(request) { error in
                    if let error = error {
                        warning(.service, "Unable to addNotificationRequest", error: error)
                        return
                    }

                    debug(.service, "Sending \(identifier) notification for \(request.content.title)")
                }
            }
        }
     */

    private func playSoundIfNeeded() {
        guard settingsManager.settings.useAlarmSound, snoozeUntilDate < Date() else { return }
        Self.stopPlaying = false
        playSound()
    }

    static let soundID: UInt32 = 1336
    private static var stopPlaying = false

    private func playSound(times: Int = 1) {
        guard times > 0, !Self.stopPlaying else {
            return
        }

        AudioServicesPlaySystemSoundWithCompletion(Self.soundID) {
            self.playSound(times: times - 1)
        }
    }

    static func stopSound() {
        stopPlaying = true
        AudioServicesDisposeSystemSoundID(soundID)
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }
}

extension BaseUserNotificationsManager: alertMessageNotificationObserver {
    func alertMessageNotification(_ message: MessageContent) {
        let content = UNMutableNotificationContent()
        var identifier: Identifier = .alertMessageNotification

        if message.title == "" {
            switch message.type {
            case .info:
                content.title = NSLocalizedString("Info", comment: "Info title")
            case .warning:
                content.title = NSLocalizedString("Warning", comment: "Warning title")
            case .error:
                content.title = NSLocalizedString("Error", comment: "Error title")
            default:
                content.title = message.title
            }
        } else {
            content.title = message.title
        }
        switch message.subtype {
        case .pump:
            identifier = .pumpNotification
        case .carb:
            identifier = .carbsRequiredNotification
        case .glucose:
            identifier = .glucoseNotification
        case .algorithm:
            if message.trigger != nil {
                identifier = message.content.contains(String(firstInterval)) ? Identifier.noLoopFirstNotification : Identifier
                    .noLoopSecondNotification
            } else {
                identifier = Identifier.alertMessageNotification
            }
        default:
            identifier = .alertMessageNotification
        }
        switch message.action {
        case .snooze:
            content.userInfo[NotificationAction.key] = NotificationAction.snooze.rawValue
        case .pumpConfig:
            content.userInfo[NotificationAction.key] = NotificationAction.pumpConfig.rawValue
        default: break
        }

        content.body = NSLocalizedString(message.content, comment: "Info message")
        content.sound = .default
        addRequest(
            identifier: identifier.rawValue,
            content: content,
            deleteOld: true,
            trigger: message.trigger,
            messageType: message.type,
            messageSubtype: message.subtype,
            action: message.action
        )
    }
}

extension BaseUserNotificationsManager: pumpNotificationObserver {
    func pumpNotification(alert: AlertEntry) {
        let content = UNMutableNotificationContent()
        let alertUp = alert.alertIdentifier.uppercased()
        let typeMessage: MessageType
        if alertUp.contains("FAULT") || alertUp.contains("ERROR") {
            content.userInfo[NotificationAction.key] = NotificationAction.pumpConfig.rawValue
            typeMessage = .error
        } else {
            typeMessage = .warning
            guard settingsManager.settings.notificationsPump else { return }
        }
        content.title = alert.contentTitle ?? "Unknown"
        content.body = alert.contentBody ?? "Unknown"

        if typeMessage == .error {
            let errorNote = "⛔️ \(content.title) - \(content.body)"
            Task {
                await nightscout.uploadErrors(withNotes: errorNote)
            }
        }

        content.sound = .default
        addRequest(
            identifier: Identifier.pumpNotification.rawValue,
            content: content,
            deleteOld: true,
            trigger: nil,
            messageType: typeMessage,
            messageSubtype: .pump,
            action: .pumpConfig
        )
    }

    func pumpRemoveNotification() {
        let identifier: Identifier = .pumpNotification
        DispatchQueue.main.async {
            self.center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            self.center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }
    }
}

extension BaseUserNotificationsManager: DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination) {
        guard let carndRequired = determination.carbsReq else { return }
        notifyCarbsRequired(Int(carndRequired))
    }
}

extension BaseUserNotificationsManager: BolusFailureObserver {
    func bolusDidFail() {
        notifyBolusFailure()
    }
}

extension BaseUserNotificationsManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound, .list])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == TrioAlertManager.category,
           let id = UUID(uuidString: response.notification.request.identifier)
        {
            Task { @MainActor in
                TrioAlertManager.shared.acknowledge(id)
                completionHandler()
            }
            return
        }
        defer { completionHandler() }
        guard let actionRaw = response.notification.request.content.userInfo[NotificationAction.key] as? String,
              let action = NotificationAction(rawValue: actionRaw)
        else { return }

        switch action {
        case .snooze:
            router.mainModalScreen.send(.snooze)
        case .pumpConfig:
            let messageCont = MessageContent(
                content: response.notification.request.content.body,
                type: MessageType.other,
                subtype: .pump,
                useAPN: false,
                action: .pumpConfig
            )
            router.alertMessage.send(messageCont)
        default: break
        }
    }
}

extension BaseUserNotificationsManager: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        Task { @MainActor in await self.refreshBadgePreferences() }
    }
}

/// Covers the database read and awaited system badge write during a brief CGM wake.
@MainActor private final class GlucoseBadgeBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid
    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Glucose badge") { [weak self] in
            Task { @MainActor in
                warning(.service, "Glucose badge background time expired before update finished")
                self?.end()
            }
        }
        if id == .invalid { warning(.service, "Glucose badge background time unavailable") }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
