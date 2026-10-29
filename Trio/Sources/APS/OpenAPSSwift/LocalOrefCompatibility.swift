import Foundation

enum LocalOrefCompatibility {
    // JS ignores duration-only records; a truncated history can end with one.
    // Missing duration for an actual basal remains an error in the Swift core.
    static func calculationHistory(_ history: [PumpHistoryEvent]) -> [PumpHistoryEvent] {
        let basalTimes = Set(history.filter { $0.type == .tempBasal }.map(\.timestamp))
        return history.filter { $0.type != .tempBasalDuration || basalTimes.contains($0.timestamp) }
    }

    static func variables(_ legacy: Oref2_variables, currentTDD: Decimal) -> TrioCustomOrefVariables {
        TrioCustomOrefVariables(
            average_total_data: legacy.average_total_data,
            weightedAverage: legacy.weightedAverage,
            currentTDD: currentTDD,
            past2hoursAverage: legacy.past2hoursAverage,
            date: legacy.date,
            overridePercentage: legacy.overridePercentage,
            useOverride: legacy.useOverride,
            duration: legacy.duration,
            unlimited: legacy.unlimited,
            overrideTarget: legacy.overrideTarget,
            smbIsOff: legacy.smbIsOff,
            advancedSettings: legacy.advancedSettings,
            isfAndCr: legacy.isfAndCr,
            isf: legacy.isf,
            cr: legacy.cr,
            smbIsScheduledOff: legacy.smbIsScheduledOff,
            start: legacy.start,
            end: legacy.end,
            smbMinutes: legacy.smbMinutes,
            uamMinutes: legacy.uamMinutes
        )
    }

    /// The local JS cancels high temps on stale/flat/noisy CGM. PR #1141 instead
    /// sets a neutral temp. Preserve this branch's cancellation contract.
    static func invalidGlucoseResult(
        glucose: [BloodGlucose],
        profile: Profile,
        currentTemp: TempBasal,
        variables: TrioCustomOrefVariables,
        clock: Date
    ) throws -> RawJSON? {
        guard let status = try DeterminationGenerator.getGlucoseStatus(glucoseReadings: glucose) else { return nil }
        let age = Decimal(clock.timeIntervalSince(status.date) / 60).jsRounded(scale: 1)
        let flat = status.shortAvgDelta == 0 && status.longAvgDelta == 0
        guard status.glucose != 400,
              status.glucose <= 10 || status.glucose == 38 || status.noise >= 3 || age > 12 || age < -5 || flat
        else { return nil }
        var reason = "CGM is calibrating, in ??? state, or noise is high"
        if age > 12 || age < -5 { reason = "BG data is too old or in the future (\(age)m)." }
        else if flat { reason = "CGM data is unchanged." }
        let basal = TempBasalFunctions.roundBasal(profile: profile, basalRate: profile.currentBasal ?? 0) * variables
            .overrideFactor()
        var result: [String: Any] = ["reason": reason]
        if currentTemp.rate >= basal {
            result["reason"] = reason + ". Canceling high temp basal of \(currentTemp.rate)"
            result["rate"] = 0
            result["duration"] = 0
        } else if currentTemp.rate == 0, currentTemp.duration > 30 {
            result["reason"] = reason + ". Shortening zero temp to 30m."
            result["rate"] = 0
            result["duration"] = 30
        }
        if result["rate"] != nil {
            result["temp"] = "absolute"
            result["deliverAt"] = Formatter.iso8601withFractionalSeconds.string(from: clock)
        }
        return String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)
    }
}
