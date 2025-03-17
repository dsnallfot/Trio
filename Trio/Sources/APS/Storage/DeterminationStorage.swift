import Combine
import CoreData
import Foundation
import Swinject

protocol DeterminationStorage {
    func fetchLastDeterminationObjectID(predicate: NSPredicate) async -> [NSManagedObjectID]
    func getForecastIDs(for determinationID: NSManagedObjectID, in context: NSManagedObjectContext) async -> [NSManagedObjectID]
    func getForecastValueIDs(for forecastID: NSManagedObjectID, in context: NSManagedObjectContext) async -> [NSManagedObjectID]
    func fetchForecastObjects(
        for data: (id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID]),
        in context: NSManagedObjectContext
    ) async -> (UUID, Forecast?, [ForecastValue])
    func getOrefDeterminationNotYetUploadedToNightscout(_ determinationIds: [NSManagedObjectID]) async
        -> Determination? // Daniel: No longer used due to uploading the latest suggested/enacted determainations regardless of isuploaded flag
    func fetchLatestSuggestedDetermination() async -> Determination?
    func fetchLatestEnactedDetermination() async -> Determination?
}

final class BaseDeterminationStorage: DeterminationStorage, Injectable {
    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func fetchLastDeterminationObjectID(predicate: NSPredicate) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: predicate,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1
        )

        return await backgroundContext.perform {
            guard let fetchedResults = results as? [OrefDetermination] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    func getForecastIDs(for determinationID: NSManagedObjectID, in context: NSManagedObjectContext) async -> [NSManagedObjectID] {
        await context.perform {
            do {
                guard let determination = try context.existingObject(with: determinationID) as? OrefDetermination,
                      let forecastSet = determination.forecasts
                else {
                    return []
                }
                let forecasts = Array(forecastSet)
                return forecasts.map(\.objectID) as [NSManagedObjectID]
            } catch {
                debugPrint(
                    "Failed \(DebuggingIdentifiers.failed) to fetch Forecast IDs for OrefDetermination with ID \(determinationID): \(error.localizedDescription)"
                )
                return []
            }
        }
    }

    func getForecastValueIDs(for forecastID: NSManagedObjectID, in context: NSManagedObjectContext) async -> [NSManagedObjectID] {
        await context.perform {
            do {
                guard let forecast = try context.existingObject(with: forecastID) as? Forecast,
                      let forecastValueSet = forecast.forecastValues
                else {
                    return []
                }
                let forecastValues = forecastValueSet.sorted(by: { $0.index < $1.index })
                return forecastValues.map(\.objectID)
            } catch {
                debugPrint(
                    "Failed \(DebuggingIdentifiers.failed) to fetch Forecast Value IDs with ID \(forecastID): \(error.localizedDescription)"
                )
                return []
            }
        }
    }

    // Fetch forecast value IDs for a given data set
    func fetchForecastObjects(
        for data: (id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID]),
        in context: NSManagedObjectContext
    ) async -> (UUID, Forecast?, [ForecastValue]) {
        return await context.perform {
            var forecast: Forecast?
            var forecastValues: [ForecastValue] = []

            do {
                // Fetch the forecast object
                forecast = try context.existingObject(with: data.forecastID) as? Forecast

                // Fetch the first 3h of forecast values
                for forecastValueID in data.forecastValueIDs.prefix(36) {
                    if let forecastValue = try context.existingObject(with: forecastValueID) as? ForecastValue {
                        forecastValues.append(forecastValue)
                    }
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch forecast Values with error: \(error.localizedDescription)"
                )
            }
            return (data.id, forecast, forecastValues)
        }
    }

    // Convert NSDecimalNumber to Decimal
    func decimal(from nsDecimalNumber: NSDecimalNumber?) -> Decimal {
        nsDecimalNumber?.decimalValue ?? 0.0
    }

    // Convert NSSet to array of Ints for Predictions
    func parseForecastValues(ofType type: String, from determinationID: NSManagedObjectID) async -> [Int]? {
        let forecastIDs = await getForecastIDs(for: determinationID, in: backgroundContext)

        var forecastValuesList: [Int] = []

        for forecastID in forecastIDs {
            await backgroundContext.perform {
                if let forecast = try? self.backgroundContext.existingObject(with: forecastID) as? Forecast {
                    // Filter the forecast based on the type
                    if forecast.type == type {
                        let forecastValueIDs = forecast.forecastValues?.sorted(by: { $0.index < $1.index }).map(\.objectID) ?? []

                        for forecastValueID in forecastValueIDs {
                            if let forecastValue = try? self.backgroundContext
                                .existingObject(with: forecastValueID) as? ForecastValue
                            {
                                let forecastValueInt = Int(forecastValue.value)
                                forecastValuesList.append(forecastValueInt)
                            }
                        }
                    }
                }
            }
        }

        return forecastValuesList.isEmpty ? nil : forecastValuesList
    }

    // Daniel: No longer used due to uploading the latest suggested/enacted determainations regardless of isuploaded flag
    func getOrefDeterminationNotYetUploadedToNightscout(_ determinationIds: [NSManagedObjectID]) async -> Determination? {
        var result: Determination?

        guard let determinationId = determinationIds.first else {
            return nil
        }

        let predictions = Predictions(
            iob: await parseForecastValues(ofType: "iob", from: determinationId),
            zt: await parseForecastValues(ofType: "zt", from: determinationId),
            cob: await parseForecastValues(ofType: "cob", from: determinationId),
            uam: await parseForecastValues(ofType: "uam", from: determinationId)
        )

        return await backgroundContext.perform {
            do {
                let orefDetermination = try self.backgroundContext.existingObject(with: determinationId) as? OrefDetermination

                // Check if the fetched object is of the expected type
                if let orefDetermination = orefDetermination {
                    result = Determination(
                        id: orefDetermination.id ?? UUID(),
                        reason: orefDetermination.reason ?? "",
                        units: orefDetermination.smbToDeliver as Decimal?,
                        insulinReq: self.decimal(from: orefDetermination.insulinReq),
                        eventualBG: orefDetermination.eventualBG as? Int,
                        sensitivityRatio: self.decimal(from: orefDetermination.sensitivityRatio),
                        rate: self.decimal(from: orefDetermination.rate),
                        duration: self.decimal(from: orefDetermination.duration),
                        iob: self.decimal(from: orefDetermination.iob),
                        cob: Decimal(orefDetermination.cob),
                        predictions: predictions,
                        deliverAt: orefDetermination.deliverAt,
                        carbsReq: orefDetermination.carbsRequired != 0 ? Decimal(orefDetermination.carbsRequired) : nil,
                        temp: TempType(rawValue: orefDetermination.temp ?? "absolute"),
                        bg: self.decimal(from: orefDetermination.glucose),
                        reservoir: self.decimal(from: orefDetermination.reservoir),
                        isf: self.decimal(from: orefDetermination.insulinSensitivity),
                        timestamp: orefDetermination.timestamp,
                        tdd: self.decimal(from: orefDetermination.totalDailyDose),
                        insulin: nil,
                        current_target: self.decimal(from: orefDetermination.currentTarget),
                        insulinForManualBolus: self.decimal(from: orefDetermination.insulinForManualBolus),
                        manualBolusErrorString: self.decimal(from: orefDetermination.manualBolusErrorString),
                        minDelta: self.decimal(from: orefDetermination.minDelta),
                        expectedDelta: self.decimal(from: orefDetermination.expectedDelta),
                        minGuardBG: nil,
                        minPredBG: nil,
                        threshold: self.decimal(from: orefDetermination.threshold),
                        carbRatio: self.decimal(from: orefDetermination.carbRatio),
                        received: orefDetermination.enacted // this is actually part of NS...
                    )
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch managed object with error: \(error.localizedDescription)"
                )
            }

            return result
        }
    }

    func fetchLatestSuggestedDetermination() async -> Determination? {
        // Build a predicate that only cares about the date (ignoring the isUploadedToNS flag)
        let predicate = NSPredicate(format: "deliverAt >= %@", Date.oneDayAgo as NSDate)

        // Fetch the latest suggested determination (sorted by deliverAt descending)
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: predicate,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1
        )

        guard let fetchedResults = results as? [OrefDetermination],
              let latestDetermination = fetchedResults.first
        else {
            return nil
        }

        // Parse forecast values as before
        let predictions = Predictions(
            iob: await parseForecastValues(ofType: "iob", from: latestDetermination.objectID),
            zt: await parseForecastValues(ofType: "zt", from: latestDetermination.objectID),
            cob: await parseForecastValues(ofType: "cob", from: latestDetermination.objectID),
            uam: await parseForecastValues(ofType: "uam", from: latestDetermination.objectID)
        )

        // Map the Core Data object to your Determination struct.
        return await backgroundContext.perform {
            Determination(
                id: latestDetermination.id ?? UUID(),
                reason: latestDetermination.reason ?? "",
                units: latestDetermination.smbToDeliver as Decimal?,
                insulinReq: self.decimal(from: latestDetermination.insulinReq),
                eventualBG: latestDetermination.eventualBG as? Int,
                sensitivityRatio: self.decimal(from: latestDetermination.sensitivityRatio),
                rate: self.decimal(from: latestDetermination.rate),
                duration: self.decimal(from: latestDetermination.duration),
                iob: self.decimal(from: latestDetermination.iob),
                cob: Decimal(latestDetermination.cob),
                predictions: predictions,
                deliverAt: latestDetermination.deliverAt,
                carbsReq: latestDetermination.carbsRequired != 0 ? Decimal(latestDetermination.carbsRequired) : nil,
                temp: TempType(rawValue: latestDetermination.temp ?? "absolute"),
                bg: self.decimal(from: latestDetermination.glucose),
                reservoir: self.decimal(from: latestDetermination.reservoir),
                isf: self.decimal(from: latestDetermination.insulinSensitivity),
                timestamp: latestDetermination.timestamp,
                tdd: self.decimal(from: latestDetermination.totalDailyDose),
                insulin: nil,
                current_target: self.decimal(from: latestDetermination.currentTarget),
                insulinForManualBolus: self.decimal(from: latestDetermination.insulinForManualBolus),
                manualBolusErrorString: self.decimal(from: latestDetermination.manualBolusErrorString),
                minDelta: self.decimal(from: latestDetermination.minDelta),
                expectedDelta: self.decimal(from: latestDetermination.expectedDelta),
                minGuardBG: nil,
                minPredBG: nil,
                threshold: self.decimal(from: latestDetermination.threshold),
                carbRatio: self.decimal(from: latestDetermination.carbRatio),
                received: latestDetermination.enacted
            )
        }
    }

    func fetchLatestEnactedDetermination() async -> Determination? {
        // Build a predicate that fetches all records where enacted is true,
        // regardless of age.
        let predicate = NSPredicate(format: "enacted == %@", true as NSNumber)

        // Fetch the latest enacted determination using the predicate.
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: predicate,
            key: "deliverAt", // Or "timestamp" if that is preferred.
            ascending: false,
            fetchLimit: 1
        )

        // Ensure we have at least one result.
        guard let fetchedResults = results as? [OrefDetermination],
              let latestDetermination = fetchedResults.first
        else {
            return nil
        }

        // Parse the predictions using the objectID of the fetched determination.
        let predictions = Predictions(
            iob: await parseForecastValues(ofType: "iob", from: latestDetermination.objectID),
            zt: await parseForecastValues(ofType: "zt", from: latestDetermination.objectID),
            cob: await parseForecastValues(ofType: "cob", from: latestDetermination.objectID),
            uam: await parseForecastValues(ofType: "uam", from: latestDetermination.objectID)
        )

        // Map the Core Data object to your Determination struct.
        return await backgroundContext.perform { () -> Determination? in
            Determination(
                id: latestDetermination.id ?? UUID(),
                reason: latestDetermination.reason ?? "",
                units: latestDetermination.smbToDeliver as Decimal?,
                insulinReq: self.decimal(from: latestDetermination.insulinReq),
                eventualBG: latestDetermination.eventualBG as? Int,
                sensitivityRatio: self.decimal(from: latestDetermination.sensitivityRatio),
                rate: self.decimal(from: latestDetermination.rate),
                duration: self.decimal(from: latestDetermination.duration),
                iob: self.decimal(from: latestDetermination.iob),
                cob: Decimal(latestDetermination.cob),
                predictions: predictions,
                deliverAt: latestDetermination.deliverAt,
                carbsReq: latestDetermination.carbsRequired != 0 ? Decimal(latestDetermination.carbsRequired) : nil,
                temp: TempType(rawValue: latestDetermination.temp ?? "absolute"),
                bg: self.decimal(from: latestDetermination.glucose),
                reservoir: self.decimal(from: latestDetermination.reservoir),
                isf: self.decimal(from: latestDetermination.insulinSensitivity),
                timestamp: latestDetermination.timestamp,
                tdd: self.decimal(from: latestDetermination.totalDailyDose),
                insulin: nil,
                current_target: self.decimal(from: latestDetermination.currentTarget),
                insulinForManualBolus: self.decimal(from: latestDetermination.insulinForManualBolus),
                manualBolusErrorString: self.decimal(from: latestDetermination.manualBolusErrorString),
                minDelta: self.decimal(from: latestDetermination.minDelta),
                expectedDelta: self.decimal(from: latestDetermination.expectedDelta),
                minGuardBG: nil,
                minPredBG: nil,
                threshold: self.decimal(from: latestDetermination.threshold),
                carbRatio: self.decimal(from: latestDetermination.carbRatio),
                received: latestDetermination.enacted
            )
        }
    }
}
