import Foundation

struct NightscoutStatus: JSON {
    let device: String
    let openaps: OpenAPSStatus
    let pump: NSPumpStatus
    let uploader: Uploader
    var additional: [String: AdditionalValue]?
    let oref2: Oref2_variables?

    // Encode as ordinary JSON numbers/strings, preserving existing numeric fields.
    enum AdditionalValue: Codable, Equatable {
        case number(Decimal)
        case text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Decimal.self) {
                self = .number(value)
            } else {
                self = .text(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .number(value): try container.encode(value)
            case let .text(value): try container.encode(value)
            }
        }
    }
}

struct OpenAPSStatus: JSON {
    let iob: IOBEntry?
    let suggested: Determination?
    let enacted: Determination?
    let version: String
}

struct NSPumpStatus: JSON {
    let clock: Date
    let battery: Battery?
    let reservoir: Decimal?
    let status: PumpStatus?
}

struct Uploader: JSON {
    let batteryVoltage: Decimal?
    let battery: Int
    let isCharging: Bool?
}

struct NightscoutTimevalue: JSON {
    let time: String
    let value: Decimal
    let timeAsSeconds: Int?
}

struct ScheduledNightscoutProfile: JSON {
    let dia: Decimal
    let carbs_hr: Int
    let delay: Decimal
    let timezone: String
    let target_low: [NightscoutTimevalue]
    let target_high: [NightscoutTimevalue]
    let sens: [NightscoutTimevalue]
    let basal: [NightscoutTimevalue]
    let carbratio: [NightscoutTimevalue]
    let units: String
}

struct NightscoutProfileStore: JSON {
    let defaultProfile: String
    let startDate: Date
    let mills: Int
    let units: String
    let enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    let bundleIdentifier: String
    let deviceToken: String
    let isAPNSProduction: Bool
    let overridePresets: [NightscoutPresetOverride]?
    let teamID: String
    let preferences: NightscoutPreferences
    let expirationDate: Date?
}

/*
 struct NightscoutPresetOverride: JSON {
     let name: String
     let duration: Decimal?
     let percentage: Double?
     let target: Decimal?
 }
 */

struct NightscoutPresetOverride: JSON {
    let name: String
    let duration: Decimal?
    let percentage: Double?
    let target: Decimal?
    let smbMinutes: Decimal?
    let uamMinutes: Decimal?
    let smbIsOff: Bool
}
