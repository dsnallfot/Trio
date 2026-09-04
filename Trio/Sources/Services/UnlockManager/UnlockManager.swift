import Combine
import LocalAuthentication

protocol UnlockManager {
    func unlock() async throws -> Bool
}

struct UnlockError: Error {
    let error: Error?
}

final class BaseUnlockManager: UnlockManager {
    @MainActor func unlock() async throws -> Bool {
        let context = LAContext()
        let reason = "Vi behöver vara säkra på att det är du som äger telefonen."

        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return true
        } catch {
            throw UnlockError(error: error)
        }
    }
}
