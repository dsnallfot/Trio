import AppIntents
import CoreData
import Foundation
import HealthKit

// Daniel: Added appintent to be able to delete meal entries via remote triggered automation
@available(iOS 16.0, *) struct DeleteCarbEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete Carbs"
    static var description = IntentDescription("Deletes a carb entry based on a specified date and time.")

    @Parameter(title: "Date", description: "The date and time (hh:mm:ss) for the carb entry to delete")  var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Delete carb entry at \(\.$date)")
    }

    @MainActor  func perform() async throws -> some ProvidesDialog {
        debugPrint("DeleteCarbEntryIntent started at \(Date())")

        let resolver = TrioApp.resolver

        // Resolve dependencies:
        let provider: DataTable.Provider = resolver.resolve(DataTable.Provider.self) ?? DataTable.Provider(resolver: resolver)
        guard let carbsStorage: CarbsStorage = resolver.resolve(CarbsStorage.self) else {
            fatalError("CarbsStorage not available")
        }
        guard let apsManager: APSManager = resolver.resolve(APSManager.self) else {
            fatalError("APSManager not available")
        }

        // Use second-level precision.
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let startDate = calendar.date(from: components) else {
            throw NSError(domain: "DeleteCarbEntryIntent", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid date"])
        }
        let endDate = startDate.addingTimeInterval(60) // Using a 60-second window
        debugPrint("Searching for entries between \(startDate) and \(endDate)")

        // Fetch the matching carb entry's objectID from a background context.
        let backgroundContext = CoreDataStack.shared.newTaskContext()
        var matchingEntries: [CarbEntryStored] = []
        try await backgroundContext.perform {
            let request: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate)
            request.fetchLimit = 1
            matchingEntries = try backgroundContext.fetch(request)
            debugPrint("Fetched \(matchingEntries.count) matching entries in background context")
        }

        guard let fetchedObjectID = matchingEntries.first?.objectID else {
            debugPrint("No matching carb entry found.")
            return .result(dialog: IntentDialog(stringLiteral: "No matching carb entry found at \(startDate.formatted())."))
        }
        debugPrint("Fetched objectID: \(fetchedObjectID)")

        // Re-fetch the object on the main context (or a context on the main actor) so it's safe to use.
        let mainContext = CoreDataStack.shared.persistentContainer.viewContext
        let entryToDelete: CarbEntryStored = try await mainContext.perform {
            guard let entry = try mainContext.existingObject(with: fetchedObjectID) as? CarbEntryStored else {
                throw NSError(
                    domain: "DeleteCarbEntryIntent",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to re-fetch entry on main context"]
                )
            }
            debugPrint("Re-fetched entry on main context: \(entry)")
            return entry
        }

        // Now safely access properties on the main-context object.
        debugPrint("Entry date: \(entryToDelete.date?.formatted() ?? "nil"), carbs: \(entryToDelete.carbs)")
        let isFpuOrComplexMeal = entryToDelete.isFPU || (entryToDelete.fat > 0) || (entryToDelete.protein > 0)
        debugPrint("isFpuOrComplexMeal: \(isFpuOrComplexMeal)")
        let treatmentObjectID = entryToDelete.objectID
        debugPrint("Treatment ObjectID: \(treatmentObjectID)")

        // Delete from remote services.
        debugPrint("Starting deletion from remote services...")
        // For complex meals, we simply use the original objectID.
        if isFpuOrComplexMeal {
            debugPrint("Complex meal detected; using original objectID for remote deletion.")
        }
        await deleteFromServices(treatmentObjectID, provider: provider)
        debugPrint("Remote service deletion complete.")

        // Delete the entry from Core Data.
        debugPrint("Deleting entry from Core Data...")
        await carbsStorage.deleteCarbsEntryStored(treatmentObjectID)
        debugPrint("Core Data deletion complete.")

        // Trigger additional sync logic.
        debugPrint("Triggering basal sync...")
        await apsManager.determineBasalSync()
        debugPrint("Basal sync triggered.")

        debugPrint("DeleteCarbEntryIntent finished at \(Date())")
        return .result(dialog: IntentDialog(stringLiteral: "Deleted carb entry at \(startDate.formatted())."))
    }

    // MARK: - Helper Functions

    /// Deletes entries from remote services using the provided provider.
    func deleteFromServices(_ treatmentObjectID: NSManagedObjectID, provider: DataTable.Provider) async {
        debugPrint("deleteFromServices started for objectID: \(treatmentObjectID)")
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteCarbsFromServices"

        await taskContext.perform {
            do {
                guard let carbEntry = try taskContext.existingObject(with: treatmentObjectID) as? CarbEntryStored else {
                    debugPrint("Carb entry for deletion not found in deleteFromServices.")
                    return
                }
                debugPrint("Deleting remote services for carbEntry: \(carbEntry)")

                // If the entry has an FPU ID, delete FPU-related remote data.
                if let fpuID = carbEntry.fpuID {
                    debugPrint("Deleting FPU related entries for fpuID: \(fpuID.uuidString)")
                    provider.deleteCarbsFromNightscout(withID: fpuID.uuidString)

                    let healthObjectsToDelete: [HKSampleType?] = [
                        AppleHealthConfig.healthFatObject,
                        AppleHealthConfig.healthProteinObject
                    ]

                    for sampleType in healthObjectsToDelete {
                        if let validSampleType = sampleType {
                            debugPrint(
                                "Deleting meal data from Health for fpuID: \(fpuID.uuidString) and sampleType: \(validSampleType)"
                            )
                            provider.deleteMealDataFromHealth(byID: fpuID.uuidString, sampleType: validSampleType)
                        }
                    }
                }

                // Delete carb entries if they exist.
                if let id = carbEntry.id, let entryDate = carbEntry.date {
                    debugPrint("Deleting carb entry remote services for id: \(id.uuidString)")
                    provider.deleteCarbsFromNightscout(withID: id.uuidString)

                    if let sampleType = AppleHealthConfig.healthCarbObject {
                        debugPrint("Deleting carb meal data from Health for id: \(id.uuidString)")
                        provider.deleteMealDataFromHealth(byID: id.uuidString, sampleType: sampleType)
                    }

                    debugPrint("Deleting carb entry from Tidepool for id: \(id.uuidString)")
                    provider.deleteCarbsFromTidepool(
                        withSyncId: id,
                        carbs: Decimal(carbEntry.carbs),
                        at: entryDate,
                        enteredBy: CarbsEntry.local
                    )
                }
            } catch {
                debugPrint("Error in deleteFromServices: \(error.localizedDescription)")
            }
        }
        debugPrint("deleteFromServices finished for objectID: \(treatmentObjectID)")
    }
}
