import CoreData
import Foundation
import Testing
@testable import Trio

@Suite("Dosing mode persistence boundary", .serialized) struct DosingModeActivationTests {
    @Test func rejectsEveryActivationOutsideClosedLoop() throws {
        let policy = AdjustmentActivationPolicy.shared
        policy.update(.closed)
        defer { policy.update(.open) }
        let model = NSManagedObjectModel()
        model.entities = [OverrideStored.self, TempTargetStored.self].map { type in
            let entity = NSEntityDescription()
            entity.name = String(describing: type)
            entity.managedObjectClassName = NSStringFromClass(type)
            let enabled = NSAttributeDescription()
            enabled.name = "enabled"
            enabled.attributeType = .booleanAttributeType
            enabled.defaultValue = false
            entity.properties = [enabled]
            return entity
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            for mode in [DosingMode.open, .basalTesting, .lowGlucoseSuspend] {
                policy.update(mode)
                for entity in model.entities {
                    let object = NSEntityDescription.insertNewObject(forEntityName: entity.name!, into: context)
                    object.setValue(true, forKey: "enabled")
                    #expect(throws: DosingModeError.self) { try context.save() }
                    context.rollback()
                }
            }
            policy.update(.closed)
            let preset = OverrideStored(entity: model.entities[0], insertInto: context)
            preset.enabled = false
            try context.save() // Saving a preset remains allowed.
            policy.update(.basalTesting)
            preset.enabled = true
            #expect(throws: DosingModeError.self) { try context.save() }
            context.rollback()
            policy.update(.closed)
            preset.enabled = true
            try context.save()
            policy.beginTransition()
            defer { policy.endTransition() }
            preset.enabled = false
            try context.save() // Cancellation always remains allowed.
        }
    }
}
