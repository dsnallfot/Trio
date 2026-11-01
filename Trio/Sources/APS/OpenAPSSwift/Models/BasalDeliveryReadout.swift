import Foundation

/// PR #1556 adapted to the local history model. Presentation only, never a dosing input.
enum BasalDeliveryReadout {
    enum Delivery: Equatable {
        case suspended
        case temp(rate: Decimal, manual: Bool)
        case scheduled(Decimal)
    }

    enum Status {
        case active
        case suspended
        case temp(start: Date, end: Date, rate: Decimal, manual: Bool)
    }

    struct Event {
        let start: Date
        let end: Date
        let rate: Decimal
    }

    static func resolve(
        status: Status?, events: [Event], suspensions: [(date: Date, isSuspend: Bool)],
        profile: [BasalProfileEntry], now: Date
    ) -> Delivery? {
        func scheduled() -> Delivery? {
            guard let minutes = now.minutesSinceMidnight,
                  let rate = profile.sorted(by: { $0.minutes < $1.minutes }).last(where: { $0.minutes <= minutes })?.rate
            else { return nil }
            return .scheduled(rate)
        }
        // Local history drops some cancellation updates. Live pump state therefore wins.
        switch status {
        case .suspended: return .suspended
        case .active: return scheduled()
        case let .temp(start, end, rate, manual):
            return start <= now && now < end ? .temp(rate: rate, manual: manual) : scheduled()
        case nil: break
        }
        let suspension = suspensions.filter { $0.date <= now }.max { $0.date < $1.date }
        if suspension?.isSuspend == true { return .suspended }
        let resumedAt = suspension?.date ?? .distantPast
        if let event = events.filter({ $0.start <= now }).max(by: { $0.start < $1.start }),
           event.start >= resumedAt, event.end > now
        {
            return .temp(rate: event.rate, manual: false)
        }
        return scheduled()
    }
}
