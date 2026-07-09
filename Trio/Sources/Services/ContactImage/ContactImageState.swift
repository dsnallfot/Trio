import Foundation

struct ContactImageState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var fifteenMinBg: String?
    var lastLoopDate: Date?
    var lastBGDate: Date?
    var forceStaleBG: Bool = false
    var iob: Decimal?
    var iobText: String?
    var cob: Decimal?
    var cobText: String?
    var eventualBG: String?
    var maxIOB: Decimal = 5.0
    var maxCOB: Decimal = 120.0
    var highGlucoseColorValue: Decimal = 180.0
    var lowGlucoseColorValue: Decimal = 70.0
    var glucoseColorScheme: GlucoseColorScheme = .staticColor
    var targetGlucose: Decimal = 100.0
    var fifteenLabel: String?
    var iobLabel: String?
    var cobLabel: String?
    var loopLabel: String?
}
