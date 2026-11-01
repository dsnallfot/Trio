import Combine
import CoreData
import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryObserver {
    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent])
}

protocol PumpHistoryStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func storePumpEvents(_ events: [NewPumpEvent])
    func storePumpEvents(_ events: [NewPumpEvent], diagnostics: ((String, Int) -> Void)?)
    func storePumpEvents(_ events: [NewPumpEvent], diagnostics: ((String, Int) -> Void)?, completion: @escaping (Error?) -> Void)
    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async
    func recent() -> [PumpHistoryEvent]
    func getPumpHistoryNotYetUploadedToNightscout(using context: NSManagedObjectContext) async -> [NightscoutTreatment]
    func getPumpHistoryNotYetUploadedToHealth() async -> [PumpHistoryEvent]
    func getPumpHistoryNotYetUploadedToTidepool() async -> [PumpHistoryEvent]
    func deleteInsulin(at date: Date)
}

extension PumpHistoryStorage {
    func storePumpEvents(
        _ events: [NewPumpEvent],
        diagnostics: ((String, Int) -> Void)?,
        completion: @escaping (Error?) -> Void
    ) {
        storePumpEvents(events, diagnostics: diagnostics)
        completion(nil)
    }

    func storePumpEvents(_ events: [NewPumpEvent], diagnostics _: ((String, Int) -> Void)?) {
        storePumpEvents(events)
    }
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    private let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    typealias PumpEvent = PumpEventStored.EventType
    typealias TempType = PumpEventStored.TempType

    private let context = CoreDataStack.shared.newTaskContext()

    private func roundDose(_ dose: Double, toIncrement increment: Double) -> Decimal {
        let roundedValue = (dose / increment).rounded() * increment
        return Decimal(roundedValue)
    }

    func storePumpEvents(_ events: [NewPumpEvent]) {
        storePumpEvents(events, diagnostics: nil)
    }

    func storePumpEvents(_ events: [NewPumpEvent], diagnostics: ((String, Int) -> Void)?) {
        storePumpEvents(events, diagnostics: diagnostics, completion: { _ in })
    }

