import Foundation

enum TimeInRangeChartStyle: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case vertical
    case horizontal

    var displayName: String {
        switch self {
        case .vertical:
            return NSLocalizedString("Vertikal", comment: "")
        case .horizontal:
            return NSLocalizedString("Horisontell", comment: "")
        }
    }
}
