#!/usr/bin/env python3
"""Run production CGM cursor/filter code against a temporary Core Data SQLite store.

Requires macOS and Xcode. No simulator, network, or real patient data is used.
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


storage = (ROOT / 'Trio/Sources/APS/Storage/GlucoseStorage.swift').read_text()
storage = storage[storage.index('final class BaseGlucoseStorage:'):]
helper = (ROOT / 'Model/Classes+Properties/GlucoseImportFilter.swift').read_text()
fetch = (ROOT / 'Trio/Sources/APS/FetchGlucoseManager.swift').read_text()
# Check the driver entry points use the same cursor exercised below.
for name in ['PluginSource', 'DexcomSourceG5', 'DexcomSourceG6']:
    source = (ROOT / f'Trio/Sources/APS/CGM/{name}.swift').read_text()
    assert 'return glucoseStorage.syncDate()' in method(source, '    func startDateToFilterNewData(')

fixtures = r'''
import CoreData
import Foundation

@objc(GlucoseStored)
final class GlucoseStored: NSManagedObject {
    @NSManaged var date: Date?
    @NSManaged var isManual: Bool
    static func fetchRequest() -> NSFetchRequest<GlucoseStored> {
        NSFetchRequest(entityName: "GlucoseStored")
    }
}
extension NSPredicate {
    static var predicateForOneDayAgo: NSPredicate {
        NSPredicate(format: "date >= %@", Date().addingTimeInterval(-86400) as NSDate)
    }
    static var predicateFor30MinAgo: NSPredicate {
        NSPredicate(format: "date >= %@", Date().addingTimeInterval(-1800) as NSDate)
    }
}
enum DebuggingIdentifiers { static let failed = "failed" }
struct BloodGlucose {
    let dateString: Date
    var date: TimeInterval { dateString.timeIntervalSince1970 }
}
final class CoreDataStack {
    static let shared = CoreDataStack()
    func fetchEntities(ofType: GlucoseStored.Type, onContext: NSManagedObjectContext,
                       predicate: NSPredicate, key: String, ascending: Bool, fetchLimit: Int) -> Any? {
        let request = GlucoseStored.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.fetchLimit = fetchLimit
        return try! onContext.fetch(request)
    }
}
final class Storage {
    let coredataContext: NSManagedObjectContext
    var context: NSManagedObjectContext { coredataContext }
    enum Config { static let filterTime: TimeInterval = 210 }
    init(_ context: NSManagedObjectContext) { coredataContext = context }
    func smoothingDates() -> [Date] { fetchGlucose()!.compactMap(\.date) }
'''
methods = ''.join(method(storage, signature) for signature in [
    '    func syncDate()', '    func lastGlucoseDate()', '    func filterTooFrequentGlucose('
]) + method(fetch, '    private func fetchGlucose()')

tests = r'''
func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
    let value = NSAttributeDescription()
    value.name = name
    value.attributeType = type
    value.isOptional = true
    return value
}
let model = NSManagedObjectModel()
model.entities = ["GlucoseStored", "DeletedGlucoseStored"].map { name in
    let entity = NSEntityDescription()
    entity.name = name
    entity.managedObjectClassName = name == "GlucoseStored" ? NSStringFromClass(GlucoseStored.self) : "NSManagedObject"
    let manual = name == "GlucoseStored" ? "isManual" : "isManualGlucoseEntry"
    entity.properties = [attribute("date", .dateAttributeType), attribute(manual, .booleanAttributeType)]
    return entity
}
let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
                                   at: URL(fileURLWithPath: CommandLine.arguments[1]), options: nil)
let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = coordinator
let storage = Storage(context)
let base = Date().addingTimeInterval(-900)
func date(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
func insert(_ seconds: Double, manual: Bool?, deleted: Bool = false) throws {
    let entity = deleted ? "DeletedGlucoseStored" : "GlucoseStored"
    let item = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
    item.setValue(date(seconds), forKey: "date")
    item.setValue(manual, forKey: deleted ? "isManualGlucoseEntry" : "isManual")
    try context.save()
}
func accepted(_ seconds: [Double], buffer: Double = 1, deleted: Bool = false) throws -> [Int] {
    try GlucoseImportFilter.acceptedIndices(dates: seconds.map(date),
        entityName: deleted ? "DeletedGlucoseStored" : "GlucoseStored", context: context,
        timeBuffer: buffer, deduplicateBatch: !deleted)
}
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    let passed = try condition()
    precondition(passed, message)
    print("PASS: \(message)")
}
try insert(299.5, manual: true)
check(storage.syncDate() == .distantPast, "manual-only history does not advance the sensor cursor")
check(storage.lastGlucoseDate() == date(299.5), "manual readings remain available as latest glucose")
try check(accepted([299.5]) == [0], "CGM may share an exact timestamp with a fingerstick")
try insert(0, manual: false)
check(storage.syncDate() == date(0), "sensor cursor ignores a more recent fingerstick")
let fresh = storage.filterTooFrequentGlucose([BloodGlucose(dateString: date(300))], at: storage.syncDate())
check(fresh.count == 1, "next five-minute CGM reading survives a fingerstick 0.5 seconds earlier")
try check(accepted([300]) == [0], "live persistence also accepts the CGM reading")
try check(accepted([300], buffer: 210) == [0], "backfill is not blocked by a nearby fingerstick")
check(storage.smoothingDates() == [date(0)], "smoothing excludes manual readings newer than the cursor")
try insert(300, manual: false)
try check(accepted([300]) == [], "replayed CGM is still deduplicated")
try check(accepted([300], buffer: 210) == [], "backfill replay is still deduplicated")
try check(accepted([600, 600.5, 900]) == [0, 2], "batch duplicates remain filtered")
check(storage.filterTooFrequentGlucose([BloodGlucose(dateString: date(510))], at: date(300)).isEmpty,
      "original 3.5-minute sensor spacing boundary is preserved")
try insert(600, manual: true, deleted: true)
try check(accepted([600], deleted: true) == [0], "deleted fingersticks do not block CGM")
try insert(900, manual: false, deleted: true)
try check(accepted([900], deleted: true) == [], "deleted CGM readings remain blocked")
try insert(1000, manual: nil, deleted: true)
try check(accepted([1000], deleted: true) == [], "legacy unclassified tombstones remain blocked")
try insert(600, manual: nil)
check(storage.syncDate() == date(600), "legacy nil manual flags count as sensor readings")
try check(accepted([600]) == [], "legacy sensor readings still prevent duplicate import")
print("All manual/CGM import regression checks passed")
'''
with tempfile.TemporaryDirectory(prefix='trio-manual-cgm-tests-') as directory:
    path = Path(directory)
    swift = path / 'main.swift'
    swift.write_text(fixtures + methods + '}\n' + helper + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', str(path / 'cache'),
                    str(swift), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests'), str(path / 'glucose.sqlite')], check=True, timeout=30)
