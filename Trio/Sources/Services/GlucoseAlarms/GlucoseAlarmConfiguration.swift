import Foundation

enum GlucoseAlarmTone: String, CaseIterable, Identifiable, Codable {
    case urgentLow = "urgent_low.caf"
    case highChimes = "high_chimes.caf"
    case chime = "chime.caf"
    case critical = "critical.caf"
    case alarm = "alarm.caf"
    case brightAlarm = "bright_alarm.caf"
    case honk = "honk.caf"
    case trill = "trill.caf"
    case clearChimes = "clear_chimes.caf"
    case dings = "dings.caf"
    case bloom = "bloom.caf"
    case bloop = "bloop.caf"
    case spring = "spring.caf"
    case minimal = "minimal.caf"
    case simple = "simple.caf"
    case synth = "synth.caf"
    case moodSynth = "mood_synth.caf"
    case crying = "crying.caf"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .urgentLow: return "Lågt glukos"
        case .highChimes: return "Höga toner"
        case .chime: return "Klockspel"
        case .critical: return "Kritiskt"
        case .alarm: return "Alarm"
        case .brightAlarm: return "Ljust alarm"
        case .honk: return "Signalhorn"
        case .trill: return "Drill"
        case .clearChimes: return "Klara klockor"
        case .dings: return "Pling"
        case .bloom: return "Bloom"
        case .bloop: return "Bloop"
        case .spring: return "Spring"
        case .minimal: return "Minimal"
        case .simple: return "Enkelt"
        case .synth: return "Synth"
        case .moodSynth: return "Mjuk synth"
        case .crying: return "Gråt"
        }
    }
}

enum AlarmActivePeriod: String, CaseIterable, Identifiable, Codable {
    case always
    case day
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always:
            return "Alltid"
        case .day:
            return "Dagtid"
        case .night:
            return "Nattid"
        }
    }
}

struct GlucoseAlarmConfiguration: Codable {
    var lowEnabled: Bool
    var highEnabled: Bool
    var alarmKit = true
    // Optional so existing saved configurations decode without resetting their choices.
    var snoozeMinutes: Int? = 15 // Legacy shared choice, used only when migrating.
    var lowSnoozeMinutes: Int?
    var highSnoozeMinutes: Int?

    var resolvedLowSnooze: Int { Self.validatedSnooze(lowSnoozeMinutes ?? snoozeMinutes) }
    var resolvedHighSnooze: Int { Self.validatedSnooze(highSnoozeMinutes ?? snoozeMinutes) }

    static let snoozeChoices = Array(stride(from: 5, through: 60, by: 5))
    static func validatedSnooze(_ minutes: Int?) -> Int {
        guard let minutes, snoozeChoices.contains(minutes) else { return 15 }
        return minutes
    }

    // Day / night configuration.
    // Optional so existing saved configurations remain readable.
    var dayStartMinutes: Int?
    var nightStartMinutes: Int?

    var urgentLowActivePeriod: AlarmActivePeriod?
    var lowActivePeriod: AlarmActivePeriod?
    var highActivePeriod: AlarmActivePeriod?
    var urgentHighActivePeriod: AlarmActivePeriod?
    var missingGlucoseActivePeriod: AlarmActivePeriod?
    var missingLoopActivePeriod: AlarmActivePeriod?
    var urgentLowEnabled: Bool?
    var urgentHighEnabled: Bool?
    var urgentLowThreshold: Decimal?
    var urgentHighThreshold: Decimal?
    var urgentLowSnoozeMinutes: Int?
    var urgentHighSnoozeMinutes: Int?
    var urgentLowTone: GlucoseAlarmTone?
    var urgentHighTone: GlucoseAlarmTone?
    var showMoreSettings: Bool?
    var missingGlucose: MissingDataAlarmConfiguration?
    var missingLoop: MissingDataAlarmConfiguration?

    static func urgentLowThreshold(_ value: Decimal, low: Decimal) -> Decimal {
        max(40, min(value, low))
    }

    static func urgentHighThreshold(_ value: Decimal, high: Decimal) -> Decimal {
        min(400, max(value, high))
    }

    var lowTone: GlucoseAlarmTone = .urgentLow
    var highTone: GlucoseAlarmTone = .highChimes

    static let defaultDayStartMinutes = 7 * 60 // 07:00
    static let defaultNightStartMinutes = 22 * 60 // 22:00

    static func validatedTimeMinutes(_ value: Int?, fallback: Int) -> Int {
        guard let value else { return fallback }
        return min(23 * 60 + 59, max(0, value))
    }
}

struct MissingDataAlarmConfiguration: Codable, Equatable {
    var enabled = false
    var first = 15
    var second = 30
    var tone: GlucoseAlarmTone = .chime
    static let choices = Array(stride(from: 10, through: 60, by: 5))
    static let loopDefaults = Self(first: 20, second: 40)
    static var savedLoop: Self {
        UserDefaults.standard.data(forKey: "Trio.glucoseAlarms.configuration.v1")
            .flatMap { try? JSONDecoder().decode(GlucoseAlarmConfiguration.self, from: $0) }?.missingLoop ?? .loopDefaults
    }

    var intervals: [Int] {
        Array(Set([Self.valid(first, fallback: 15), Self.valid(second, fallback: 30)])).sorted()
    }

    static func valid(_ value: Int, fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }
}
