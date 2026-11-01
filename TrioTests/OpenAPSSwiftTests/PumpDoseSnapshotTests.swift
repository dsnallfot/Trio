import CoreData
import Foundation
import Testing
@testable import Trio

@Suite("Pump finalization and model migration", .serialized) struct PumpDoseSnapshotTests {
    func modelURL(_ name: String) throws -> URL {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle.main
        #endif
        let directory = try #require(bundle.url(forResource: "TrioCoreDataPersistentContainer", withExtension: "momd"))
        return directory.appendingPathComponent(name + ".mom")
    }

    func context(
        version: String = "TrioCoreDataPersistentContainerPumpHistory",
        url: URL? = nil
    ) throws -> NSManagedObjectContext {
        let model = try #require(NSManagedObjectModel(contentsOf: modelURL(version)))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: url == nil ? NSInMemoryStoreType : NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    func snapshot(mutable: Bool, minutes: Double, delivered: Decimal? = nil, bolus: Bool = false) -> PumpDoseSnapshot {
        PumpDoseSnapshot(
            syncIdentifier: "pump-dose-1",
            isMutable: mutable,
            start: Date(timeIntervalSince1970: 10000),
            end: Date(timeIntervalSince1970: 10000 + minutes * 60),
            rate: 1,
            amount: delivered ?? 1,
            deliveredUnits: delivered,
            isBolus: bolus,
            isScheduled: false,
            isSMB: true,
            isExternal: false
        )
    }

    @Test func finalSnapshotCorrectsSameRowAndRequeuesUpload() throws {
        let context = try context()
        try context.performAndWait {
            let row = PumpEventStored(context: context)
            row.id = "unchanged-id"
            row.type = "TempBasal"
            row.timestamp = Date(timeIntervalSince1970: 10000)
            row.note = "personal-note"
            snapshot(mutable: true, minutes: 30).apply(to: row, in: context)
            row.isUploadedToNS = true
            try context.save()
            snapshot(mutable: false, minutes: 3.25, delivered: Decimal(string: "0.05")!).apply(to: row, in: context)
            try context.save()
            #expect(row.id == "unchanged-id")
            #expect(row.note == "personal-note")
            #expect(row.tempBasal?.duration == 3)
            #expect(row.tempBasal?.endDate == Date(timeIntervalSince1970: 10195))
            #expect(row.tempBasal?.deliveredUnits == NSDecimalNumber(string: "0.05"))
            #expect(!row.isUploadedToNS)
            #expect(row.doseFinalized)
            snapshot(mutable: true, minutes: 30).apply(to: row, in: context)
            #expect(row.tempBasal?.duration == 3)
            #expect(try context.count(for: PumpEventStored.fetchRequest()) == 1)
        }
    }

    @Test func cancelledBolusPreservesIdentityAndRemoteNote() throws {
        let context = try context()
        try context.performAndWait {
            let row = PumpEventStored(context: context)
            row.id = "remote-bolus"
            row.type = "Bolus"
            row.note = "Trio (remote)"
            snapshot(mutable: true, minutes: 1, bolus: true).apply(to: row, in: context)
            row.isUploadedToNS = true
            snapshot(mutable: false, minutes: 0.5, delivered: Decimal(string: "0.4")!, bolus: true).apply(to: row, in: context)
            try context.save()
            #expect(row.bolus?.amount == NSDecimalNumber(string: "0.4"))
            #expect(row.note == "Trio (remote)")
            #expect(!row.isUploadedToNS)
        }
    }

