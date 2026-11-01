import Foundation

/// Stable values are also reported to Nightscout. Settings are never destructively clamped.
enum DosingMode: String, JSON, CaseIterable, Identifiable {
    case open
    case closed
    case lowGlucoseSuspend
    case basalTesting
    var id: String { rawValue }
    var allowsAutomation: Bool { self != .open }
    var allowsAdjustments: Bool { self == .closed }
    var requiresSwift: Bool { self == .lowGlucoseSuspend || self == .basalTesting }
    var title: String {
        switch self {
        case .open: return "Öppen loop"
        case .closed: return "Sluten loop"
        case .lowGlucoseSuspend: return "Låg suspendering"
        case .basalTesting: return "Basaltest"
        }
    }

    var explanation: String {
        switch self {
        case .open: return "Visar beräkningar men skickar inga automatiska doser."
        case .closed: return "Automatiska basaljusteringar och SMB enligt dina inställningar."
        case .lowGlucoseSuspend: return "Kan minska eller stoppa basal, men ger inte extra insulin."
        case .basalTesting: return "Låter basalprofilen löpa utan känslighetsanpassning. Kan stoppa basal vid lågt aktuellt eller prognostiserat glukos."
        }
    }
}

extension Preferences {
    func clamped(for mode: DosingMode) -> Preferences {
        var result = self
        if mode.requiresSwift { result.maxIOB = 0 }
        if mode == .basalTesting {
            result.autosensMin = 1
            result.autosensMax = 1
            result.useNewFormula = false
            result.sigmoid = false
            result.threshold_setting = max(threshold_setting, 72)
        }
        return result
    }
}

/// Shared by command entry points and Core Data validation; a transition blocks new activations.
/// Revision also invalidates delayed/scheduled activation requests across a mode change.
final class AdjustmentActivationPolicy {
    static let shared = AdjustmentActivationPolicy()
    static let blockedMessage = "Overrides och tillfälliga mål kan bara aktiveras i sluten loop."
    private let lock = NSLock()
    private var mode: DosingMode = .open
    private var transitioning = false
    private var revision: UInt64 = 0
    var token: UInt64 { lock.lock()
        defer { lock.unlock() }
        return revision }

    var allowsActivation: Bool { lock.lock()
        defer { lock.unlock() }
        return mode.allowsAdjustments && !transitioning }

    func accepts(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return mode.allowsAdjustments && !transitioning && token == revision
    }

    func update(_ mode: DosingMode) {
        lock.lock()
        defer { lock.unlock() }
        if self.mode != mode { revision &+= 1 }
        self.mode = mode
    }

    func beginTransition() { lock.lock()
        transitioning = true
        revision &+= 1
        lock.unlock() }

    func endTransition() { lock.lock()
        transitioning = false
        lock.unlock() }

    func validateActivation() throws {
        guard allowsActivation else { throw DosingModeError.adjustmentsBlocked }
    }
}

enum DosingModeError: LocalizedError {
    case adjustmentsBlocked
    case swiftRequired
    case staleCalculation
    var errorDescription: String? {
        switch self {
        case .adjustmentsBlocked: return AdjustmentActivationPolicy.blockedMessage
        case .swiftRequired: return "Välj Swift-motorn innan du aktiverar LGS eller basaltest."
        case .staleCalculation: return "Behandlingsläget ändrades. En ny beräkning behövs."
        }
    }
}

extension DosingMode {
    /// Max IOB alone is not a hard ceiling when IOB is negative or autosens raises basal.
    func constrain(_ determination: Determination, schedule: [BasalProfileEntry], at date: Date) throws -> Determination {
        guard requiresSwift else { return determination }
        var result = determination
        result.units = nil
        if let rate = result.rate, rate > 0 {
            guard let minutes = date.minutesSinceMidnight,
                  let basal = schedule.sorted(by: { $0.minutes < $1.minutes }).last(where: { $0.minutes <= minutes })?.rate,
                  basal >= 0 else { throw DosingModeError.staleCalculation }
            if rate > basal {
                result.reason += "Behandlingsläge: begränsar temp basal till ordinarie basal \(basal)E/h. "
                result.rate = basal
            }
        }
        return result
    }
}
