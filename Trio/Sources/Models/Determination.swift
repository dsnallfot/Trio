import Foundation

struct DeterminationErrorResponse: JSON, Equatable {
    let error: String
}

struct Determination: JSON, Equatable {
    let id: UUID?
    var reason: String
    var units: Decimal?
    var insulinReq: Decimal?
    var eventualBG: Int?
    let sensitivityRatio: Decimal?
    var rate: Decimal?
    var duration: Decimal?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
    let carbsReq: Decimal?
    let temp: TempType?
    var bg: Decimal?
    var reservoir: Decimal?
    var isf: Decimal?
    var timestamp: Date?
    var tdd: Decimal?
    var insulin: Insulin?
    var current_target: Decimal?
    var insulinForManualBolus: Decimal?
    var manualBolusErrorString: Decimal?
    var minDelta: Decimal?
    var expectedDelta: Decimal?
    var minGuardBG: Decimal?
    var minPredBG: Decimal?
    var threshold: Decimal?
    let carbRatio: Decimal?
    let received: Bool?
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

struct Insulin: JSON, Equatable {
    let TDD: Decimal?
    let bolus: Decimal?
    let temp_basal: Decimal?
    let scheduled_basal: Decimal?
}

extension Determination {
    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case isf = "ISF"
        case tdd = "TDD"
        case insulin
        case current_target
        case insulinForManualBolus
        case manualBolusErrorString
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
        case received
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

extension Insulin {
    private enum CodingKeys: String, CodingKey {
        case TDD
        case bolus
        case temp_basal
        case scheduled_basal
    }
}

protocol DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination)
}

extension Determination {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
