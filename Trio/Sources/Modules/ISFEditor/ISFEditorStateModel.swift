import CoreData
import Observation
import SwiftUI

extension ISFEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!

        var items: [Item] = []
        var initialItems: [Item] = []
        var shouldDisplaySaving: Bool = false

        let context = CoreDataStack.shared.newTaskContext()

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var rateValues: [Decimal] {
            var values = stride(from: 9, to: 540.01, by: 1.0).map { Decimal($0) }

            if units == .mmolL {
                values = values.filter { Int(truncating: $0 as NSNumber) % 2 == 0 }
            }

            return values
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        private(set) var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units

            let profile = provider.profile

            items = profile.sensitivities.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.sensitivity) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }

            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
        }

        func add() {
            var time = 0
            var rate = 0
            if let last = items.last {
                time = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, timeIndex: time)

            items.append(newItem)
        }

        func save() {
            guard hasChanges else { return }
            shouldDisplaySaving.toggle()

            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm"

            let sensitivities = items.map { item -> InsulinSensitivityEntry in
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: formatter.string(from: date))
            }

            let changes: [(String, String, String)] = items.compactMap { newItem in
                guard let oldItem = initialItems.first(where: { $0.timeIndex == newItem.timeIndex }),
                      oldItem.rateIndex != newItem.rateIndex else { return nil }
                let date = Date(timeIntervalSince1970: self.timeValues[newItem.timeIndex])
                let timeString = formatter.string(from: date)
                let oldRate = units == .mgdL ? rateValues[oldItem.rateIndex].description : rateValues[oldItem.rateIndex]
                    .formattedAsMmolL
                let newRate = units == .mgdL ? rateValues[newItem.rateIndex].description : rateValues[newItem.rateIndex]
                    .formattedAsMmolL
                return (timeString, oldRate, newRate)
            }

            let changesString = changes.map { "\($0.0) \($0.1)➔\($0.2)" }.joined(separator: ", ")
            let finalNote = "ISF-profil ändrades: \(changesString) mmol/L/E"

            let profile = InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: sensitivities
            )

            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            Task.detached(priority: .low) {
                debug(.nightscout, "Attempting to upload ISF to Nightscout")
                await self.nightscout.uploadProfiles(alsoUploadNote: true, note: finalNote)
            }
        }

        func validate() {
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    let uniq = Array(Set(self.items))
                    var sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                    if !sorted.isEmpty {
                        sorted[0].timeIndex = 0
                    }
                    if self.items != sorted {
                        self.items = sorted
                    }
                    if self.items.isEmpty {
                        self.units = self.settingsManager.settings.units
                    }
                }
            }
        }
    }
}

extension ISFEditor.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
