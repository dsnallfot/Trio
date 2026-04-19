import CoreData
import Foundation

public extension OverrideRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<OverrideRunStored> {
        NSFetchRequest<OverrideRunStored>(entityName: "OverrideRunStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var id: UUID?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var startDate: Date?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var override: OverrideStored?
    @NSManaged var enteredBy: String?
}

extension OverrideRunStored: Identifiable {}
