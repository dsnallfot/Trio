#!/usr/bin/env python3
"""Exercise production glucose upload methods on SQLite with Core Data queue checking.

macOS/Xcode only. Platform upload DTOs are fixtures; fetches, predicates and mapping
methods are extracted from production. No patient data, network or simulator needed.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end] + '\n'


core = (ROOT / 'Model/CoreDataStack.swift').read_text()
storage = (ROOT / 'Trio/Sources/APS/Storage/GlucoseStorage.swift').read_text()
storage = storage[storage.index('final class BaseGlucoseStorage:'):]
predicates = (ROOT / 'Model/Helper/GlucoseStored+helper.swift').read_text()
names = [prefix + destination for destination in ['Nightscout', 'Health', 'Tidepool']
         for prefix in ['glucoseNotYetUploadedTo', 'manualGlucoseNotYetUploadedTo']]
fixture = r'''
import CoreData
import Foundation
@objc(GlucoseStored) final class GlucoseStored: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var glucose: Int16
    @NSManaged var direction: String?
    @NSManaged var isManual: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isUploadedToHealth: Bool
    @NSManaged var isUploadedToTidepool: Bool
}
enum DebuggingIdentifiers { static let failed = "failed" }
extension Date { static var oneDayAgo: Date { Date().addingTimeInterval(-86400) } }
extension Decimal { var asMmolL: Decimal { self / 18 } }
enum Units { case mgdL, mmolL }
final class SettingsManager {
    struct Settings { var units = Units.mgdL }
    var settings = Settings()
}
enum CarbsEntry { static let local = "Trio" }
struct BloodGlucose {
    struct Direction {
        let rawValue: String
        init?(from value: String) { rawValue = value }
    }
    let _id: String
    let sgv: Int
    let direction: Direction?
    let date: Decimal
    let dateString: Date
    let unfiltered: Decimal
    let filtered: Decimal
    let noise: Int?
    let glucose: Int
    var type: String? = nil
    var device: String? = nil
    func convertStoredGlucoseSample(isManualGlucose: Bool) -> StoredGlucoseSample {
        StoredGlucoseSample(value: self, manual: isManualGlucose)
    }
}
struct StoredGlucoseSample { let value: BloodGlucose; let manual: Bool }
struct NightscoutTreatment {
    enum Event { case capillaryGlucose }
    var duration: Int?
    var rawDuration: Int?
    var rawRate: Int?
    var absolute: Decimal?
    var rate: Decimal?
    var eventType: Event
    var createdAt: Date?
    var enteredBy: String?
    var bolus: Int?
    var insulin: Decimal?
    var notes: String?
    var carbs: Decimal?
    var fat: Decimal?
    var protein: Decimal?
    var foodType: String?
    var targetTop: Decimal?
    var targetBottom: Decimal?
    var glucoseType: String?
    var glucose: String?
    var units: String?
    var id: String?
}
'''
source = fixture + '\nfinal class CoreDataStack {\nstatic let shared = CoreDataStack()\n'
for signature in ['func fetchEntities<', 'func fetchEntitiesAsync<', 'func fetchAndMapEntitiesAsync<']:
    source += method(core, signature)
source += '}\nextension NSPredicate {\n'
for name in names:
    source += method(predicates, 'static var ' + name + ':')
source += '}\nfinal class BaseGlucoseStorage {\n'
source += '''let coredataContext: NSManagedObjectContext
let settingsManager = SettingsManager()
init(_ context: NSManagedObjectContext) { coredataContext = context }
'''
source += method(storage, 'private var glucoseFormatter:')
for name in names:
    source += method(storage, 'func get' + name[0].upper() + name[1:] + '(')
source += '}\n'
source += r'''
@main struct Tests {
    static func main() async throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "GlucoseStored"
        entity.managedObjectClassName = NSStringFromClass(GlucoseStored.self)
        let fields: [(String, NSAttributeType)] = [
            ("id", .UUIDAttributeType), ("date", .dateAttributeType),
            ("glucose", .integer16AttributeType), ("direction", .stringAttributeType),
            ("isManual", .booleanAttributeType), ("isUploadedToNS", .booleanAttributeType),
            ("isUploadedToHealth", .booleanAttributeType), ("isUploadedToTidepool", .booleanAttributeType)
        ]
        entity.properties = fields.map { name, type in
            let field = NSAttributeDescription()
            field.name = name; field.attributeType = type; field.isOptional = true
            return field
        }
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
            at: URL(fileURLWithPath: CommandLine.arguments[1]))
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let now = Date()
        let sensorID = UUID(), manualID = UUID()
        try await context.perform {
            context.name = "glucose-upload-test"
            context.transactionAuthor = "glucose-writer"
            for (id, value, age, manual, uploaded) in [
                (sensorID, 120, 60.0, false, false),
                (manualID, 180, 30.0, true, false),
                (UUID(), 200, 20.0, false, true),
                (UUID(), 210, 90000.0, true, false)
            ] {
                let row = GlucoseStored(context: context)
                row.id = id; row.glucose = Int16(value)
                row.date = now.addingTimeInterval(-age); row.direction = "Flat"
                row.isManual = manual
                row.isUploadedToNS = uploaded; row.isUploadedToHealth = uploaded
                row.isUploadedToTidepool = uploaded
            }
            try context.save()
        }
        let storage = BaseGlucoseStorage(context)
        // All six entry points run concurrently on the same private context, as in the crash.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    async let ns = storage.getGlucoseNotYetUploadedToNightscout()
                    async let manualNS = storage.getManualGlucoseNotYetUploadedToNightscout()
                    async let health = storage.getGlucoseNotYetUploadedToHealth()
                    async let manualHealth = storage.getManualGlucoseNotYetUploadedToHealth()
                    async let tidepool = storage.getGlucoseNotYetUploadedToTidepool()
                    async let manualTidepool = storage.getManualGlucoseNotYetUploadedToTidepool()
                    let (n, mn, h, mh, t, mt) = await (ns, manualNS, health, manualHealth, tidepool, manualTidepool)
                    // Preserve existing predicates: the general path also includes manual rows.
                    precondition(n.map(\._id) == [manualID.uuidString, sensorID.uuidString])
                    precondition(n.map(\.sgv) == [180, 120])
                    precondition(n.allSatisfy { $0.type == "sgv" && $0.device == "Trio" })
                    precondition(n[0].dateString == now.addingTimeInterval(-30))
                    precondition(n[0].direction?.rawValue == "Flat")
                    precondition(mn.count == 1 && mn[0].id == manualID.uuidString)
                    precondition(mn[0].glucose == "180" && mn[0].units == "mg/dl")
                    precondition(mn[0].glucoseType == "Fingerstick")
                    precondition(h.map(\._id) == n.map(\._id) && mh.map(\._id) == [manualID.uuidString])
                    precondition(t.map { $0.value._id } == n.map(\._id) && t.allSatisfy { !$0.manual })
                    precondition(mt.count == 1 && mt[0].manual && mt[0].value._id == manualID.uuidString)
                }
            }
        }
        print("PASS: 600 concurrent uploads; selection, order, IDs, timestamps and payloads preserved")
        storage.settingsManager.settings.units = .mmolL
        let mmol = await storage.getManualGlucoseNotYetUploadedToNightscout()
        precondition(mmol.first?.glucose == "10.0" && mmol.first?.units == "mmol")
        print("PASS: fingerstick mmol/L formatting")
        // Legacy APIs must remain usable without changing metadata during a read.
        _ = CoreDataStack.shared.fetchEntities(ofType: GlucoseStored.self, onContext: context,
            predicate: NSPredicate(value: false), key: "date", ascending: false)
        _ = await CoreDataStack.shared.fetchEntitiesAsync(ofType: GlucoseStored.self, onContext: context,
            predicate: NSPredicate(value: false), key: "date", ascending: false)
        let metadataOK = await context.perform {
            context.name == "glucose-upload-test" && context.transactionAuthor == "glucose-writer"
        }
        precondition(metadataOK)
        print("PASS: fetches preserve context name and transaction author")
        // Detached payloads remain readable after the source objects are invalidated.
        let snapshot = await storage.getGlucoseNotYetUploadedToNightscout()
        await context.perform { context.reset() }
        precondition(snapshot.map(\.sgv) == [180, 120])
        try await context.perform {
            for row in try context.fetch(NSFetchRequest<GlucoseStored>(entityName: "GlucoseStored")) {
                row.isUploadedToNS = true; row.isUploadedToHealth = true; row.isUploadedToTidepool = true
            }
            try context.save()
        }
        let emptyNS = await storage.getGlucoseNotYetUploadedToNightscout()
        let emptyManualNS = await storage.getManualGlucoseNotYetUploadedToNightscout()
        let emptyHealth = await storage.getGlucoseNotYetUploadedToHealth()
        let emptyManualHealth = await storage.getManualGlucoseNotYetUploadedToHealth()
        let emptyTidepool = await storage.getGlucoseNotYetUploadedToTidepool()
        let emptyManualTidepool = await storage.getManualGlucoseNotYetUploadedToTidepool()
        precondition(emptyNS.isEmpty && emptyManualNS.isEmpty && emptyHealth.isEmpty &&
                     emptyManualHealth.isEmpty && emptyTidepool.isEmpty && emptyManualTidepool.isEmpty)
        print("PASS: detached values survive reset; uploaded entries are excluded from all six paths")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='trio-glucose-upload-context-') as directory:
    path = Path(directory)
    swift = path / 'Tests.swift'
    swift.write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-module-cache-path', str(path / 'cache'), str(swift), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests'), str(path / 'glucose.sqlite'),
                    '-com.apple.CoreData.ConcurrencyDebug', '1'], check=True, timeout=60)
