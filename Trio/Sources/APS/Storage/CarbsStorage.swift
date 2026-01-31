import Combine
import CoreData
import Foundation
import SwiftDate
import Swinject

protocol CarbsObserver {
    func carbsDidUpdate(_ carbs: [CarbsEntry])
}

protocol CarbsStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    func storeCarbs(_ carbs: [CarbsEntry], areFetchedFromRemote: Bool) async
    func deleteCarbsEntryStored(_ treatmentObjectID: NSManagedObjectID) async
    func syncDate() -> Date
    func recent() -> [CarbsEntry]
    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func getCarbsNotYetUploadedToHealth() async -> [CarbsEntry]
    func getCarbsNotYetUploadedToTidepool() async -> [CarbsEntry]
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let coredataContext = CoreDataStack.shared.newTaskContext()

    private let updateSubject = PassthroughSubject<Void, Never>()

    private let settingsProvider = PickerSettingsProvider.shared

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        var entriesToStore = entries

        if areFetchedFromRemote {
            entriesToStore = await filterRemoteEntries(entries: entriesToStore)
        }

        // Check for FPU-only entries (fat/protein without carbs)
        let fpuOnlyEntries = entriesToStore.filter { entry in
            entry.carbs == 0 && (entry.fat ?? 0 > 0 || entry.protein ?? 0 > 0)
        }

        // Create additional Carb (non-FPU) entries with fat/protein amounts and carbs == 0
        for entry in fpuOnlyEntries {
            let additionalEntry = CarbsEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                actualDate: entry.actualDate,
                carbs: Decimal(0),
                fat: entry.fat,
                protein: entry.protein,
                note: entry.note,
                enteredBy: entry.enteredBy,
                isFPU: false, // it should be a Carb entry
                fpuID: entry.fpuID
            )
            entriesToStore.append(additionalEntry)
        }

        await saveCarbsToCoreData(entries: entriesToStore, areFetchedFromRemote: areFetchedFromRemote)
        await saveCarbEquivalents(entries: entriesToStore, areFetchedFromRemote: areFetchedFromRemote)
    }

    private func filterRemoteEntries(entries: [CarbsEntry]) async -> [CarbsEntry] {
        // Fetch only the date property from Core Data
        guard let existing24hCarbEntries = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false,
            batchSize: 50,
            propertiesToFetch: ["date", "objectID"]
        ) as? [[String: Any]] else {
            return entries
        }

        // Extract dates into a set for efficient lookup
        // Since we are not dealing with NSManagedObjects directly it is safe to pass properties between threads
        let existingTimestamps = Set(existing24hCarbEntries.compactMap { $0["date"] as? Date })

        // Remove all entries that have a matching date in existingTimestamps
        var filteredEntries = entries
        filteredEntries.removeAll { entry in
            let entryDate = entry.actualDate ?? entry.createdAt
            return existingTimestamps.contains(entryDate)
        }

        return filteredEntries
    }

    /**
     Calculates the duration for processing FPUs (fat and protein units) based on the FPUs and the time cap.

     - The function uses predefined rules to determine the duration based on the number of FPUs.
     - Ensures that the duration does not exceed the time cap.

     - Parameters:
       - fpus: The number of FPUs calculated from fat and protein.
       - timeCap: The maximum allowed duration.

     - Returns: The computed duration in hours.
     */
    private func calculateComputedDuration(fpus: Decimal, timeCap: Int) -> Int {
        switch fpus {
        case ..<2:
            return 3
        case 2 ..< 3:
            return 4
        case 3 ..< 4:
            return 5
        default:
            return timeCap
        }
    }

    /**
     Converts fat and protein into delayed carb-equivalent entries (FPU handling).

     Behavior:

          - Calculates carb equivalents from fat and protein
            ((fat × 9 + protein × 4) / 10 × adjustment factor).
          - Rounds down to whole grams.
          - Drops values below 10 g.
          - Caps total equivalents at 99 g.
          - Splits into up to 3 entries.
          - Caps each entry at 33 g.
          - Distributes grams as evenly as possible.

          Timing:

          - First entry is scheduled after the configured delay
            (default: 60 minutes) from the carb entry timestamp.
          - Additional entries are spaced 30 minutes apart.

          Example (default):

          - Carb entry at T
          - 1st equivalent at T + 60 min
          - 2nd equivalent at T + 90 min
          - 3rd equivalent at T + 120 min

          Generated entries:

          - Are marked with `isFPU = true`
          - Contain only carbs (fat and protein set to 0)
          - Share the same `fpuID` as the original carb entry

     - Parameters:
       - entries: An array of `CarbsEntry` objects representing the carb equivalent entries to be processed.
       - fat: The amount of fat in the last entry.
       - protein: The amount of protein in the last entry.
       - createdAt: The creation date of the last entry.

     - Returns: A tuple containing the array of future carb entries and the total carb equivalents.
     */
    private func processFPU(
        entries: [CarbsEntry],
        fat: Decimal,
        protein: Decimal,
        createdAt: Date,
        actualDate: Date?
    ) -> ([CarbsEntry], Decimal) {
        let trioSettings = settings.settings
        let providerSettings = settingsProvider.settings

        let adjustment = trioSettings.individualAdjustmentFactor.clamp(to: providerSettings.individualAdjustmentFactor)

        let delayMinutes = trioSettings.delay.clamp(to: providerSettings.delay)

        // Constraints
        let maxTotalGrams = 99
        let maxEntries = 3
        let maxPerEntry = 33
        let minPerEntry = 10
        let spacing: TimeInterval = 30 * 60

        // kcal -> carb equivalents (kcal/10 * adjustment), rounded down to whole grams
        let kcal = protein * 4 + fat * 9
        let rawEquivalents = Int((kcal / 10) * adjustment)
        let totalGrams = min(maxTotalGrams, max(0, rawEquivalents))

        guard totalGrams >= minPerEntry else {
            return ([], Decimal(totalGrams))
        }

        let amounts = splitIntoCarbEquivalents(
            total: totalGrams,
            maxEntries: maxEntries,
            maxPerEntry: maxPerEntry,
            minPerEntry: minPerEntry
        )

        let baseDate = actualDate ?? createdAt
        let start = baseDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
        let fpuID = entries.first?.fpuID ?? UUID().uuidString

        let futureEntries: [CarbsEntry] = amounts.enumerated().map { idx, grams in
            CarbsEntry(
                id: UUID().uuidString,
                createdAt: createdAt,
                actualDate: start.addingTimeInterval(TimeInterval(idx) * spacing),
                carbs: Decimal(grams),
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.local,
                isFPU: true,
                fpuID: fpuID
            )
        }

        let totalScheduled = futureEntries.reduce(into: Decimal(0)) { $0 += $1.carbs }
        return (futureEntries, totalScheduled)
    }

    /**
     Splits a total carb-equivalent value into multiple integer entries.

     - Returns no entries if `total` is below `minPerEntry`.
     - Limits output to `maxEntries`.
     - Caps each entry at `maxPerEntry`.
     - Distributes grams evenly (difference ≤ 1 g).
     - Merges or removes entries below `minPerEntry`.

     - Returns:
       Integer gram values representing the split carb equivalents.
     */
    private func splitIntoCarbEquivalents(
        total: Int,
        maxEntries: Int,
        maxPerEntry: Int,
        minPerEntry: Int
    ) -> [Int] {
        guard total >= minPerEntry else { return [] }

        // Choose an entry count that *guarantees* each entry can be <= maxPerEntry
        let needed = (total + maxPerEntry - 1) / maxPerEntry
        let count = min(maxEntries, max(1, needed))

        // Even split (difference between buckets is at most 1)
        func evenSplit(_ total: Int, count: Int) -> [Int] {
            let base = total / count
            let rem = total % count
            return (0 ..< count).map { base + ($0 < rem ? 1 : 0) }
        }

        var buckets = evenSplit(total, count: count)

        // Enforce minPerEntry by merging any too-small tail bucket into the previous one
        // This should be rare, but it keeps the invariant
        if buckets.count > 1 {
            for i in stride(from: buckets.count - 1, through: 1, by: -1) {
                let v = buckets[i]
                guard v > 0, v < minPerEntry else { continue }
                buckets[i - 1] += v
                buckets[i] = 0
            }
            buckets = buckets.filter { $0 > 0 }
        }

        // Guarantee not to exceed maxPerEntry if merging a reduced count
        // Clamp as final guard here
        buckets = buckets.map { min(maxPerEntry, $0) }.filter { $0 >= minPerEntry }

        return buckets
    }

    private func saveCarbEquivalents(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        guard let lastEntry = entries.last else { return }

        if let fat = lastEntry.fat, let protein = lastEntry.protein, fat > 0 || protein > 0 {
            let (futureCarbEquivalents, carbEquivalentCount) = processFPU(
                entries: entries,
                fat: fat,
                protein: protein,
                createdAt: lastEntry.createdAt,
                actualDate: lastEntry.actualDate
            )

            if carbEquivalentCount > 0 {
                await saveFPUToCoreDataAsBatchInsert(entries: futureCarbEquivalents, areFetchedFromRemote: areFetchedFromRemote)
            }
        }
    }

    private func saveCarbsToCoreData(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        guard let entry = entries.last else { return }

        await coredataContext.perform {
            let newItem = CarbEntryStored(context: self.coredataContext)
            newItem.date = entry.actualDate ?? entry.createdAt
            newItem.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            newItem.fat = Double(truncating: NSDecimalNumber(decimal: entry.fat ?? 0))
            newItem.protein = Double(truncating: NSDecimalNumber(decimal: entry.protein ?? 0))
            newItem.note = entry.note
            newItem.id = UUID()
            newItem.isFPU = false
            newItem.isUploadedToNS = areFetchedFromRemote ? true : false
            newItem.isUploadedToHealth = false
            newItem.isUploadedToTidepool = false

            if entry.fat != nil, entry.protein != nil, let fpuId = entry.fpuID {
                newItem.fpuID = UUID(uuidString: fpuId)
            }

            do {
                guard self.coredataContext.hasChanges else { return }
                try self.coredataContext.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func saveFPUToCoreDataAsBatchInsert(entries: [CarbsEntry], areFetchedFromRemote: Bool) async {
        let commonFPUID = UUID(
            uuidString: entries.first?.fpuID ?? UUID()
                .uuidString
        ) // all fpus should only get ONE id per batch insert to be able to delete them referencing the fpuID
        var entrySlice = ArraySlice(entries) // convert to ArraySlice
        let batchInsert = NSBatchInsertRequest(entity: CarbEntryStored.entity()) { (managedObject: NSManagedObject) -> Bool in
            guard let carbEntry = managedObject as? CarbEntryStored, let entry = entrySlice.popFirst(),
                  let entryId = entry.id
            else {
                return true // return true to stop
            }
            carbEntry.date = entry.actualDate
            carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            carbEntry.id = UUID.init(uuidString: entryId)
            carbEntry.fpuID = commonFPUID
            carbEntry.isFPU = true
            carbEntry.isUploadedToNS = areFetchedFromRemote ? true : false
            // do NOT set Health and Tidepool flags to ensure they will NOT be uploaded
            return false // return false to continue
        }
        await coredataContext.perform {
            do {
                try self.coredataContext.execute(batchInsert)
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.succeeded) saved fpus to core data")

                // Notify subscriber in Home State Model to update the FPU Array
                self.updateSubject.send(())
            } catch {
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.failed) error while saving fpus to core data")
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() -> [CarbsEntry] {
        storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)?.reversed() ?? []
    }

    func deleteCarbsEntryStored(_ treatmentObjectID: NSManagedObjectID) async {
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteCarbs"

        var carbEntryFromCoreData: CarbEntryStored?

        await taskContext.perform {
            do {
                carbEntryFromCoreData = try taskContext.existingObject(with: treatmentObjectID) as? CarbEntryStored
                guard let carbEntry = carbEntryFromCoreData else {
                    debugPrint("Carb entry for batch delete not found. \(DebuggingIdentifiers.failed)")
                    return
                }

                // entry has fpuID
                // case 1: carb equivalent entry
                // case 2: "parent" entry, but containing fat and/or protein, and possibly carbs
                // => use fpuID ID to delete all corresponding entries via batch delete
                if let fpuID = carbEntry.fpuID {
                    // fetch request for all carb entries with the same id
                    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CarbEntryStored.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "fpuID == %@", fpuID as CVarArg)

                    // NSBatchDeleteRequest
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    deleteRequest.resultType = .resultTypeCount

                    // execute the batch delete request
                    let result = try taskContext.execute(deleteRequest) as? NSBatchDeleteResult
                    debugPrint("\(DebuggingIdentifiers.succeeded) Deleted \(result?.result ?? 0) items with FpuID \(fpuID)")

                    // Notifiy subscribers of the batch delete
                    self.updateSubject.send(())
                }
                // entry has no fpuID
                // => it's a carb-only entry. use its ID to for deletion
                else {
                    taskContext.delete(carbEntry)

                    guard taskContext.hasChanges else { return }
                    try taskContext.save()

                    debugPrint(
                        "CarbsStorage: \(#function) \(DebuggingIdentifiers.succeeded) deleted carb entry from core data"
                    )
                }

            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Error deleting carb entry: \(error.localizedDescription)")
            }
        }
    }

    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.carbsNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return await coredataContext.perform {
            guard let carbEntries = results as? [CarbEntryStored] else {
                return []
            }

            return carbEntries.map { result in
                let originalNote = result.note ?? ""
                // Regex pattern breakdown:
                //   ^(.*?)             -> capture any text at the start (non-greedy) as the note text.
                //   \s*Inlagt av:\s*   -> match "Inlagt av:" with optional surrounding whitespace.
                //   (Trio\s*\(.*?\))   -> capture "Trio" followed by optional whitespace, an opening parenthesis,
                //                         any text non-greedily, and a closing parenthesis.
                //   \s*$               -> match any trailing whitespace until the end.
                let pattern = "^(.*?)\\s*Inlagt av:\\s*(Trio\\s*\\(.*?\\))\\s*$"
                var cleanedNote = originalNote
                var enteredBy: String = CarbsEntry.local

                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(originalNote.startIndex..., in: originalNote)
                    if let match = regex.firstMatch(in: originalNote, options: [], range: range),
                       let noteRange = Range(match.range(at: 1), in: originalNote),
                       let enteredByRange = Range(match.range(at: 2), in: originalNote)
                    {
                        // The note is the text before "Inlagt av:".
                        cleanedNote = String(originalNote[noteRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        // The enteredBy value is the entire text starting with "Trio" including the parentheses.
                        enteredBy = String(originalNote[enteredByRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                return NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: enteredBy,
                    bolus: nil,
                    insulin: nil,
                    notes: cleanedNote,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: cleanedNote,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.id?.uuidString
                )
            }
        }
    }

    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.fpusNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return await coredataContext.perform {
            guard let fpuEntries = results as? [CarbEntryStored] else { return [] }

            return fpuEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.local,
                    bolus: nil,
                    insulin: nil,
                    notes: "Fett/Protein", // result.note,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: "", // result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.fpuID?.uuidString
                )
            }
        }
    }

    func getCarbsNotYetUploadedToHealth() async -> [CarbsEntry] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.carbsNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        guard let carbEntries = results as? [CarbEntryStored] else {
            return []
        }

        return await coredataContext.perform {
            return carbEntries.map { result in
                CarbsEntry(
                    id: result.id?.uuidString,
                    createdAt: result.date ?? Date(),
                    actualDate: result.date,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    note: result.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: result.isFPU,
                    fpuID: result.fpuID?.uuidString
                )
            }
        }
    }

    func getCarbsNotYetUploadedToTidepool() async -> [CarbsEntry] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.carbsNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        guard let carbEntries = results as? [CarbEntryStored] else {
            return []
        }

        return await coredataContext.perform {
            return carbEntries.map { result in
                CarbsEntry(
                    id: result.id?.uuidString,
                    createdAt: result.date ?? Date(),
                    actualDate: result.date,
                    carbs: Decimal(result.carbs),
                    fat: nil,
                    protein: nil,
                    note: result.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: nil,
                    fpuID: nil
                )
            }
        }
    }
}
