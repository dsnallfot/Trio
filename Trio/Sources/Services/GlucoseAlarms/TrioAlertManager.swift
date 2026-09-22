import ActivityKit
import AlarmKit
import AppIntents
import Combine
import CoreData
import Foundation
import SwiftUI
import UserNotifications

/// Owns only low/high glucose alarms. Existing remote, pump and algorithm notifications stay independent.
@MainActor final class TrioAlertManager: ObservableObject {
    static let shared = TrioAlertManager()
    nonisolated static let category = "Trio.glucoseAlarm"
    private static let stateKey = "Trio.glucoseAlarms.state.v1"
    private static let alarmIDsKey = "Trio.glucoseAlarms.systemIDs.v1"
    private let center = UNUserNotificationCenter.current()
    private let context = CoreDataStack.shared.newTaskContext()
    private let settings = TrioApp.resolver.resolve(SettingsManager.self)!
    private let preferences = GlucoseAlarmPreferences.shared
    private var subscriptions = Set<AnyCancellable>()
    private var state: GlucoseAlarmState
    private var systemIDs: Set<UUID>
    private var revision = 0
    private var lastAlarmKitChoice: Bool?
    @Published private(set) var testAlarmID: UUID?
    private var expirationTask: Task<Void, Never>?
    @Published private(set) var permissionText = ""
    @Published private(set) var deliveryError: String?
    @Published private(set) var notificationText = ""
    @Published private(set) var thresholdWarning: String?

    private init() {
        state = UserDefaults.standard.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(GlucoseAlarmState.self, from: $0) } ?? GlucoseAlarmState()
        systemIDs = Set((UserDefaults.standard.stringArray(forKey: Self.alarmIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
        // Clean up previously replaced alarms, including a schedule interrupted by process termination.
        for id in systemIDs where id != state.activeID { cancel(id) }
        Task {
            let categories = await center.notificationCategories()
            let snooze = UNNotificationAction(identifier: "snooze", title: "Pausa glukoslarm", options: [])
            let category = UNNotificationCategory(identifier: Self.category, actions: [snooze], intentIdentifiers: [])
            center.setNotificationCategories(categories.union([category]))
        }
        let storage = TrioApp.resolver.resolve(GlucoseStorage.self)!
        storage.updatePublisher.receive(on: DispatchQueue.main).sink { [weak self] in self?.evaluate() }
            .store(in: &subscriptions)
        for name in [
            GlucoseAlarmPreferences.changed,
            UserDefaults.didChangeNotification,
            UIApplication.didBecomeActiveNotification
        ] {
            Foundation.NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.evaluate() }.store(in: &subscriptions)
        }
        TrioApp.resolver.resolve(Broadcaster.self)!.register(SettingsObserver.self, observer: self)
        Task { [weak self] in
            for await _ in AlarmManager.shared.authorizationUpdates {
                guard let self else { return }
                self.updatePermission()
            }
        }
        updatePermission()
        evaluate()
    }

    func requestPermission() async {
        do { _ = try await AlarmManager.shared.requestAuthorization() }
        catch { deliveryError = "Kunde inte begära larmbehörighet: \(error.localizedDescription)" }
        updatePermission()
    }

    func updatePermission() {
        Task {
            let status = await center.notificationSettings()
            notificationText = status.authorizationStatus == .denied
                ?
                "Vanliga notiser är avstängda i iOS. De kan INTE användas som reserv om AlarmKit också är avstängt eller misslyckas."
                : ""
        }
        switch AlarmManager.shared.authorizationState {
        case .authorized: permissionText =
            "AlarmKit är tillåtet i iOS inställningar. Larmen kan höras genom tyst läge och Fokusläge."
        case .denied: permissionText =
            "AlarmKit är avstängt i iOS inställningar. Endast vanliga notiser används; de kan tystas av tyst läge och Fokusläge."
        case .notDetermined: permissionText =
            "Tillåt AlarmKit för ljud genom tyst läge och Fokusläge. Tills dess används vanliga notiser."
        @unknown default: permissionText = "AlarmKit är inte tillgängligt. Vanliga notiser används."
        }
    }

    func evaluate() {
        if let previous = lastAlarmKitChoice, previous != preferences.alarmKit, let id = state.activeID {
            state.activeID = nil
            cancel(id)
            persist()
        }
        lastAlarmKitChoice = preferences.alarmKit
        revision += 1
        let evaluation = revision
        Task {
            let backgroundTask = GlucoseAlarmBackgroundTask()
            defer { backgroundTask.end() }
            let reading = await context.perform { () -> GlucoseAlarmState.Reading? in
                let request = GlucoseStored.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                request.fetchLimit = 1
                do {
                    guard let row = try self.context.fetch(request).first, let date = row.date else { return nil }
                    return GlucoseAlarmState.Reading(date: date, mgdL: Decimal(row.glucose))
                } catch {
                    debug(.service, "Glucose alarm fetch failed: \(error)")
                    return nil
                }
            }
            guard evaluation == revision else { return }
            let now = Date()
            let snooze = UserDefaults.standard
                .getValue(Date.self, forKey: "UserNotificationsManager.snoozeUntilDate") ?? .distantPast
            thresholdWarning = settings.settings.lowGlucose >= settings.settings.highGlucose
                ?
                "Gränsen för lågt glukos måste vara lägre än gränsen för högt glukos. Larmen är pausade tills gränserna rättats."
                : nil
            let decision = state.evaluate(
                reading, low: settings.settings.lowGlucose, high: settings.settings.highGlucose,
                lowEnabled: preferences.lowEnabled, highEnabled: preferences.highEnabled, now: now, globalSnooze: snooze,
                urgentLow: preferences.urgentLowThreshold, urgentHigh: preferences.urgentHighThreshold,
                urgentLowEnabled: preferences.urgentLowEnabled, urgentHighEnabled: preferences.urgentHighEnabled
            )
            persist()
            if let id = decision.cancelled { cancel(id) }
            if let event = decision.issued { await deliver(event) }
            expirationTask?.cancel()
            if let reading = reading, now.timeIntervalSince(reading.date) < GlucoseAlarmState.freshness {
                let wakeDates = [
                    reading.date.addingTimeInterval(GlucoseAlarmState.freshness + 1),
                    max(state.snoozeDeadline(for: state.kind), snooze),
                    state.lastAlertAt?.addingTimeInterval(GlucoseAlarmState.repeatInterval) ?? .distantPast
                ].filter { $0 > Date() }
                if let next = wakeDates.min() { scheduleEvaluation(at: next) }
            }
        }
    }

    private func scheduleEvaluation(at date: Date) {
        let delay = max(1, date.timeIntervalSinceNow)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state), data != UserDefaults.standard.data(forKey: Self.stateKey) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
        let ids = systemIDs.map(\.uuidString).sorted()
        if ids != UserDefaults.standard.stringArray(forKey: Self.alarmIDsKey) {
            UserDefaults.standard.set(ids, forKey: Self.alarmIDsKey)
        }
    }

