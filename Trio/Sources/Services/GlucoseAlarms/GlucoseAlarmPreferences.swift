import AVFoundation
import Combine
import Foundation

@MainActor final class GlucoseAlarmPreferences: ObservableObject {
    static let shared = GlucoseAlarmPreferences()
    static let changed = Foundation.Notification.Name("Trio.glucoseAlarmPreferencesChanged")
    typealias Tone = GlucoseAlarmTone
    private typealias Configuration = GlucoseAlarmConfiguration

    private static let key = "Trio.glucoseAlarms.configuration.v1"

    @Published var dayStartMinutes: Int { didSet { save() } }
    @Published var nightStartMinutes: Int { didSet { save() } }

    @Published var urgentLowActivePeriod: AlarmActivePeriod { didSet { save() } }
    @Published var lowActivePeriod: AlarmActivePeriod { didSet { save() } }
    @Published var highActivePeriod: AlarmActivePeriod { didSet { save() } }
    @Published var urgentHighActivePeriod: AlarmActivePeriod { didSet { save() } }
    @Published var missingGlucoseActivePeriod: AlarmActivePeriod { didSet { save() } }
    @Published var missingLoopActivePeriod: AlarmActivePeriod { didSet { save() } }

    @Published var lowEnabled: Bool { didSet { save() } }
    @Published var highEnabled: Bool { didSet { save() } }
    @Published var lowSnoozeMinutes: Int { didSet { save() } }
    @Published var highSnoozeMinutes: Int { didSet { save() } }
    @Published var alarmKit: Bool { didSet { save() } }
    @Published var lowTone: Tone { didSet { save() } }
    @Published var highTone: Tone { didSet { save() } }
    @Published var urgentLowEnabled: Bool { didSet { save() } }
    @Published var urgentHighEnabled: Bool { didSet { save() } }
    @Published var urgentLowThreshold: Decimal { didSet { save() } }
    @Published var urgentHighThreshold: Decimal { didSet { save() } }
    @Published var urgentLowSnoozeMinutes: Int { didSet { save() } }
    @Published var urgentHighSnoozeMinutes: Int { didSet { save() } }
    @Published var urgentLowTone: Tone { didSet { save() } }
    @Published var urgentHighTone: Tone { didSet { save() } }
    @Published var showMoreSettings: Bool { didSet { save() } }
    @Published var missingGlucose: MissingDataAlarmConfiguration { didSet { save() } }
    @Published var missingLoop: MissingDataAlarmConfiguration { didSet { save() } }
    private var player: AVAudioPlayer?

