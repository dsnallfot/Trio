import Foundation

enum JSONError: Error {
    case invalidString
    case invalidDate(String)
    case decodingFailed(Error)
    case encodingFailed
}

enum JSONBridge {
    static func preferences(from: JSON) throws -> Preferences {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func pumpSettings(from: JSON) throws -> PumpSettings {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func bgTargets(from: JSON) throws -> BGTargets {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func basalProfile(from: JSON) throws -> [BasalProfileEntry] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func trioCustomOrefVariables(from: JSON) throws -> TrioCustomOrefVariables {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func insulinSensitivities(from: JSON) throws -> InsulinSensitivities {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func carbRatios(from: JSON) throws -> CarbRatios {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func tempTargets(from: JSON) throws -> [TempTarget] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func model(from: JSON) -> String {
        from.rawJSON
    }

    static func trioSettings(from: JSON) throws -> TrioSettings {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func glucose(from: JSON) throws -> [BloodGlucose] {
        // Core Data emits id and either sgv or glucose, while BloodGlucose
        // expects _id and sgv. Normalize only this boundary, not stored data.
        guard var rows = try JSONSerialization.jsonObject(with: Data(from.rawJSON.utf8)) as? [[String: Any]] else {
            throw JSONError.invalidString
        }
        for index in rows.indices {
            rows[index]["_id"] = rows[index]["_id"] ?? rows[index]["id"] ?? "oref-\(index)"
            rows[index]["sgv"] = rows[index]["sgv"] ?? rows[index]["glucose"]
        }
        return try JSONCoding.decoder.decode([BloodGlucose].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    static func currentTemp(from: JSON, clock: Date) throws -> TempBasal {
        struct Input: Decodable {
            let duration: Int
            let rate: Decimal
            let temp: TempType
            let timestamp: Date?
        }
        let value: Input = try JSONBridge.from(string: from.rawJSON)
        return TempBasal(duration: value.duration, rate: value.rate, temp: value.temp, timestamp: value.timestamp ?? clock)
    }

    static func carbs(from: JSON) throws -> [CarbsEntry] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func iobResult(from: JSON) throws -> [IobResult] {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func pumpHistory(from: JSON) throws -> [PumpHistoryEvent] {
        do {
            return try JSONBridge.from(string: from.rawJSON)
        } catch {
            // see if we got an empty object "{}"
            guard let data = from.rawJSON.data(using: .utf8) else {
                throw error
            }

            if let parsedObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               parsedObject.isEmpty
            {
                return []
            }

            throw error
        }
    }

    static func profile(from: JSON) throws -> Profile {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func computedCarbs(from: JSON) throws -> ComputedCarbs? {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func autosens(from: JSON) throws -> SwiftOrefAutosens? {
        try JSONBridge.from(string: from.rawJSON)
    }

    static func clock(from: JSON) throws -> Date {
        let dateJson = from.rawJSON.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = Formatter.iso8601withFractionalSeconds.date(from: dateJson) ?? Formatter.iso8601
            .date(from: dateJson)
        {
            return date
        }

        throw JSONError.invalidDate(from.rawJSON)
    }

    static func from<T: Decodable>(string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw JSONError.invalidString
        }
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    static func to<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONCoding.encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONError.encodingFailed
        }
        return string
    }
}
