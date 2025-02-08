import CoreData
import Foundation

@available(iOS 16.0,*) final class CarbPresetIntentRequest: BaseIntentsRequest {
    func addCarbs(
        _ quantityCarbs: Double,
        _ quantityFat: Double,
        _ quantityProtein: Double,
        _ dateAdded: Date,
        _ note: String?
    ) async throws -> String {
        guard quantityCarbs >= 0.0 || quantityFat >= 0.0 || quantityProtein >= 0.0 else {
            return "registrerar inte måltid i Trio"
        }

        let carbs = min(Decimal(quantityCarbs), settingsManager.settings.maxCarbs)

        await carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: dateAdded,
                actualDate: dateAdded,
                carbs: carbs,
                fat: Decimal(quantityFat),
                protein: Decimal(quantityProtein),
                note: (note?.isEmpty ?? true) ? "✨" : note!,
                enteredBy: CarbsEntry.local,
                isFPU: false, fpuID: nil
            )],
            areFetchedFromRemote: false
        )
        var resultDisplay: String
        resultDisplay = "\(carbs) g kh"
        if quantityFat > 0.0 {
            resultDisplay = "\(resultDisplay) och \(quantityFat) g fett"
        }
        if quantityProtein > 0.0 {
            resultDisplay = "\(resultDisplay) och \(quantityProtein) g protein"
        }
        let dateName = dateAdded.formatted()
        resultDisplay = "\(resultDisplay) lades till \(dateName)"
        return resultDisplay
    }
}
