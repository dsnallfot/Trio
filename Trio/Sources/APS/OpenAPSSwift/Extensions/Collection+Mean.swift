import Foundation

extension Collection where Element == Decimal {
    var mean: Decimal {
        guard !isEmpty else { return .zero }
        return reduce(.zero, +) / Decimal(count)
    }
}
