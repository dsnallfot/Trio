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

    // Optional additions keep older saved configurations readable.
    var urgentLowEnabled: Bool?
    var urgentHighEnabled: Bool?
    var urgentLowThreshold: Decimal?
    var urgentHighThreshold: Decimal?
    var urgentLowSnoozeMinutes: Int?
    var urgentHighSnoozeMinutes: Int?
    var urgentLowTone: GlucoseAlarmTone?
    var urgentHighTone: GlucoseAlarmTone?

    static func urgentLowThreshold(_ value: Decimal, low: Decimal) -> Decimal {
        max(40, min(value, low))
    }

    static func urgentHighThreshold(_ value: Decimal, high: Decimal) -> Decimal {
        min(400, max(value, high))
    }

    var lowTone: GlucoseAlarmTone = .urgentLow
    var highTone: GlucoseAlarmTone = .highChimes
}
