#!/usr/bin/env python3
"""Exercise production edit orchestration, payloads and deletion against temporary SQLite.

macOS Swift/Core Data required. External services and replacement insertion are test doubles.
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


remote = (ROOT / 'Trio/Sources/Services/RemoteControl/TrioRemoteControl.swift').read_text()
meal = (ROOT / 'Trio/Sources/Services/RemoteControl/TrioRemoteControl+Meal.swift').read_text()
storage = (ROOT / 'Trio/Sources/APS/Storage/CarbsStorage.swift').read_text()
model = (ROOT / 'Trio/Sources/Models/PushMessage.swift').read_text()
fixtures = r'''
import Foundation
import CoreData
extension Decimal { var formattedAsMmolL: String { "test" } }
enum DebuggingIdentifiers { static let succeeded = "ok"; static let failed = "failed" }
enum LogCategory { case remoteControl }
func debug(_ category: LogCategory, _ message: String) {}
struct Settings {
    var maxCarbs: Decimal = 100
    var maxFat: Decimal = 100
    var maxProtein: Decimal = 100
    var notificationsRemote = false
}
final class SettingsManager { var settings = Settings() }
final class Resolver {
    let settings = SettingsManager()
    func resolve<T>(_ type: T.Type) -> T? { settings as? T }
}
enum TrioApp { static let resolver = Resolver() }
enum DataTable { final class Provider { init(resolver: Resolver) {} } }
final class APSManager { func determineBasalSync() async {} }
final class Notifications { func notifyTrioRemoteControl(title: String, body: String) {} }
final class Subject { func send(_ value: Void) {} }
struct CarbsEntry { let createdAt: Date }
@objc(CarbEntryStored)
final class CarbEntryStored: NSManagedObject {
    @NSManaged var date: Date?
    @NSManaged var fpuID: UUID?
    @NSManaged var isFPU: Bool
    static func fetchRequest() -> NSFetchRequest<CarbEntryStored> { NSFetchRequest(entityName: "CarbEntryStored") }
}
final class CoreDataStack {
    static let shared = CoreDataStack()
    let persistentContainer: NSPersistentContainer
    init() {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "CarbEntryStored"
        entity.managedObjectClassName = NSStringFromClass(CarbEntryStored.self)
        entity.properties = [("date", NSAttributeType.dateAttributeType), ("fpuID", .UUIDAttributeType), ("isFPU", .booleanAttributeType)].map {
            let attribute = NSAttributeDescription()
            attribute.name = $0.0; attribute.attributeType = $0.1; attribute.isOptional = true
            return attribute
        }
        model.entities = [entity]
        persistentContainer = NSPersistentContainer(name: "Test", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        persistentContainer.persistentStoreDescriptions = [description]
        persistentContainer.loadPersistentStores { _, error in precondition(error == nil) }
    }
    func newTaskContext() -> NSManagedObjectContext { persistentContainer.newBackgroundContext() }
}
final class Storage {
    var failDeletion = false
    func deleteCarbsEntryStored(_ id: NSManagedObjectID) async -> Bool {
        if failDeletion { return false }
        return await deleteStored(id)
    }
    let updateSubject = Subject()
    func recent() -> [CarbsEntry] { [CarbsEntry(createdAt: Date().addingTimeInterval(3600))] }
'''
production_delete = method(storage[storage.index('final class BaseCarbsStorage:'):], '    func deleteCarbsEntryStored(').replace('func deleteCarbsEntryStored(', 'func deleteStored(', 1)
controller = r'''
}
final class TrioRemoteControl {
    let carbsStorage = Storage()
    let settings = TrioApp.resolver.settings
    let notificationManager = Notifications()
    var errors: [String] = []
    var replacements: [PushMessage] = []
    var serviceDeletes = 0
    private static var pendingRemoteCommandKeys = Set<String>()
    private static var processedRemoteCommandKeys = [String: Date]()
    private static let remoteCommandDedupQueue = DispatchQueue(label: "test.dedup")
    private static let remoteCommandDedupRetention: TimeInterval = 600
    func logError(_ message: String, pushMessage: PushMessage? = nil) async { errors.append(message) }
    func deleteMealFromServices(_ id: NSManagedObjectID, provider: DataTable.Provider) async { serviceDeletes += 1 }
    func handleMealCommand(_ message: PushMessage) async -> Bool {
        replacements.append(message)
        return true
    }
'''
controller += method(remote, '    enum CommandType:')
for signature in ['    internal func remoteCommandDedupKey(', '    internal func beginRemoteCommandIfNotDuplicate(',
                  '    internal func finishRemoteCommandDedup(', '    internal func cancelRemoteCommandDedup(']:
    controller += method(remote, signature)
for signature in ['    private func validateMealCommand(', '    func handleEditMealCommand(', '    func handleDeleteMealCommand(']:
    controller += method(meal, signature)
controller += '}\n'
tests = r'''
func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    print("PASS: \(message)")
}
func insert(_ time: Double, fpuID: UUID? = nil, isFPU: Bool = false) async throws -> NSManagedObjectID {
    let context = CoreDataStack.shared.newTaskContext()
    return try await context.perform {
        let item = CarbEntryStored(context: context)
        item.date = Date(timeIntervalSince1970: time)
        item.fpuID = fpuID; item.isFPU = isFPU
        try context.save()
        return item.objectID
    }
}
func count(_ id: UUID? = nil) async throws -> Int {
    let context = CoreDataStack.shared.newTaskContext()
    return try await context.perform {
        let request = CarbEntryStored.fetchRequest()
        if let id { request.predicate = NSPredicate(format: "fpuID == %@", id as CVarArg) }
        return try context.count(for: request)
    }
}
@main struct Main {
    static func main() async throws {
        let controller = TrioRemoteControl()
        var message = PushMessage(user: "test", commandType: .editMeal, carbs: 40, protein: 10, fat: 20,
                                  sharedSecret: "test", timestamp: 10000, scheduledTime: 2000, originalTime: 1000)
        let encoded = try JSONEncoder().encode(message)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        check(json["command_type"] as? String == "editMeal" && json["original_time"] as? Double == 1000,
              "editMeal payload and original_time encoding")
        let decoded = try JSONDecoder().decode(PushMessage.self, from: encoded)
        check(decoded.originalTime == 1000 && decoded.scheduledTime == 2000 && decoded.timestamp == 10000,
              "three independent timestamps survive roundtrip")
        var legacy = message; legacy.commandType = .meal; legacy.originalTime = nil
        let legacyDecoded = try JSONDecoder().decode(PushMessage.self, from: JSONEncoder().encode(legacy))
        check(legacyDecoded.originalTime == nil, "legacy payload without original_time")

        let group = UUID()
        _ = try await insert(1000.2, fpuID: group)
        _ = try await insert(4600, fpuID: group, isFPU: true)
        _ = try await insert(6400, fpuID: group, isFPU: true)
        _ = try await insert(8200, fpuID: group, isFPU: true)
        _ = try await insert(1000.5, fpuID: UUID(), isFPU: true)
        var invalid = message; invalid.carbs = 101
        await controller.handleEditMealCommand(invalid)
        check(try await count(group) == 4 && controller.replacements.isEmpty && controller.serviceDeletes == 0,
              "invalid replacement leaves old meal and all FPU entries intact")
        invalid = message; invalid.originalTime = nil
        await controller.handleEditMealCommand(invalid)
        invalid = message; invalid.bolusAmount = 1
        await controller.handleEditMealCommand(invalid)
        invalid = message; invalid.scheduledTime = .infinity
        await controller.handleEditMealCommand(invalid)
        invalid = message; invalid.fat = -1
        await controller.handleEditMealCommand(invalid)
        check(try await count(group) == 4 && controller.replacements.isEmpty, "missing identity, bolus, invalid time and negatives rejected before deletion")

        await controller.handleEditMealCommand(message)
        check(try await count(group) == 0, "parent and all later FPU entries deleted together")
        check(try await count() == 1, "unrelated FPU in matching second is preserved")
        check(controller.replacements.count == 1 && controller.replacements[0].scheduledTime == 2000,
              "replacement invoked after deletion with new time, despite future carb history")
        await controller.handleEditMealCommand(message)
        check(controller.replacements.count == 1 && controller.serviceDeletes == 1, "duplicate edit never deletes or inserts again")

        message.originalTime = 3000; message.scheduledTime = nil; message.fat = nil; message.protein = nil
        _ = try await insert(3000.1)
        await controller.handleEditMealCommand(message)
        check(controller.replacements.last?.scheduledTime == 3000 && controller.replacements.last?.fat == 0 && controller.replacements.last?.protein == 0,
              "omitted scheduled_time keeps original time; omitted nutrients become zero")

        let before = controller.replacements.count
        message.originalTime = 4000
        await controller.handleEditMealCommand(message)
        check(controller.replacements.count == before, "missing old meal prevents insertion")
        _ = try await insert(4000.1); _ = try await insert(4000.8)
        await controller.handleEditMealCommand(message)
        check(controller.replacements.count == before, "ambiguous parents prevent deletion and insertion")

        message.originalTime = 6000
        _ = try await insert(6000)
        controller.carbsStorage.failDeletion = true
        await controller.handleEditMealCommand(message)
        check(controller.replacements.count == before, "storage deletion failure prevents replacement")
        controller.carbsStorage.failDeletion = false
        await controller.handleEditMealCommand(message)
        check(controller.replacements.count == before + 1, "failed edit releases dedup reservation for retry")

        let id = try await insert(5000)
        check(await controller.carbsStorage.deleteCarbsEntryStored(id), "single carb deletion reports success")
        check(!(await controller.carbsStorage.deleteCarbsEntryStored(id)), "already removed object reports failure")
        // An invalid object ID exercises the error path without changing patient data.
        let transient = CoreDataStack.shared.newTaskContext()
        let temporaryID = await transient.perform { CarbEntryStored(context: transient).objectID }
        check(!(await controller.carbsStorage.deleteCarbsEntryStored(temporaryID)), "unresolvable object reports failure")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='trio-edit-meal-') as directory:
    path = Path(directory)
    source = path / 'test.swift'
    source.write_text(fixtures + production_delete + controller + model + tests)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(path / 'module-cache'), '-parse-as-library', '-o', str(path / 'tests'), str(source)], check=True)
    subprocess.run([str(path / 'tests'), str(path / 'test.sqlite')], check=True)
