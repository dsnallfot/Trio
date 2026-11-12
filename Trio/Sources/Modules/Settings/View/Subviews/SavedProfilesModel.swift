import Combine
import Foundation
import LoopKit
import Swinject

@MainActor final class SavedProfilesModel: ObservableObject {
    @Published private(set) var profiles: [SavedTherapyProfile] = []
    @Published private(set) var current: SavedTherapyProfile?
    @Published private(set) var isActivating = false
    @Published var errorMessage: String?

    private static var activationInProgress = false

    private let resolver: Resolver
    private let storage: FileStorage
    private let deviceManager: DeviceDataManager
    private let broadcaster: Broadcaster
    private let nightscout: NightscoutManager
    private let filename = "settings/saved-therapy-profiles.json"

    var units: GlucoseUnits { resolver.resolve(SettingsManager.self)!.settings.units }

    init(resolver: Resolver) {
        self.resolver = resolver
        storage = resolver.resolve(FileStorage.self)!
        deviceManager = resolver.resolve(DeviceDataManager.self)!
        broadcaster = resolver.resolve(Broadcaster.self)!
        nightscout = resolver.resolve(NightscoutManager.self)!
    }

    func reload() {
        guard !isActivating else { return }
        profiles = storage.retrieve(filename, as: [SavedTherapyProfile].self) ?? []
        current = SavedTherapyProfile(
            name: "Aktuell profil",
            basal: BasalProfileEditor.Provider(resolver: resolver).profile,
            sensitivities: ISFEditor.Provider(resolver: resolver).profile,
            carbRatios: CarbRatioEditor.Provider(resolver: resolver).profile,
            targets: TargetsEditor.Provider(resolver: resolver).profile
        )
    }

    func save(_ snapshot: SavedTherapyProfile, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, snapshot.isValid else {
            errorMessage = "Profilen saknar ett namn eller innehåller ogiltiga inställningar."
            return false
        }
        var saved = snapshot
        saved.id = UUID()
        saved.name = name
        let updated = profiles + [saved]
        storage.save(updated, as: filename)
        guard let persisted = storage.retrieve(filename, as: [SavedTherapyProfile].self),
              persisted.contains(where: { $0.id == saved.id })
        else {
            errorMessage = "Profilen kunde inte sparas. Försök igen."
            return false
        }
        profiles = persisted
        return true
    }

    func activate(_ profile: SavedTherapyProfile) async -> Bool {
        guard !Self.activationInProgress else {
            errorMessage = "En profilaktivering pågår redan. Vänta tills den är klar."
            return false
        }
        guard profile.isValid else {
            errorMessage = "Profilen innehåller ogiltiga eller ofullständiga inställningar."
            return false
        }
        guard let pump = deviceManager.pumpManager else {
            errorMessage = "Ingen pump är ansluten. Inga inställningar har ändrats."
            return false
        }
        let durations = zip(profile.basal, profile.basal.dropFirst().map(\.minutes) + [1440])
        guard profile.basal.count <= pump.maximumBasalScheduleEntryCount,
              profile.basal.allSatisfy({ entry in
                  pump.supportedBasalRates.contains { abs($0 - Double(entry.rate)) < 0.000001 }
              }),
              durations.allSatisfy({
                  let duration = TimeInterval(($0.1 - $0.0.minutes) * 60)
                  let increment = pump.minimumBasalScheduleEntryDuration
                  return increment > 0 && duration >= increment && duration.truncatingRemainder(dividingBy: increment) == 0
              })
        else {
            errorMessage = "Profilens basalschema stöds inte av den anslutna pumpen. Inga inställningar har ändrats."
            return false
        }

        Self.activationInProgress = true
        isActivating = true
        errorMessage = nil
        defer {
            isActivating = false
            Self.activationInProgress = false
        }
        let schedule = profile.basal.map {
            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
        }
        do {
            // Do not cancel or time out locally: a late pump acknowledgement must still be handled.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pump.syncBasalRateSchedule(items: schedule) { result in
                    continuation.resume(with: result.map { _ in () })
                }
            }
        } catch {
            errorMessage =
                "Basalprofilen kunde inte bekräftas av pumpen. Inga inställningar i Trio har ändrats. \(error.localizedDescription)"
            return false
        }

        // Keep all four writes together under the storage queue lock.
        storage.transaction { storage in
            storage.save(profile.basal, as: OpenAPS.Settings.basalProfile)
            storage.save(profile.sensitivities, as: OpenAPS.Settings.insulinSensitivities)
            storage.save(profile.carbRatios, as: OpenAPS.Settings.carbRatios)
            storage.save(profile.targets, as: OpenAPS.Settings.bgTargets)
        }
        broadcaster.notify(BasalProfileObserver.self, on: .main) { $0.basalProfileDidChange(profile.basal) }
        broadcaster.notify(InsulinSensitivitiesObserver.self, on: .main) {
            $0.insulinSensitivitiesDidChange(profile.sensitivities)
        }
        broadcaster.notify(CarbRatiosObserver.self, on: .main) { $0.carbRatiosDidChange(profile.carbRatios) }
        broadcaster.notify(BGTargetsObserver.self, on: .main) { $0.bgTargetsDidChange(profile.targets) }
        current = profile
        // Keep the existing Nightscout format and profile name (default).
        await nightscout.uploadProfiles(alsoUploadNote: true, note: "Sparad profil aktiverades: '\(profile.name)'")
        return true
    }
}
