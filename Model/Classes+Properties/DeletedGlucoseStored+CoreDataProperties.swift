import CoreData
import Foundation

public extension DeletedGlucoseStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<DeletedGlucoseStored> {
        NSFetchRequest<DeletedGlucoseStored>(entityName: "DeletedGlucoseStored")
    }

    @NSManaged var date: Date
    @NSManaged var glucose: Int16
    @NSManaged var isManualGlucoseEntry: Bool
}

extension DeletedGlucoseStored: Identifiable {}
