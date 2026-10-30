import Foundation

enum TempBasalFunctionError: LocalizedError, Equatable {
    case invalidBasalRateOnProfile

    var errorDescription: String? {
        switch self {
        case .invalidBasalRateOnProfile:
            return "The currentBasal, maxBasal, or maxDailyBasal wasn't set on Profile"
        }
    }
}

enum TempBasalFunctions {
    /// Rounds basal rates to match the basal increment for the pump as the basal rate increases
    static func roundBasal(profile: Profile, basalRate: Decimal) -> Decimal {
        // FIXME: Should we just call the pumpManager here?

        let lowestRateScale: Decimal
        if let model = profile.model, model.hasSuffix("54") || model.hasSuffix("23") {
            lowestRateScale = 40
        } else {
            lowestRateScale = 20
        }

        let roundedBasal: Decimal
        if basalRate < 1 {
            roundedBasal = (basalRate * lowestRateScale).jsRounded() / lowestRateScale
        } else if basalRate < 10 {
            roundedBasal = (basalRate * 20).jsRounded() / 20
        } else {
            roundedBasal = (basalRate * 10).jsRounded() / 10
        }

        return roundedBasal
    }

    /// defines the max safe basal rate given a profile
    static func getMaxSafeBasalRate(profile: Profile) throws -> Decimal {
        // use default values if either of these are NaN
        let maxDailySafetyMultiplier = profile.maxDailySafetyMultiplier.isNaN ? 3 : profile.maxDailySafetyMultiplier
        let currentBasalSafetyMultiplier = profile.currentBasalSafetyMultiplier.isNaN ? 4 : profile.currentBasalSafetyMultiplier

        guard let currentBasal = profile.currentBasal, let maxDailyBasal = profile.maxDailyBasal,
              let maxBasal = profile.maxBasal
        else {
            throw TempBasalFunctionError.invalidBasalRateOnProfile
        }

        return min(
            maxBasal,
            maxDailySafetyMultiplier * maxDailyBasal,
            currentBasalSafetyMultiplier * currentBasal
        )
    }

    static func setTempBasal(
        rate: Decimal,
        duration: Decimal,
        profile: Profile,
        determination: Determination,
        currentTemp: TempBasal
    ) throws -> Determination {
        var determination = determination
        let maxSafeBasal = try getMaxSafeBasalRate(profile: profile)

        var rate = rate
        if rate < 0 {
            rate = 0
        } else if rate > maxSafeBasal {
            rate = maxSafeBasal
        }

        let suggestedRate = roundBasal(profile: profile, basalRate: rate)

        if Decimal(currentTemp.duration) > (duration - 10),
           currentTemp.duration <= 120,
           suggestedRate <= currentTemp.rate * 1.2,
           suggestedRate >= currentTemp.rate * 0.8,
           duration > 0
        {
            determination
                .reason += " \(currentTemp.duration)m kvar och \(currentTemp.rate) ~ behov \(suggestedRate)E/h: ingen temp krävs"
            return determination
        }

        if suggestedRate == profile.currentBasal {
            if profile.skipNeutralTemps {
                if currentTemp.duration > 0 {
                    determination
                        .reason = determination.reason +
                        ". Föreslagen basal är samma som profilbasal: en temp är aktiv: avbryter nuvarande temp"
                    determination.duration = 0
                    determination.rate = 0
                    return determination
                } else {
                    determination
                        .reason = determination.reason +
                        ". Föreslagen basal är samma som profilbasal: ingen temp är aktiv: ingen åtgärd"
                    return determination
                }
            } else {
                determination.reason = determination.reason + ". Ställer in neutral temp basal \(profile.currentBasal ?? 0)E/h"
                determination.duration = duration
                determination.rate = suggestedRate
                return determination
            }
        } else {
            determination.duration = duration
            determination.rate = suggestedRate
            return determination
        }
    }
}
