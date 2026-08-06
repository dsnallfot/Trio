enum ColorSchemeOption: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case systemDefault
    case light
    case dark

    var displayName: String {
        switch self {
        case .systemDefault: return "Systemstandard"
        case .light: return "Ljust"
        case .dark: return "Mörkt"
        }
    }
}
