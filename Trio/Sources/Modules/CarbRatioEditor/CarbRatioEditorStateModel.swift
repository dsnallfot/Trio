import SwiftUI

extension CarbRatioEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var nightscout: NightscoutManager!
        @Injected() private var broadcaster: Broadcaster!
        @Published var items: [Item] = []
        @Published var initialItems: [Item] = []
        @Published var shouldDisplaySaving: Bool = false

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        let rateValues = stride(from: 30.0, to: 501.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            if initialItems.count != items.count {
                return true
            }

            for (initialItem, currentItem) in zip(initialItems, items) {
                if initialItem.rateIndex != currentItem.rateIndex || initialItem.timeIndex != currentItem.timeIndex {
                    return true
                }
            }

            return false
        }

        override func subscribe() {
            items = provider.profile.schedule.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.ratio) ?? 0
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
            shouldDisplaySaving = true

            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm"

            let schedule = items.map { item -> CarbRatioEntry in
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return CarbRatioEntry(start: formatter.string(from: date), offset: minutes, ratio: rate)
            }

            let changes: [(String, Decimal, Decimal)] = items.compactMap { newItem in
                guard let oldItem = initialItems.first(where: { $0.timeIndex == newItem.timeIndex }),
                      oldItem.rateIndex != newItem.rateIndex else { return nil }
                let date = Date(timeIntervalSince1970: self.timeValues[newItem.timeIndex])
                let timeString = formatter.string(from: date)
                let oldRate = rateValues[oldItem.rateIndex]
                let newRate = rateValues[newItem.rateIndex]
                return (timeString, oldRate, newRate)
            }

            let changesString = changes.map { "\($0.0) \($0.1)➔\($0.2)" }.joined(separator: ", ")
            let finalNote = "CR-profil ändrades: \(changesString) g/E"

            let profile = CarbRatios(units: .grams, schedule: schedule)
            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            DispatchQueue.main.async {
                self.broadcaster.notify(CarbRatiosObserver.self, on: .main) {
                    $0.carbRatiosDidChange(profile)
                }
            }

            Task.detached(priority: .low) {
                debug(.nightscout, "Attempting to upload CRs to Nightscout")
                await self.nightscout.uploadProfiles(alsoUploadNote: true, note: finalNote)
            }
        }

        func validate() {
            DispatchQueue.main.async {
                let uniq = Array(Set(self.items))
                var sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                if !sorted.isEmpty {
                    sorted[0].timeIndex = 0
                }
                if self.items != sorted {
                    self.items = sorted
                }
            }
        }
    }
}
