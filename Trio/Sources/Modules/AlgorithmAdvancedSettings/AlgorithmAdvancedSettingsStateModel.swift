import Combine
import Observation
import SwiftUI

extension AlgorithmAdvancedSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var storage: FileStorage!
        @Injected() var nightscout: NightscoutManager!

        @Published var useSwiftOref = false
        @Published var lastOrefRun = "Ingen körning registrerad"

        var units: GlucoseUnits = .mgdL

        @Published var maxDailySafetyMultiplier: Decimal = 3
        @Published var currentBasalSafetyMultiplier: Decimal = 4
        @Published var useCustomPeakTime: Bool = false
        @Published var insulinPeakTime: Decimal = 75
        @Published var skipNeutralTemps: Bool = false
        @Published var unsuspendIfNoTemp: Bool = false
        @Published var suspendZerosIOB: Bool = false
        @Published var min5mCarbimpact: Decimal = 8
        @Published var remainingCarbsFraction: Decimal = 1.0
        @Published var remainingCarbsCap: Decimal = 90
        @Published var noisyCGMTargetMultiplier: Decimal = 1.3
        @Published var insulinActionCurve: Decimal = 10

        var pumpSettings: PumpSettings {
            provider.settings()
        }

        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.useSwiftOref, on: $useSwiftOref) { useSwiftOref = $0 }
            broadcaster.register(DeterminationObserver.self, observer: self)
            updateOrefStatus()

            subscribePreferencesSetting(\.maxDailySafetyMultiplier, on: $maxDailySafetyMultiplier) {
                maxDailySafetyMultiplier = $0 }
            subscribePreferencesSetting(\.currentBasalSafetyMultiplier, on: $currentBasalSafetyMultiplier) {
                currentBasalSafetyMultiplier = $0 }
            subscribePreferencesSetting(\.useCustomPeakTime, on: $useCustomPeakTime) { useCustomPeakTime = $0 }
            subscribePreferencesSetting(\.insulinPeakTime, on: $insulinPeakTime) { insulinPeakTime = $0 }
            subscribePreferencesSetting(\.skipNeutralTemps, on: $skipNeutralTemps) { skipNeutralTemps = $0 }
            subscribePreferencesSetting(\.unsuspendIfNoTemp, on: $unsuspendIfNoTemp) { unsuspendIfNoTemp = $0 }
            subscribePreferencesSetting(\.suspendZerosIOB, on: $suspendZerosIOB) { suspendZerosIOB = $0 }
            subscribePreferencesSetting(\.min5mCarbimpact, on: $min5mCarbimpact) { min5mCarbimpact = $0 }
            subscribePreferencesSetting(\.remainingCarbsFraction, on: $remainingCarbsFraction) { remainingCarbsFraction = $0 }
            subscribePreferencesSetting(\.remainingCarbsCap, on: $remainingCarbsCap) { remainingCarbsCap = $0 }
            subscribePreferencesSetting(\.noisyCGMTargetMultiplier, on: $noisyCGMTargetMultiplier) {
                noisyCGMTargetMultiplier = $0 }

            insulinActionCurve = pumpSettings.insulinActionCurve
        }

        func updateOrefStatus() {
            if let run = storage.retrieve(OrefRunStatus.storageKey, as: OrefRunStatus.self) {
                lastOrefRun =
                    "\(run.engine.title) · \(run.date.formatted(date: .omitted, time: .shortened)) · \(Int(run.duration * 1000)) ms"
            }
        }

        var isPumpSettingUnchanged: Bool {
            pumpSettings.insulinActionCurve == insulinActionCurve
        }

        func saveIfChanged() {
            if !isPumpSettingUnchanged {
                let settings = PumpSettings(
                    insulinActionCurve: insulinActionCurve,
                    maxBolus: pumpSettings.maxBolus,
                    maxBasal: pumpSettings.maxBasal
                )
                provider.save(settings: settings)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        let settings = self.provider.settings()
                        self.insulinActionCurve = settings.insulinActionCurve

                        Task.detached(priority: .low) {
                            debug(.nightscout, "Attempting to upload DIA to Nightscout")
                            await self.nightscout.uploadProfiles(
                                alsoUploadNote: true,
                                note: "DIA-profil ändrades i Trio"
                            )
                        }
                    } receiveValue: {}
                    .store(in: &lifetime)
            }
        }
    }
}

extension AlgorithmAdvancedSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}

extension AlgorithmAdvancedSettings.StateModel: DeterminationObserver {
    func determinationDidUpdate(_: Determination) {
        DispatchQueue.main.async { self.updateOrefStatus() }
    }
}
