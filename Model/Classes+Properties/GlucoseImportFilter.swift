import CoreData
import Foundation

/// Shared timestamp matching for persisted readings and deletion records.
/// Call on the context's queue, in the same operation as the subsequent insert.
enum GlucoseImportFilter {
    static func acceptedIndices(
        dates: [Date],
        entityName: String,
        context: NSManagedObjectContext,
        timeBuffer: TimeInterval,
        deduplicateBatch: Bool
    ) throws -> [Int] {
        guard let first = dates.min(), let last = dates.max() else { return [] }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            first.addingTimeInterval(-timeBuffer) as NSDate,
            last.addingTimeInterval(timeBuffer) as NSDate
        )
        request.propertiesToFetch = ["date"]
        request.resultType = .dictionaryResultType
        var occupiedDates = try context.fetch(request).compactMap { $0["date"] as? Date }
        var accepted: [Int] = []
        // Drivers may send newest first. Use a stable order for intra-batch spacing.
        for index in dates.indices.sorted(by: { dates[$0] < dates[$1] }) {
            let date = dates[index]
            guard !occupiedDates.contains(where: { abs($0.timeIntervalSince(date)) <= timeBuffer }) else { continue }
            accepted.append(index)
            if deduplicateBatch {
                occupiedDates.append(date)
            }
        }
        return accepted
    }
}
