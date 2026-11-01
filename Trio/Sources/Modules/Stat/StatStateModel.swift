import CoreData
import Foundation
import Observation
import SwiftUI
import Swinject

extension Stat {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        var highLimit: Decimal = 10 / 0.0555
        var lowLimit: Decimal = 4 / 0.0555
        var hbA1cDisplayUnit: HbA1cDisplayUnit = .percent
        var timeInRangeChartStyle: TimeInRangeChartStyle = .vertical
        var units: GlucoseUnits = .mgdL
        var glucoseFromPersistence: [GlucoseStored] = []

        @ObservationIgnored @Injected() var storage: FileStorage!
        var insulinToday: Insulin?
        var insulinDay: Insulin?
        var selectedDuration: Duration = .Today

        @MainActor func loadInsulinStatistics() async {
            let now = Date()
            let today = Calendar.current.startOfDay(for: now)
            let day = now.addingTimeInterval(-24 * 3600)
            let profile = await storage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
            let increment = settingsManager.preferences.bolusIncrement
            do {
                let totals = try await context.perform {
                    let rows = try PumpHistoryWindow.fetch(in: self.context, since: min(today, day))
                    let entries: [PumpEventDTO] = rows.flatMap { row -> [PumpEventDTO] in
                        guard let date = row.timestamp else { return [] }
                        let type: EventType? = row.tempBasal?.isScheduledBasal == true ? .scheduledBasal :
                            [.pumpSuspend, .pumpResume, .pumpDetached, .pumpAttached, .rewind, .prime]
                            .first { $0.rawValue == row.type }
                        if let type = type {
                            return [.marker(PumpHistoryEvent(id: row.id ?? "", type: type, timestamp: date))]
                        }
                        return [row.toBolusDTOEnum(), row.toTempBasalDurationDTOEnum(), row.toTempBasalDTOEnum()]
                            .compactMap { $0 }
                    }
                    guard !entries.isEmpty else { return (nil as Insulin?, nil as Insulin?) }
                    let json = try PumpEventDTO.json(entries)
                    guard let history = [PumpHistoryEvent](from: json) else { throw JSONError.invalidString }
                    let todayResult = try LocalInsulinHistory.calculate(
                        history: history, basal: profile, increment: increment, clock: now, since: today
                    )
                    let dayResult = try LocalInsulinHistory.calculate(
                        history: history, basal: profile, increment: increment, clock: now, since: day
                    )
                    return (todayResult.insulin as Insulin?, dayResult.insulin as Insulin?)
                }
                insulinToday = totals.0
                insulinDay = totals.1
            } catch {
                insulinToday = nil
                insulinDay = nil
                warning(.default, "Could not calculate insulin statistics", error: error)
            }
        }

        private let context = CoreDataStack.shared.newTaskContext()
        private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        enum Duration: String, CaseIterable, Identifiable {
            case Today
            case Day
            case Week
            case Month
            // case Total

            var id: Self { self }

            static var selectableCases: [Duration] {
                [.Today, .Day, .Week, .Month]
            }
        }

        override func subscribe() {
            /// Default is today
            setupGlucoseArray(for: .Today)
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            hbA1cDisplayUnit = settingsManager.settings.hbA1cDisplayUnit
            timeInRangeChartStyle = settingsManager.settings.timeInRangeChartStyle
        }

        func setupGlucoseArray(for duration: Duration) {
            Task {
                let ids = await self.fetchGlucose(for: duration)
                await updateGlucoseArray(with: ids)
            }
        }

        private func fetchGlucose(for duration: Duration) async -> [NSManagedObjectID] {
            let predicate: NSPredicate

            switch duration {
            case .Day:
                predicate = NSPredicate.glucoseForStatsDay
            case .Week:
                predicate = NSPredicate.glucoseForStatsWeek
            case .Today:
                predicate = NSPredicate.glucoseForStatsToday
            case .Month:
                predicate = NSPredicate.glucoseForStatsMonth
                // case .Total:
                // predicate = NSPredicate.glucoseForStatsMonth
            }

            let results = await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: predicate,
                key: "date",
                ascending: false,
                batchSize: 100,
                propertiesToFetch: ["glucose", "objectID"]
            )

            return await context.perform {
                guard let fetchedResults = results as? [[String: Any]] else { return [] }

                return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
            }
        }

        @MainActor private func updateGlucoseArray(with IDs: [NSManagedObjectID]) {
            do {
                let glucoseObjects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? GlucoseStored
                }
                glucoseFromPersistence = glucoseObjects
            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
                )
            }
        }
    }
}
