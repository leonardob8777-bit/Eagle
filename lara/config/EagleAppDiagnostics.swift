import Foundation

/// App composition only; neither creating a channel nor logging needs an access manager.
@MainActor
enum EagleAppDiagnostics {
    static let shared = makeDelivery()

    static func makeDelivery() -> EagleDiagnosticDelivery {
        EagleDiagnosticDelivery(history: EagleLogHistory(), write: { globallogger.log($0) })
    }

    nonisolated static let log: @Sendable (String) -> Void = { message in
        Task { @MainActor in
            shared.enqueue(message)
        }
    }
}