    func storePumpEvents(
        _ events: [NewPumpEvent],
        diagnostics: ((String, Int) -> Void)?,
        completion: @escaping (Error?) -> Void
    ) {
        diagnostics?("historyBatches", 1)
        diagnostics?("historyEvents", events.count)
        processQueue.async {
            self.context.perform {
                for event in events {
                    // DASH emits its removal with no PumpEventType, but a stable raw record prefix.
                    let removed = event.type == nil && event.raw.starts(with: Data("Pod Removed ".utf8))
                    let storedType: String
                    if removed { storedType = EventType.pumpDetached.rawValue }
                    else if let type = event.type?.historyStoredType { storedType = type }
                    else { continue }
                    let request = PumpEventStored.fetchRequest()
                    // Include type: a bolus and basal may legitimately start together.
                    // Include start time even with a sync ID: drivers may reuse IDs after a pump change.
                    request.predicate = NSPredicate(
                        format: "timestamp == %@ AND type == %@",
                        event.date as NSDate,
                        storedType
                    )
                    let existingEvents: [PumpEventStored]
                    do {
                        existingEvents = try self.context.fetch(request)
                    } catch {
                        self.context.rollback()
                        completion(error)
                        return
                    }
                    let scheduled = event.type == .basal
                    let candidates = existingEvents.filter {
                        ($0.tempBasal?.isScheduledBasal ?? false) == scheduled &&
                            ($0.bolus == nil || $0.bolus?.isExternal == event.dose?.manuallyEntered)
                    }
                    let match = candidates.first { $0.syncIdentifier == event.dose?.syncIdentifier } ??
                        (candidates.count == 1 && !candidates[0].doseFinalized ? candidates[0] : nil)

                    if storedType == EventType.pumpDetached.rawValue || storedType == EventType.pumpAttached.rawValue {
                        if existingEvents.isEmpty {
                            let marker = PumpEventStored(context: self.context)
                            marker.id = UUID().uuidString
                            marker.timestamp = event.date
                            marker.type = storedType
                        }
                        continue
                    }
                    switch event.type {
                    case .basal,
                         .bolus,
                         .tempBasal:
                        guard let dose = event.dose else { continue }
                        let row = match ?? PumpEventStored(context: self.context)
                        if match == nil {
                            row.id = UUID().uuidString
                            row.timestamp = event.date
                            row.type = storedType
                        }
                        PumpDoseSnapshot(
                            syncIdentifier: dose.syncIdentifier,
                            isMutable: dose.isMutable,
                            start: dose.startDate,
                            end: dose.endDate,
                            rate: Decimal(dose.unitsPerHour),
                            amount: self.roundDose(
                                dose.deliveredUnits ?? dose.unitsInDeliverableIncrements,
                                toIncrement: Double(self.settings.preferences.bolusIncrement)
                            ),
                            deliveredUnits: dose.deliveredUnits.map { Decimal($0) },
                            isBolus: event.type == .bolus,
                            isScheduled: scheduled,
                            isSMB: dose.automatic ?? true,
                            isExternal: dose.manuallyEntered
                        ).apply(to: row, in: self.context)

                    case .suspend:
                        guard existingEvents.isEmpty else {
                            diagnostics?("historyDuplicateCandidates", 1)
                            // Duplicate found, do not store the event
                            let typeDescription = event.type?.rawValue ?? "unknown"
                            print("🟡 Skipping duplicate pump event. Timestamp: \(event.date), Type: \(typeDescription)")
                            continue
                        }
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = UUID().uuidString
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.pumpSuspend.rawValue
                        newPumpEvent.isUploadedToNS = false
                        newPumpEvent.isUploadedToHealth = false
                        newPumpEvent.isUploadedToTidepool = false

                    case .resume:
                        guard existingEvents.isEmpty else {
                            diagnostics?("historyDuplicateCandidates", 1)
                            // Duplicate found, do not store the event
                            let typeDescription = event.type?.rawValue ?? "unknown"
                            print("🟡 Skipping duplicate pump event. Timestamp: \(event.date), Type: \(typeDescription)")
                            continue
                        }
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = UUID().uuidString
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.pumpResume.rawValue
                        newPumpEvent.isUploadedToNS = false
                        newPumpEvent.isUploadedToHealth = false
                        newPumpEvent.isUploadedToTidepool = false

                    case .rewind:
                        guard existingEvents.isEmpty else {
                            diagnostics?("historyDuplicateCandidates", 1)
                            // Duplicate found, do not store the event
                            let typeDescription = event.type?.rawValue ?? "unknown"
                            print("🟡 Skipping duplicate pump event. Timestamp: \(event.date), Type: \(typeDescription)")
                            continue
                        }
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = UUID().uuidString
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.rewind.rawValue
                        newPumpEvent.isUploadedToNS = false
                        newPumpEvent.isUploadedToHealth = false
                        newPumpEvent.isUploadedToTidepool = false

                    case .prime:
                        guard existingEvents.isEmpty else {
                            diagnostics?("historyDuplicateCandidates", 1)
                            // Duplicate found, do not store the event
                            let typeDescription = event.type?.rawValue ?? "unknown"
                            print("🟡 Skipping duplicate pump event. Timestamp: \(event.date), Type: \(typeDescription)")
                            continue
                        }
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = UUID().uuidString
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.prime.rawValue
                        newPumpEvent.isUploadedToNS = false
                        newPumpEvent.isUploadedToHealth = false
                        newPumpEvent.isUploadedToTidepool = false

                    case .alarm:
                        guard existingEvents.isEmpty else {
                            diagnostics?("historyDuplicateCandidates", 1)
                            // Duplicate found, do not store the event
                            let typeDescription = event.type?.rawValue ?? "unknown"
                            print("🟡 Skipping duplicate pump event. Timestamp: \(event.date), Type: \(typeDescription)")
                            continue
                        }
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = UUID().uuidString
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.pumpAlarm.rawValue
                        newPumpEvent.isUploadedToNS = false
                        newPumpEvent.isUploadedToHealth = false
                        newPumpEvent.isUploadedToTidepool = false
                        newPumpEvent.note = event.title

                    default:
                        continue
                    }
                }

                do {
                    guard self.context.hasChanges else {
                        diagnostics?("historyUnchangedBatches", 1)
                        completion(nil)
                        return
                    }
                    try self.context.save()
                    diagnostics?("historyContextSaves", 1)
                    completion(nil)

                    self.updateSubject.send(())
                    debugPrint("\(DebuggingIdentifiers.succeeded) stored pump events in Core Data")
                } catch let error as NSError {
                    debugPrint("\(DebuggingIdentifiers.failed) failed to store pump events with error: \(error.userInfo)")
                    self.context.rollback()
                    completion(error)
                }
            }
        }
    }

