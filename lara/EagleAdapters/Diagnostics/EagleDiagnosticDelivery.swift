import Foundation

/// Delivers history and logger updates on the existing deferred main-queue hop.
@MainActor
final class EagleDiagnosticDelivery {
    let history: EagleLogHistory
    private let write: @MainActor @Sendable (String) -> Void

    init(history: EagleLogHistory, write: @escaping @MainActor @Sendable (String) -> Void) {
        self.history = history
        self.write = write
    }

    func enqueue(_ message: String, retaining owner: AnyObject? = nil) {
        DispatchQueue.main.async { [self, owner] in
            history.append(message)
            write(message)
            withExtendedLifetime(owner) {}
        }
    }
}
