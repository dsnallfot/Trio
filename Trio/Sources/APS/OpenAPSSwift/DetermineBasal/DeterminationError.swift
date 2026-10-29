import Foundation

enum DeterminationError: LocalizedError, Equatable {
    case missingGlucoseStatus
    case missingProfile
    case missingCurrentBasal
    case invalidProfileTarget
    case glucoseOutOfRange(glucose: Decimal)
    case cgmNoiseTooHigh(noise: Int)
    case noDelta
    case missingIob
    case missingInputs
    case eventualGlucoseCalculationError(sensitivity: Decimal, deviation: Decimal)
    case determinationError

    var errorDescription: String? {
        switch self {
        case .missingGlucoseStatus:
            return String(localized: "Saknar glukosstatus; kan inte beräkna basal.")
        case .missingProfile:
            return String(localized: "Saknar profil; kan inte beräkna basal.")
        case .missingCurrentBasal:
            return String(localized: "Fel: kunde inte hämta aktuell basalhastighet")
        case .invalidProfileTarget:
            return String(localized: "Fel: kunde inte fastställa målglukos. ")
        case let .glucoseOutOfRange(glucose):
            return String(localized: "Glukosvärde utanför tillåtet intervall: \(glucose.description).")
        case let .cgmNoiseTooHigh(noise):
            return String(localized: "För hög störningsnivå i CGM-data: \(noise).")
        case .noDelta:
            return String(localized: "Ingen glukosförändring (oförändrade värden); kan inte avgöra trend.")
        case .missingIob:
            return String(localized: "Saknar IOB-data; kan inte beräkna basal.")
        case .missingInputs:
            return String(localized: "Nödvändiga indata saknas; kan inte beräkna basal.")
        case let .eventualGlucoseCalculationError(sensitivity, deviation):
            return String(
                localized: "Kunde inte beräkna förväntat glukosvärde. Insulinkänslighet: \(sensitivity.description), Avvikelse: \(deviation.description)"
            )
        case .determinationError:
            return String(localized: "Okänt fel vid beräkning av basal.")
        }
    }
}