    func acknowledge(_ id: UUID) {
        guard let cancelled = state.acknowledge(
            id: id,
            now: Date(),
            snoozeMinutes: preferences.snoozeMinutes(for: state.kind)
        ) else { cancel(id)
            return }
        persist()
        cancel(cancelled)
        evaluate()
    }

    private func cancel(_ id: UUID) {
        if testAlarmID == id { testAlarmID = nil }
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        guard systemIDs.contains(id) else { return }
        try? AlarmManager.shared.stop(id: id)
        do {
            try AlarmManager.shared.cancel(id: id)
            systemIDs.remove(id)
        } catch {
            // A stopped/missing alarm needs no further cancellation. Retain IDs if enumeration fails.
            if let alarms = try? AlarmManager.shared.alarms, !alarms.contains(where: { $0.id == id }) { systemIDs.remove(id) }
        }
        persist()
    }

    /// Exercises the real AlarmKit channel without storing glucose or touching the loop.
    func testAlarm(tone: GlucoseAlarmPreferences.Tone) async {
        await requestPermission()
        guard AlarmManager.shared.authorizationState == .authorized else { return }
        cancelTestAlarm()
        let id = UUID()
        testAlarmID = id
        systemIDs.insert(id)
        persist()
        let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(
            title: "Test av glukoslarm",
            stopButton: AlarmButton(text: "Stoppa test", textColor: .white, systemImageName: "stop.circle")
        ))
        let config = AlarmManager.AlarmConfiguration<GlucoseAlarmMetadata>.alarm(
            schedule: .fixed(Date().addingTimeInterval(10)),
            attributes: AlarmAttributes<GlucoseAlarmMetadata>(presentation: presentation, tintColor: .blue),
            stopIntent: StopGlucoseAlarmIntent(id: id), sound: .named(tone.rawValue)
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
            if testAlarmID != id { systemIDs.insert(id)
                cancel(id) } else { deliveryError = nil }
        } catch {
            systemIDs.remove(id)
            if testAlarmID == id { testAlarmID = nil }
            persist()
            deliveryError = "Testlarmet kunde inte startas: \(error.localizedDescription)"
        }
    }

    func cancelTestAlarm() {
        if let id = testAlarmID { cancel(id) }
    }

    private func deliver(_ event: GlucoseAlarmState.Event) async {
        guard Date().timeIntervalSince(event.reading.date) <= GlucoseAlarmState.freshness else {
            evaluate()
            return
        }
        let tone = preferences.tone(for: event.kind)
        let value = settings.settings.units == .mmolL
        ? String(format: "%.1f mmol/L", NSDecimalNumber(decimal: event.reading.mgdL).doubleValue * 0.0555)
            : "\(event.reading.mgdL) mg/dL"
        let label: String
        switch event.kind {
        case .low: label = "Lågt"
        case .high: label = "Högt"
        case .urgentLow: label = "Akut lågt"
        case .urgentHigh: label = "Akut högt"
        }
        let title = "\(label) glukos: \(value)"
        let useAlarmKit = preferences.alarmKit && AlarmManager.shared.authorizationState == .authorized
        if useAlarmKit {
            systemIDs.insert(event.id)
            persist() // Before the asynchronous schedule, so relaunch can reconcile this ID.
            let presentation = AlarmPresentation(alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "Pausa larm", textColor: .white, systemImageName: "pause.circle")
            ))
            let attributes = AlarmAttributes<GlucoseAlarmMetadata>(presentation: presentation, tintColor: .red)
            let config = AlarmManager.AlarmConfiguration<GlucoseAlarmMetadata>.alarm(
                schedule: .fixed(Date().addingTimeInterval(2)), attributes: attributes,
                stopIntent: StopGlucoseAlarmIntent(id: event.id), sound: .named(tone.rawValue)
            )
            do {
                _ = try await AlarmManager.shared.schedule(id: event.id, configuration: config)
                guard state.activeID == event.id else {
                    systemIDs.insert(event.id)
                    cancel(event.id)
                    return
                }
                deliveryError = nil
                debug(.service, "Glucose alarm scheduled: \(event.kind.rawValue), reading=\(event.reading.date)")
                return
            } catch {
                guard state.activeID == event.id else { cancel(event.id)
                    return }
                systemIDs.remove(event.id)
                persist()
                deliveryError = "AlarmKit kunde inte starta larmet. En vanlig notis används."
                debug(.service, "AlarmKit scheduling failed: \(error)")
            }
        }
        guard state.activeID == event.id else { return }
        let authorization = await center.notificationSettings()
        guard state.activeID == event.id else { return }
        if authorization.authorizationStatus == .denied {
            deliveryError = "Glukoslarmet kan inte levereras: tillåt AlarmKit eller notiser i iOS-inställningarna."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content
            .body =
            "Glukosvärde kl. \(event.reading.date.formatted(date: .omitted, time: .shortened)). Pausens längd väljs i glukoslarmens inställningar."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: tone.rawValue))
        content.categoryIdentifier = Self.category
        content.interruptionLevel = .timeSensitive
        do {
            try await center.add(UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil))
            if state.activeID != event.id { cancel(event.id) }
        } catch {
            deliveryError = "Glukosnotisen kunde inte levereras: \(error.localizedDescription)"
        }
    }
}

struct GlucoseAlarmMetadata: AlarmMetadata {}

/// System-only action: acknowledges the exact persisted event, including after relaunch.
struct StopGlucoseAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pausa glukoslarm"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Larm-ID") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { await TrioAlertManager.shared.acknowledge(id) }
        return .result()
    }
}

extension TrioAlertManager: SettingsObserver {
    nonisolated func settingsDidChange(_: TrioSettings) {
        Task { @MainActor in self.evaluate() }
    }
}

/// Keeps the short database-read / system-schedule transaction alive during a BLE wake.
@MainActor private final class GlucoseAlarmBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid
    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Glucose alarm") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
