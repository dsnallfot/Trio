import Foundation

struct PumpStatus: JSON, Equatable {
    let status: StatusType
    let bolusing: Bool
    let suspended: Bool
    var timestamp: Date?
}

extension PumpStatus {
    /// Omnipod can report delivery active since `.distantPast` with no active pod.
    /// Preserve the last suspend until a pump resume, temp basal or bolus follows it.
    func includingSuspend(deliveryActiveSince: Date, lastPumpEvent: (type: String, date: Date)?) -> PumpStatus {
        guard !suspended, let lastPumpEvent,
              lastPumpEvent.type == PumpEventStored.EventType.pumpSuspend.rawValue,
              deliveryActiveSince < lastPumpEvent.date
        else { return self }
        return PumpStatus(status: .suspended, bolusing: bolusing, suspended: true, timestamp: timestamp)
    }
}

enum StatusType: String, JSON {
    case normal
    case suspended
    case bolusing
}