    private init() {
        let old = TrioApp.resolver.resolve(SettingsManager.self)!.settings
        let enabled = old.useAlarmSound && old.glucoseNotificationsOption != .disabled
        let saved = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Configuration.self, from: $0) }
        let config = saved ?? Configuration(lowEnabled: enabled, highEnabled: enabled)
        lowEnabled = config.lowEnabled
        highEnabled = config.highEnabled
        alarmKit = config.alarmKit
        lowSnoozeMinutes = config.resolvedLowSnooze
        highSnoozeMinutes = config.resolvedHighSnooze
        lowTone = config.lowTone
        highTone = config.highTone
        urgentLowEnabled = config.urgentLowEnabled ?? false
        urgentHighEnabled = config.urgentHighEnabled ?? false
        urgentLowThreshold = config.urgentLowThreshold ?? 40
        urgentHighThreshold = config.urgentHighThreshold ?? 400
        urgentLowSnoozeMinutes = Configuration.validatedSnooze(config.urgentLowSnoozeMinutes)
        urgentHighSnoozeMinutes = Configuration.validatedSnooze(config.urgentHighSnoozeMinutes)
        urgentLowTone = config.urgentLowTone ?? .urgentLow
        urgentHighTone = config.urgentHighTone ?? .critical
        showMoreSettings = config.showMoreSettings ?? false
        missingGlucose = config.missingGlucose ?? MissingDataAlarmConfiguration()
        missingLoop = config.missingLoop ?? .loopDefaults
        dayStartMinutes = Configuration.validatedTimeMinutes(
            config.dayStartMinutes,
            fallback: Configuration.defaultDayStartMinutes
        )

        nightStartMinutes = Configuration.validatedTimeMinutes(
            config.nightStartMinutes,
            fallback: Configuration.defaultNightStartMinutes
        )

        urgentLowActivePeriod = config.urgentLowActivePeriod ?? .always
        lowActivePeriod = config.lowActivePeriod ?? .always
        highActivePeriod = config.highActivePeriod ?? .always
        urgentHighActivePeriod = config.urgentHighActivePeriod ?? .always
        missingGlucoseActivePeriod = config.missingGlucoseActivePeriod ?? .always
        missingLoopActivePeriod = config.missingLoopActivePeriod ?? .always
        save()
    }

    private func save() {
        var config = Configuration(
            lowEnabled: lowEnabled, highEnabled: highEnabled, alarmKit: alarmKit,
            snoozeMinutes: nil,
            lowSnoozeMinutes: Configuration.validatedSnooze(lowSnoozeMinutes),
            highSnoozeMinutes: Configuration.validatedSnooze(highSnoozeMinutes), lowTone: lowTone, highTone: highTone
        )
        config.urgentLowEnabled = urgentLowEnabled
        config.urgentHighEnabled = urgentHighEnabled
        config.urgentLowThreshold = urgentLowThreshold
        config.urgentHighThreshold = urgentHighThreshold
        config.urgentLowSnoozeMinutes = urgentLowSnoozeMinutes
        config.urgentHighSnoozeMinutes = urgentHighSnoozeMinutes
        config.urgentLowTone = urgentLowTone
        config.urgentHighTone = urgentHighTone
        config.showMoreSettings = showMoreSettings
        config.missingGlucose = missingGlucose
        config.missingLoop = missingLoop
        config.dayStartMinutes = dayStartMinutes
        config.nightStartMinutes = nightStartMinutes
        config.urgentLowActivePeriod = urgentLowActivePeriod
        config.lowActivePeriod = lowActivePeriod
        config.highActivePeriod = highActivePeriod
        config.urgentHighActivePeriod = urgentHighActivePeriod
        config.missingGlucoseActivePeriod = missingGlucoseActivePeriod
        config.missingLoopActivePeriod = missingLoopActivePeriod
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.key) }
        Foundation.NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    func tone(for kind: GlucoseAlarmState.Kind) -> Tone {
        switch kind {
        case .low: return lowTone
        case .high: return highTone
        case .urgentLow: return urgentLowTone
        case .urgentHigh: return urgentHighTone
        }
    }

    func snoozeMinutes(for kind: GlucoseAlarmState.Kind?) -> Int {
        switch kind {
        case .low: return lowSnoozeMinutes
        case .high: return highSnoozeMinutes
        case .urgentLow: return urgentLowSnoozeMinutes
        case .urgentHigh: return urgentHighSnoozeMinutes
        case nil: return 15
        }
    }

    func preview(_ tone: Tone) {
        stopPreview()
        guard let url = Bundle.main.url(forResource: tone.rawValue, withExtension: nil) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch { debug(.service, "Glucose alarm preview failed: \(error)") }
    }

    func stopPreview() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func isDaytime(at date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)

        let currentMinutes =
            (components.hour ?? 0) * 60 +
            (components.minute ?? 0)

        let dayStart = dayStartMinutes
        let nightStart = nightStartMinutes

        // Om tiderna av någon anledning är identiska
        // behandlar vi hela dygnet som dagtid.
        guard dayStart != nightStart else {
            return true
        }

        // Normal variant, t.ex.:
        // dag 07:00 → 22:00
        if dayStart < nightStart {
            return currentMinutes >= dayStart &&
                currentMinutes < nightStart
        }

        // Dagtiden passerar midnatt, t.ex.:
        // dag 20:00 → 06:00
        return currentMinutes >= dayStart ||
            currentMinutes < nightStart
    }

    func isAllowed(
        during period: AlarmActivePeriod,
        at date: Date = Date()
    ) -> Bool {
        switch period {
        case .always:
            return true

        case .day:
            return isDaytime(at: date)

        case .night:
            return !isDaytime(at: date)
        }
    }

    func activePeriod(for kind: GlucoseAlarmState.Kind) -> AlarmActivePeriod {
        switch kind {
        case .urgentLow:
            return urgentLowActivePeriod
        case .low:
            return lowActivePeriod
        case .high:
            return highActivePeriod
        case .urgentHigh:
            return urgentHighActivePeriod
        }
    }
}
