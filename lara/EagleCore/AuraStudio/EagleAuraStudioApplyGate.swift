import Foundation

/// Process-wide Aura admission state. The caller retains session ownership and native execution.
@MainActor
enum EagleAuraStudioApplyGate {
    private static var operationInFlight = false
    private static var safetyLocked = false

    static func begin() -> Bool {
        guard !operationInFlight, !safetyLocked else { return false }
        operationInFlight = true
        return true
    }

    static func end() {
        operationInFlight = false
    }

    static func lock() {
        operationInFlight = false
        safetyLocked = true
    }
}