    func storeExternalInsulinEvent(amount: Decimal, timestamp: Date) async {
        debug(.default, "External insulin saved")
        await context.perform {
            // create pump event
            let newPumpEvent = PumpEventStored(context: self.context)
            newPumpEvent.id = UUID().uuidString
            // restrict entry to now or past
            newPumpEvent.timestamp = timestamp > Date() ? Date() : timestamp
            newPumpEvent.type = PumpEvent.bolus.rawValue
            newPumpEvent.isUploadedToNS = false
            newPumpEvent.isUploadedToHealth = false
            newPumpEvent.isUploadedToTidepool = false

            // create bolus entry and specify relationship to pump event
            let newBolusEntry = BolusStored(context: self.context)
            newBolusEntry.pumpEvent = newPumpEvent
            newBolusEntry.amount = amount as NSDecimalNumber
            newBolusEntry.isExternal = true // we are creating an external dose
            newBolusEntry.isSMB = false // the dose is manually administered

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()

                self.updateSubject.send(())
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    func recent() -> [PumpHistoryEvent] {
        storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)?.reversed() ?? []
    }

    func deleteInsulin(at date: Date) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []
            guard let entryIndex = allValues.firstIndex(where: { $0.timestamp == date }) else {
                return
            }
            allValues.remove(at: entryIndex)
            storage.save(allValues, as: OpenAPS.Monitor.pumpHistory)
            broadcaster.notify(PumpHistoryObserver.self, on: processQueue) {
                $0.pumpHistoryDidUpdate(allValues)
            }
        }
    }

    func determineBolusEventType(for event: PumpEventStored) -> PumpEventStored.EventType {
        guard let bolus = event.bolus else {
            return event.type.flatMap({ PumpEventStored.EventType(rawValue: $0) }) ?? .bolus
        }
        if bolus.isSMB {
            return .smb
        }
        if bolus.isExternal {
            return .isExternal
        }
        return event.type.flatMap({ PumpEventStored.EventType(rawValue: $0) }) ?? .bolus
    }

    func getPumpHistoryNotYetUploadedToNightscout(using context: NSManagedObjectContext) async -> [NightscoutTreatment] {
        await context.perform {
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            fetchRequest.predicate = NSPredicate.pumpEventsNotYetUploadedToNightscout
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            do {
                let fetchedPumpEvents = try context.fetch(fetchRequest)
                debugPrint("🟡 [NSFetch] Fetched \(fetchedPumpEvents.count) PumpEventStored entries not yet uploaded")

                for event in fetchedPumpEvents {
                    let idString = event.id ?? "nil"
                    let timestamp = event.timestamp?.description(with: .current) ?? "nil"
                    debugPrint("  🔍 ID: \(idString) | Timestamp: \(timestamp) | isUploadedToNS: \(event.isUploadedToNS)")
                }

                let mapped: [NightscoutTreatment] = fetchedPumpEvents.compactMap { event in
                    switch event.type {
                    case PumpEvent.bolus.rawValue:
                        let eventType = self.determineBolusEventType(for: event)
                        let enteredBy: String = {
                            if let pending = TrioRemoteControl.pendingRemoteBolusNote,
                               let eventTimestamp = event.timestamp
                            {
                                let timeDiff = abs(eventTimestamp.timeIntervalSince(pending.timestamp))
                                if timeDiff < 180 {
                                    debugPrint("🟣 Using pending remote note '\(pending.note)' for bolus at \(eventTimestamp)")
                                    return "Trio (\(pending.note))"
                                }
                            }
                            if let note = event.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !note.isEmpty, note != NightscoutTreatment.local
                            {
                                debugPrint("🟣 Using event.note '\(note)' at \(event.timestamp ?? .distantPast)")
                                return note
                            }
                            return NightscoutTreatment.local
                        }()

                        return NightscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: eventType,
                            createdAt: event.timestamp,
                            enteredBy: enteredBy,
                            bolus: nil,
                            insulin: event.bolus?.amount as Decimal?,
                            notes: nil,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil,
                            id: event.id,
                            pumpHistoryRevision: event.uploadRevision
                        )

                    case PumpEvent.tempBasal.rawValue:
                        return NightscoutTreatment(
                            duration: Int(event.tempBasal?.duration ?? 0),
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: event.tempBasal?.rate as Decimal?,
                            rate: event.tempBasal?.rate as Decimal?,
                            eventType: .nsTempBasal,
                            createdAt: event.timestamp,
                            enteredBy: NightscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: nil,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil,
                            id: event.id,
                            pumpHistoryRevision: event.uploadRevision
                        )

                    case PumpEvent.pumpSuspend.rawValue:
                        return NightscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsNote,
                            createdAt: event.timestamp,
                            enteredBy: NightscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: PumpEvent.pumpSuspend.rawValue,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil
                        )

                    case PumpEvent.pumpResume.rawValue:
                        return NightscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsNote,
                            createdAt: event.timestamp,
                            enteredBy: NightscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: PumpEvent.pumpResume.rawValue,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil
                        )

                    case PumpEvent.rewind.rawValue:
                        return NightscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsInsulinChange,
                            createdAt: event.timestamp,
                            enteredBy: NightscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: nil,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil
                        )

                    case PumpEvent.prime.rawValue:
                        return NightscoutTreatment(
                            duration: nil,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsSiteChange,
                            createdAt: event.timestamp,
                            enteredBy: NightscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: nil,
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil
                        )

                    case PumpEvent.pumpAlarm.rawValue:
                        return NightscoutTreatment(
                            duration: 30,
                            rawDuration: nil,
                            rawRate: nil,
                            absolute: nil,
                            rate: nil,
                            eventType: .nsAnnouncement,
                            createdAt: event.timestamp,
                            enteredBy: NightscoutTreatment.local,
                            bolus: nil,
                            insulin: nil,
                            notes: "Alarm \(String(describing: event.note)) \(PumpEvent.pumpAlarm.rawValue)",
                            carbs: nil,
                            fat: nil,
                            protein: nil,
                            targetTop: nil,
                            targetBottom: nil
                        )

                    default:
                        debugPrint("⚠️ Unknown pump event type: \(event.type ?? "nil") at \(event.timestamp ?? .distantPast)")
                        return nil
                    }
                }

                debugPrint("🔵 [NSMap] Successfully mapped \(mapped.count) NightscoutTreatments from PumpEventStored")
                return mapped
            } catch {
                debugPrint("❌ Failed to fetch PumpEventStored: \(error.localizedDescription)")
                return []
            }
        }
    }

    func getPumpHistoryNotYetUploadedToHealth() async -> [PumpHistoryEvent] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToHealth,
            key: "timestamp",
            ascending: false
        )

        guard let fetchedPumpEvents = results as? [PumpEventStored] else { return [] }

        return await context.perform {
            fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?
                    )
                case PumpEvent.tempBasal.rawValue:
                    if let id = event.id, let timestamp = event.timestamp, let tempBasal = event.tempBasal,
                       let tempBasalRate = tempBasal.rate
                    {
                        return PumpHistoryEvent(
                            id: id,
                            type: .tempBasal,
                            timestamp: timestamp,
                            amount: tempBasalRate as Decimal,
                            duration: Int(tempBasal.duration)
                        )
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }

    func getPumpHistoryNotYetUploadedToTidepool() async -> [PumpHistoryEvent] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpEventsNotYetUploadedToTidepool,
            key: "timestamp",
            ascending: false
        )

        guard let fetchedPumpEvents = results as? [PumpEventStored] else { return [] }

        return await context.perform {
            fetchedPumpEvents.map { event in
                switch event.type {
                case PumpEvent.bolus.rawValue:
                    return PumpHistoryEvent(
                        id: event.id ?? UUID().uuidString,
                        type: .bolus,
                        timestamp: event.timestamp ?? Date(),
                        amount: event.bolus?.amount as Decimal?,
                        isSMB: event.bolus?.isSMB ?? true,
                        isExternal: event.bolus?.isExternal ?? false
                    )
                case PumpEvent.tempBasal.rawValue:
                    if let id = event.id, let timestamp = event.timestamp, let tempBasal = event.tempBasal,
                       let tempBasalRate = tempBasal.rate
                    {
                        return PumpHistoryEvent(
                            id: id,
                            type: .tempBasal,
                            timestamp: timestamp,
                            amount: tempBasalRate as Decimal,
                            duration: Int(tempBasal.duration)
                        )
                    } else {
                        return nil
                    }

                default:
                    return nil
                }
            }.compactMap { $0 }
        }
    }
}

private extension PumpEventType {
    var historyStoredType: String? {
        switch self {
        case .bolus: return "Bolus"
        case .basal,
             .tempBasal: return "TempBasal"
        case .suspend: return "PumpSuspend"
        case .resume: return "PumpResume"
        case .rewind: return "Rewind"
        case .prime: return "Prime"
        case .alarm: return "PumpAlarm"
        case .replaceComponent(componentType: .pump): return EventType.pumpAttached.rawValue
        default: return nil
        }
    }
}
