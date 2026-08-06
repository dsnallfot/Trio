import Foundation

enum LockScreenView: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case simple
    case detailed
    var displayName: String {
        switch self {
        case .simple:
            return NSLocalizedString("Enkel", comment: "")
        case .detailed:
            return NSLocalizedString("Detaljerad", comment: "")
        }
    }
}
