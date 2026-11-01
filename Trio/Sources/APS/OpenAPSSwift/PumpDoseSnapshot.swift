import CoreData
import Foundation

/// Pump snapshots amend the original row; a late mutable report cannot undo a final one.
/// Kept independent of LoopKit so persistence and finalization can be exercised on macOS.
struct PumpDoseSnapshot {
    let syncIdentifier: String?
    let isMutable: Bool
    let start: Date
    let end: Date
    let rate: Decimal
    let amount: Decimal
    let deliveredUnits: Decimal?
    let isBolus: Bool
    let isScheduled: Bool
    let isSMB: Bool
    let isExternal: Bool

    func apply(to row: PumpEventStored, in context: NSManagedObjectContext) {
        guard !(row.doseFinalized && isMutable) else { return }
        if row.tempBasal?.deliveredUnits != nil, deliveredUnits == nil { return }
        let previousAmount = row.bolus?.amount
        let previousRate = row.tempBasal?.rate
        let previousDuration = row.tempBasal?.duration
        if isBolus {
            let bolus = row.bolus ?? BolusStored(context: context)
            bolus.pumpEvent = row
            bolus.amount = amount as NSDecimalNumber
            bolus.isSMB = isSMB
            bolus.isExternal = isExternal
        } else {
            let basal = row.tempBasal ?? TempBasalStored(context: context)
            basal.pumpEvent = row
            basal.rate = rate as NSDecimalNumber
            basal.endDate = isScheduled ? start : max(start, end)
            basal.duration = isScheduled ? 0 : Int16(clamping: Int(max(0, end.timeIntervalSince(start) / 60).rounded()))
            basal.deliveredUnits = deliveredUnits.map { $0 as NSDecimalNumber }
            basal.isScheduledBasal = isScheduled
            basal.tempType = "absolute"
        }
        // Migration: old rows have no finalization marker, and can be repaired by pump replay.
        row.syncIdentifier = syncIdentifier ?? row.syncIdentifier ?? "local-\(row.id ?? UUID().uuidString)"
        row.doseFinalized = !isMutable
        if previousAmount != row.bolus?.amount || previousRate != row.tempBasal?.rate ||
            previousDuration != row.tempBasal?.duration
        {
            row.uploadRevision = UUID().uuidString
            row.isUploadedToNS = false
            row.isUploadedToHealth = false
            row.isUploadedToTidepool = false
        }
    }
}

/// Carry the delivery state into the reporting window even when basal testing produces
/// no new commands for more than a day. Old boluses are never pulled into the window.
enum PumpHistoryWindow {
    static func fetch(in context: NSManagedObjectContext, since: Date) throws -> [PumpEventStored] {
        let request = PumpEventStored.fetchRequest()
        request.predicate = NSPredicate(format: "timestamp >= %@", since as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        var rows = try context.fetch(request)
        rows += try precedingEvents(in: context, since: since)
        return rows.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    static func precedingEvents(in context: NSManagedObjectContext, since: Date) throws -> [PumpEventStored] {
        let request = PumpEventStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        var rows: [PumpEventStored] = []
        for condition in [
            "tempBasal != nil AND tempBasal.isScheduledBasal == NO",
            "tempBasal.isScheduledBasal == YES",
            "type == 'PumpSuspend' OR type == 'PumpResume'",
            "type == 'PumpDetached' OR type == 'PumpAttached'"
        ] {
            request.predicate = NSPredicate(format: "timestamp < %@ AND (\(condition))", since as NSDate)
            request.fetchLimit = 1
            rows += try context.fetch(request)
        }
        return rows
    }
}

/// Atomic compare-and-set at the store, not a fetch/compare/save race. A finalization
/// arriving during the network request changes the revision and stays queued.
enum PumpHistoryUploadReceipt {
    static func acknowledge(id: String, revision: String?, in context: NSManagedObjectContext) throws {
        let request = NSBatchUpdateRequest(entityName: "PumpEventStored")
        if let revision = revision {
            request.predicate = NSPredicate(format: "id == %@ AND uploadRevision == %@", id, revision)
        } else {
            request.predicate = NSPredicate(format: "id == %@ AND uploadRevision == nil", id)
        }
        request.propertiesToUpdate = ["isUploadedToNS": true]
        request.resultType = .updatedObjectIDsResultType
        let result = try context.execute(request) as? NSBatchUpdateResult
        if let ids = result?.result as? [NSManagedObjectID], !ids.isEmpty {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSUpdatedObjectsKey: ids], into: [context])
        }
    }
}

extension BasalDeliveryTimeline {
    static func event(from event: PumpEventStored) -> Event? {
        guard let start = event.timestamp else { return nil }
        if let basal = event.tempBasal {
            return .init(
                start: start,
                end: basal.endDate ?? start.addingTimeInterval(Double(basal.duration) * 60),
                kind: basal.isScheduledBasal ? .anchor : .temp,
                rate: basal.rate as Decimal? ?? 0,
                id: event.id ?? ""
            )
        }
        let kind: BasalDeliveryTimeline.Event.Kind
        switch event.type {
        case EventType.pumpDetached.rawValue: kind = .detached
        case EventType.pumpAttached.rawValue: kind = .attached
        case EventType.pumpSuspend.rawValue: kind = .suspend
        case EventType.pumpResume.rawValue: kind = .resume
        default: kind = .anchor
        }
        return .init(start: start, end: start, kind: kind)
    }
}
