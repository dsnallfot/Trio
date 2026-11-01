import CoreData
import Foundation

@objc(OverrideStored) public class OverrideStored: NSManagedObject {
    override public func validateForInsert() throws {
        try super.validateForInsert()
        if enabled { try AdjustmentActivationPolicy.shared.validateActivation() }
    }

    override public func validateForUpdate() throws {
        try super.validateForUpdate()
        if enabled {
            try AdjustmentActivationPolicy.shared.validateActivation()
        }
    }
}
