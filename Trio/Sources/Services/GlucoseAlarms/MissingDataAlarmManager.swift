import AlarmKit
import AppIntents
import Combine
import CoreData
import SwiftUI

/// Arms future system alarms while Trio is awake. No timer or heartbeat is required at the deadline.
@MainActor final class MissingDataAlarmManager: ObservableObject {
    static let shared = MissingDataAlarmManager()
    private static let key = "Trio.missingDataAlarms.v1"
    private struct Saved: Codable {
        var glucose = MissingDataAlarmState()
        var loop = MissingDataAlarmState()
        var retired: Set<UUID> = []
    }

    private var saved: Saved
    private let context = CoreDataStack.shared.newTaskContext()
    private let preferences = GlucoseAlarmPreferences.shared
    private let aps = TrioApp.resolver.resolve(APSManager.self)!
    private var subscriptions = Set<AnyCancellable>()
    private var running = false
    private var pending = false
    @Published private(set) var errorText: String?

    private init() {
        saved = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
        TrioApp.resolver.resolve(GlucoseStorage.self)!.updatePublisher
            .receive(on: DispatchQueue.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        aps.lastLoopDateSubject.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        for name in [GlucoseAlarmPreferences.changed, UIApplication.didBecomeActiveNotification] {
            Foundation.NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        }
        Task { [weak self] in
            for await _ in AlarmManager.shared.authorizationUpdates { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        pending = true
        guard !running else { return }
        running = true
        Task {
            let lease = MissingAlarmBackgroundTask()
            defer { lease.end()
                running = false }
            while pending {
                pending = false
                await reconcile()
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    private func reconcile() async {
        errorText = nil
        let now = Date()
        do {
            let latest = try await context.perform { () -> Date? in
                let request = GlucoseStored.fetchRequest()
                request.predicate = NSPredicate(format: "glucose > 0 AND date <= %@", now as NSDate)
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                request.fetchLimit = 1
                return try self.context.fetch(request).first?.date
            }
            saved.retired.formUnion(saved.glucose.reconcile(latest: latest, config: preferences.missingGlucose, now: now))
        } catch {
            errorText = "Kunde inte läsa senaste glukosvärdet. Befintliga tidslarm behålls."
            warning(.service, "Missing glucose alarm fetch failed: \(error)")
            // Turning monitoring off must work even if the database is unavailable.
            if !preferences.missingGlucose.enabled {
                saved.retired.formUnion(saved.glucose.reconcile(latest: nil, config: preferences.missingGlucose, now: now))
            }
        }
        saved.retired.formUnion(saved.loop.reconcile(latest: aps.lastLoopDate, config: preferences.missingLoop, now: now))
        persist()
        for id in saved.retired { cancel(id) }
        guard AlarmManager.shared.authorizationState == .authorized else {
            if preferences.missingGlucose.enabled || preferences.missingLoop.enabled {
                errorText = "Tillåt AlarmKit i iOS för dessa tidslarm. Befintliga loopnotiser har separata notisinställningar."
            }
            return
        }
        do {
            let installed = Set(try AlarmManager.shared.alarms.map(\.id))
            for isGlucose in [true, false] {
                let slots = isGlucose ? saved.glucose.slots : saved.loop.slots

                let activePeriod: AlarmActivePeriod = isGlucose
                    ? preferences.missingGlucoseActivePeriod
                    : preferences.missingLoopActivePeriod

                for slot in slots where !slot.acknowledged {
                    // ------------------------------------------------------------
                    // Dag / natt
                    //
                    // Missing-data-larmen schemaläggs i förväg, så det är tiden
                    // då larmet faktiskt ska gå (slot.date) som ska testas.
                    //
                    // Exempel:
                    //
                    // Dagtid 07:00 -> 22:00
                    // Alarm = Dagtid
                    // slot.date = 22:15
                    //
                    // Då ska inget AlarmKit-larm finnas för denna slot.
                    // ------------------------------------------------------------
                    let allowedAtAlarmTime = preferences.isAllowed(
                        during: activePeriod,
                        at: slot.date
                    )

                    if !allowedAtAlarmTime {
                        // Om larmet redan hann schemaläggas innan användaren
                        // ändrade dag/natt-inställningen måste vi även ta bort
                        // det befintliga AlarmKit-larmet.
                        if installed.contains(slot.id) {
                            do {
                                try AlarmManager.shared.cancel(id: slot.id)
                            } catch {
                                warning(
                                    .service,
                                    "Could not cancel time-restricted missing-data alarm: \(slot.id), \(error)"
                                )
                            }
                        }

                        // Behåll sloten som oschemalagd.
                        //
                        // Det gör att en framtida ändring från exempelvis
                        // "Dagtid" till "Alltid" kan göra sloten aktuell igen.
                        setScheduled(slot.id, false)
                        persist()

                        continue
                    }

                    // Expired/stopped alarms stay consumed after relaunch;
                    // only missing future alarms are repaired.
                    guard !slot.scheduled ||
                        (slot.date > Date() && !installed.contains(slot.id))
                    else {
                        continue
                    }

                    let snapshot = isGlucose ? saved.glucose : saved.loop

                    if snapshot.supersededOverdue(slot, now: Date()) {
                        // Enabling/reconfiguring after both deadlines passed gives
                        // one immediate warning, not two.
                        setScheduled(slot.id, true)
                        persist()
                        continue
                    }

                    if pending {
                        return
                    }

                    let title = isGlucose
                        ? "Saknade glukosvärden"
                        : "Loopar inte"

                    let text = "\(title): \(slot.minutes) minuter"

                    let attributes = AlarmAttributes<GlucoseAlarmMetadata>(
                        presentation: AlarmPresentation(
                            alert: AlarmPresentation.Alert(
                                title: LocalizedStringResource(
                                    stringLiteral: text
                                ),
                                stopButton: AlarmButton(
                                    text: "Kvittera",
                                    textColor: .white,
                                    systemImageName: "checkmark.circle"
                                )
                            )
                        ),
                        tintColor: .orange
                    )

                    let configuration =
                        AlarmManager.AlarmConfiguration<GlucoseAlarmMetadata>.alarm(
                            schedule: .fixed(
                                max(
                                    slot.date,
                                    Date().addingTimeInterval(2)
                                )
                            ),
                            attributes: attributes,
                            stopIntent: StopMissingDataAlarmIntent(
                                id: slot.id
                            ),
                            sound: .named(slot.tone.rawValue)
                        )

                    // Persist ownership before suspension inside AlarmKit;
                    // a crash cannot orphan an unknown ID.
                    setScheduled(slot.id, true)
                    persist()

                    do {
                        _ = try await AlarmManager.shared.schedule(
                            id: slot.id,
                            configuration: configuration
                        )

                        if isAcknowledged(slot.id) {
                            saved.retired.insert(slot.id)
                            cancel(slot.id)
                        }

                        debug(
                            .service,
                            "Missing data alarm scheduled: \(title), deadline=\(slot.date), period=\(activePeriod.rawValue), id=\(slot.id)"
                        )
                    } catch {
                        setScheduled(slot.id, false)

                        errorText =
                            "Kunde inte schemalägga \(title): \(error.localizedDescription)"

                        warning(
                            .service,
                            "Missing data alarm schedule failed: \(error)"
                        )
                    }

                    persist()
                }
            }
        } catch {
            errorText = "Kunde inte kontrollera schemalagda tidslarm: \(error.localizedDescription)"
        }
    }

    private func setScheduled(_ id: UUID, _ scheduled: Bool) {
        if let i = saved.glucose.slots.firstIndex(where: { $0.id == id }) { saved.glucose.slots[i].scheduled = scheduled }
        if let i = saved.loop.slots.firstIndex(where: { $0.id == id }) { saved.loop.slots[i].scheduled = scheduled }
    }

    private func isAcknowledged(_ id: UUID) -> Bool {
        (saved.glucose.slots + saved.loop.slots).first { $0.id == id }?.acknowledged ?? true
    }

    func acknowledge(_ id: UUID) {
        _ = saved.glucose.acknowledge(id)
        _ = saved.loop.acknowledge(id)
        saved.retired.insert(id)
        persist()
        cancel(id)
        // The other deadline remains armed until a newer reading/successful loop replaces it.
    }

    private func cancel(_ id: UUID) {
        do {
            if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
                try AlarmManager.shared.cancel(id: id)
            }
            saved.retired.remove(id)
            persist()
        } catch {
            errorText = "Kunde inte återkalla ett tidigare tidslarm."
            warning(.service, "Missing data alarm cancellation failed: \(id), \(error)")
        }
    }
}

struct StopMissingDataAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Kvittera tidslarm"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Larm-ID") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { await MissingDataAlarmManager.shared.acknowledge(id) }
        return .result()
    }
}

@MainActor private final class MissingAlarmBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid
    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Missing data alarms") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