    @Test func migratesPopulatedBackfillStoreWithoutLosingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let old = try context(version: "TrioCoreDataPersistentContainerBackfill", url: url)
        try old.performAndWait {
            let event = NSEntityDescription.insertNewObject(forEntityName: "PumpEventStored", into: old)
            event.setValue("old-temp", forKey: "id")
            event.setValue("TempBasal", forKey: "type")
            let basal = NSEntityDescription.insertNewObject(forEntityName: "TempBasalStored", into: old)
            basal.setValue(30, forKey: "duration")
            basal.setValue(NSDecimalNumber(string: "0.35"), forKey: "rate")
            event.setValue(basal, forKey: "tempBasal")
            try old.save()
            old.reset()
            let store = try #require(old.persistentStoreCoordinator?.persistentStores.first)
            try old.persistentStoreCoordinator?.remove(store)
        }
        let migrated = try context(url: url)
        try migrated.performAndWait {
            let rows = try migrated.fetch(PumpEventStored.fetchRequest())
            let row = try #require(rows.first)
            #expect(rows.count == 1)
            #expect(row.id == "old-temp")
            #expect(row.tempBasal?.rate == NSDecimalNumber(string: "0.35"))
            #expect(row.tempBasal?.duration == 30)
            #expect(row.tempBasal?.isScheduledBasal == false)
            #expect(!row.doseFinalized)
            #expect(row.tempBasal?.endDate == nil)
        }
    }

    @Test func staleNightscoutReceiptCannotHideFinalization() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try context(url: directory.appendingPathComponent("receipt.sqlite"))
        try context.performAndWait {
            let row = PumpEventStored(context: context)
            row.id = "upload-race"
            row.type = "TempBasal"
            snapshot(mutable: true, minutes: 30).apply(to: row, in: context)
            try context.save()
            let sentRevision = row.uploadRevision
            snapshot(mutable: false, minutes: 5, delivered: 0).apply(to: row, in: context)
            try context.save()
            try PumpHistoryUploadReceipt.acknowledge(id: "upload-race", revision: sentRevision, in: context)
            context.refresh(row, mergeChanges: false)
            #expect(!row.isUploadedToNS)
            try PumpHistoryUploadReceipt.acknowledge(id: "upload-race", revision: row.uploadRevision, in: context)
            context.refresh(row, mergeChanges: false)
            #expect(row.isUploadedToNS)
        }
    }

    @Test func reportingWindowRetainsBasalAndSuspensionButNotOldBolus() throws {
        let context = try context()
        try context.performAndWait {
            let since = Date(timeIntervalSince1970: 200_000)
            for (index, type) in ["TempBasal", "PumpSuspend", "Bolus"].enumerated() {
                let row = PumpEventStored(context: context)
                row.id = "boundary-\(index)"
                row.type = type
                row.timestamp = since.addingTimeInterval(-3600)
                if type == "TempBasal" {
                    let basal = TempBasalStored(context: context)
                    basal.pumpEvent = row
                    basal.rate = 1
                    basal.duration = 30
                }
            }
            try context.save()
            let rows = try PumpHistoryWindow.fetch(in: context, since: since)
            #expect(rows.count == 2)
            #expect(rows.contains { $0.type == "PumpSuspend" })
            #expect(rows.contains { $0.type == "TempBasal" })
            #expect(!rows.contains { $0.type == "Bolus" })
        }
    }

    @Test func storedTempAndPauseRoundTripThroughAppHistoryJSON() throws {
        let context = try context()
        try context.performAndWait {
            let row = PumpEventStored(context: context)
            row.id = "round-trip"
            row.timestamp = Date(timeIntervalSince1970: 10000)
            row.type = "TempBasal"
            snapshot(mutable: false, minutes: 3.25, delivered: Decimal(string: "0.05")!).apply(to: row, in: context)
            let pause = PumpHistoryEvent(id: "pause", type: .pumpSuspend, timestamp: Date(timeIntervalSince1970: 10195))
            let json = try PumpEventDTO
                .json([#require(row.toTempBasalDurationDTOEnum()), #require(row.toTempBasalDTOEnum()), .marker(pause)])
            let decoded = try JSONBridge.pumpHistory(from: json)
            #expect(decoded.count == 3)
            #expect(decoded[1].endDate == pause.timestamp)
            #expect(decoded[1].deliveredUnits == Decimal(string: "0.05")!)
            #expect(decoded[2] == pause)
        }
    }
}
