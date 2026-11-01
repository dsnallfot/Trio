import CoreData
import Foundation

public extension TempBasalStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempBasalStored> {
        NSFetchRequest<TempBasalStored>(entityName: "TempBasalStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var deliveredUnits: NSDecimalNumber?
    @NSManaged var isScheduledBasal: Bool
    @NSManaged var duration: Int16
    @NSManaged var rate: NSDecimalNumber?
    @NSManaged var tempType: String?
    @NSManaged var pumpEvent: PumpEventStored?
}

extension TempBasalStored: Identifiable {}
