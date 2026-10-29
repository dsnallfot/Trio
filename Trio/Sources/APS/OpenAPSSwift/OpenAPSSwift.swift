import Foundation

struct OpenAPSSwift {
    static func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        trioSettings: JSON,
        clock: Date
    ) -> (OrefFunctionResult) {
        do {
            let preferences = try JSONBridge.preferences(from: preferences)
            let pumpSettings = try JSONBridge.pumpSettings(from: pumpSettings)
            var bgTargets = try JSONBridge.bgTargets(from: bgTargets)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            var isf = try JSONBridge.insulinSensitivities(from: isf)
            let carbRatio = try JSONBridge.carbRatios(from: carbRatio)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)
            let model = JSONBridge.model(from: model)
            _ = trioSettings // Existing JS profile also derives output units from bgTargets.

            // Match prepare/profile.js: convert input schedules, retain display units.
            if bgTargets.units == .mmolL {
                bgTargets.targets = bgTargets.targets
                    .map { BGTargetEntry(low: $0.low * 18, high: $0.high * 18, start: $0.start, offset: $0.offset) }
                bgTargets.units = .mgdL
            }
            if isf.units == .mmolL {
                isf.sensitivities = isf.sensitivities
                    .map { InsulinSensitivityEntry(sensitivity: $0.sensitivity * 18, offset: $0.offset, start: $0.start) }
                isf.units = .mgdL
            }
            let profile = try ProfileGenerator.generate(
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                preferences: preferences,
                carbRatios: carbRatio,
                tempTargets: tempTargets,
                model: model,
                clock: clock
            )

            return (try .success(JSONBridge.to(profile)))
        } catch {
            return (.failure(error))
        }
    }

    static func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON,
        preferences: JSON,
        basalProfile: JSON,
        trioCustomOrefVariables: JSON,
        clock: Date
    ) -> (OrefFunctionResult) {
        do {
            let glucose = try JSONBridge.glucose(from: glucose)
            let currentTemp = try JSONBridge.currentTemp(from: currentTemp, clock: clock)
            let iob = try JSONBridge.iobResult(from: iob)
            var profile = try JSONBridge.profile(from: profile)
            let autosens = try JSONBridge.autosens(from: autosens)
            let meal = try JSONBridge.computedCarbs(from: meal)
            let microBolusAllowed = microBolusAllowed
            let reservoir = Decimal(string: reservoir.rawJSON)
            let pumpHistory = try JSONBridge.pumpHistory(from: pumpHistory)
            var preferences = try JSONBridge.preferences(from: preferences)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let history = try LocalInsulinHistory.calculate(
                history: pumpHistory,
                basal: basalProfile,
                increment: profile.bolusIncrement,
                clock: clock
            )
            let legacyVariables: Oref2_variables = try JSONBridge.from(string: trioCustomOrefVariables.rawJSON)
            let variables = LocalOrefCompatibility.variables(legacyVariables, currentTDD: history.total)
            if !history.allowsDynamicISF { preferences.useNewFormula = false }
            profile.highTemptargetRaisesSensitivity = profile.highTemptargetRaisesSensitivity || preferences.exerciseMode

            guard let mealData = meal else {
                return .failure(DeterminationError.missingInputs)
            }

            if let early = try LocalOrefCompatibility.invalidGlucoseResult(
                glucose: glucose,
                profile: profile,
                currentTemp: currentTemp,
                variables: variables,
                clock: clock
            ) {
                return .success(early)
            }
            var rawDetermination = try DeterminationGenerator.generate(
                profile: profile,
                preferences: preferences,
                currentTemp: currentTemp,
                iobData: iob,
                mealData: mealData,
                autosensData: autosens ?? SwiftOrefAutosens(ratio: 1, newisf: nil),
                reservoirData: reservoir ?? 100,
                glucose: glucose,
                microBolusAllowed: microBolusAllowed && glucose.first?.glucose != 400 && glucose.first?.sgv != 400,
                trioCustomOrefVariables: variables,
                currentTime: clock,
                localCompatibility: true
            )

            // Early error/cancel returns deliberately keep these fields absent.
            if rawDetermination?.bg != nil {
                rawDetermination?.tdd = history.total.jsRounded(scale: 2)
                rawDetermination?.insulin = history.insulin
                if var reason = rawDetermination?.reason {
                    let summary: String
                    if history.hours > 21, history.total > 0 {
                        let bolusPercent = ((history.insulin.bolus ?? 0) / history.total * 100).jsRounded()
                        let basalPercent = (
                            ((history.insulin.temp_basal ?? 0) + (history.insulin.scheduled_basal ?? 0)) / history
                                .total * 100
                        ).jsRounded()
                        summary = ", TDD: \(history.total.jsRounded(scale: 2)) E, \(bolusPercent)% Bolus \(basalPercent)% Basal"
                    } else {
                        summary = ", TDD: Otillräcklig pumpdata (< 21h)"
                    }
                    let insertion = reason.range(of: "; ")?.lowerBound ?? reason.endIndex
                    reason.insert(contentsOf: summary, at: insertion)
                    rawDetermination?.reason = reason
                }
                rawDetermination?.reservoir = reservoir
                if let threshold = rawDetermination?.threshold {
                    rawDetermination?.threshold = DosingEngine.convertGlucose(profile: profile, glucose: threshold)
                }
            }
            return try .success(JSONBridge.to(rawDetermination))

        } catch let determinationError as DeterminationError {
            // if we get a determination error we want to return it as a JSON
            // object that is { "error": "some error" }
            do {
                let response = try JSONBridge.to(DeterminationErrorResponse(error: determinationError.localizedDescription))
                return .success(response)
            } catch {
                return .failure(determinationError)
            }
        } catch {
            return .failure(error)
        }
    }

    static func meal(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: JSON,
        glucose: JSON
    ) -> (OrefFunctionResult) {
        do {
            let pumpHistory = LocalOrefCompatibility.calculationHistory(try JSONBridge.pumpHistory(from: pumphistory))
            let profile = try JSONBridge.profile(from: profile)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let clock = try JSONBridge.clock(from: clock)
            let carbs = try JSONBridge.carbs(from: carbs)
            let glucose = try JSONBridge.glucose(from: glucose)

            var mealResult = try MealGenerator.generate(
                pumpHistory: pumpHistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbHistory: carbs,
                glucoseHistory: glucose
            )

            if glucose.count < 4 {
                // prepare/meal.js keeps the other absorption fields on sparse CGM.
                mealResult = try MealTotal.recentCarbs(
                    treatments: MealHistory.findMealInputs(pumpHistory: pumpHistory, carbHistory: carbs),
                    pumpHistory: pumpHistory,
                    profile: profile,
                    basalProfile: basalProfile,
                    glucose: glucose,
                    time: clock
                )
                mealResult?.mealCOB = 0
            }
            if let cob = mealResult?.mealCOB { mealResult?.mealCOB = cob.jsRounded() }
            return try .success(JSONBridge.to(mealResult))
        } catch {
            return .failure(error)
        }
    }

    static func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> (OrefFunctionResult) {
        do {
            let pumpHistory = LocalOrefCompatibility.calculationHistory(try JSONBridge.pumpHistory(from: pumphistory))
            let profile = try JSONBridge.profile(from: profile)
            let clock = try JSONBridge.clock(from: clock)
            let autosens = try JSONBridge.autosens(from: autosens)

            let iobResult = try IobGenerator.generate(
                history: pumpHistory,
                profile: profile,
                clock: clock,
                autosens: autosens
            )

            return try .success(JSONBridge.to(iobResult))
        } catch {
            return .failure(error)
        }
    }

    static func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalProfile: JSON,
        profile: JSON,
        carbs: JSON,
        tempTargets: JSON,
        clock: JSON,
        includeDeviationsForTesting: Bool = false
    ) -> (OrefFunctionResult) {
        do {
            let glucose = try JSONBridge.glucose(from: glucose)
            let pumpHistory = LocalOrefCompatibility.calculationHistory(try JSONBridge.pumpHistory(from: pumpHistory))
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let profile = try JSONBridge.profile(from: profile)
            let carbs = try JSONBridge.carbs(from: carbs)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)
            let clock = try JSONBridge.clock(from: clock)

            // this logic is from prepare/autosens.js
            let ratio8h = try AutosensGenerator.generate(
                glucose: glucose,
                pumpHistory: pumpHistory,
                basalProfile: basalProfile,
                profile: profile,
                carbs: carbs,
                tempTargets: tempTargets,
                maxDeviations: 96,
                clock: clock,
                includeDeviationsForTesting: includeDeviationsForTesting
            )

            let ratio24h = try AutosensGenerator.generate(
                glucose: glucose,
                pumpHistory: pumpHistory,
                basalProfile: basalProfile,
                profile: profile,
                carbs: carbs,
                tempTargets: tempTargets,
                maxDeviations: 288,
                clock: clock,
                includeDeviationsForTesting: includeDeviationsForTesting
            )

            let lowestRatio = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h

            return try .success(JSONBridge.to(lowestRatio))
        } catch {
            return .failure(error)
        }
    }
}
