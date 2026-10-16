import Foundation

/// Presentation cleanup when the caller rejects an operation before any native mutation.
@MainActor
struct EagleAuraStudioPreflightFailure {
    let operationID: String
    let targetTitle: () -> String
    let log: (String, String) -> Void
    let recordDiagnostics: (String) -> Void
    let resetOperationUI: () -> Void
    let endGate: () -> Void
    let localizedText: (String, String) -> String
    let showNotice: (String) -> Void

    func failBeforeNativeCall(_ reason: String) {
        log(
            "sequence.preflight-failed",
            "op=\(operationID) reason=\(reason)"
        )
        recordDiagnostics(reason)
        resetOperationUI()
        endGate()
        showNotice(localizedText(
            "Aura Studio could not prepare a safe session for \(targetTitle()). Nothing was sent, and the other aura was not touched. A technical report is ready if the problem repeats.",
            "Aura Studio no pudo preparar una sesión segura para \(targetTitle()). No se envió nada y no se tocó la otra aura. Hay un informe técnico disponible si el problema se repite."
        ))
    }
}

