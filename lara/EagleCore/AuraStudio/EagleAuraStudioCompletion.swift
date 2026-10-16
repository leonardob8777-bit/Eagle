import Foundation

/// Commits presentation state after the caller has classified native outcomes.
/// Does not execute, verify, retry or unlock native operations.
@MainActor
struct EagleAuraStudioCompletion<NoticeKind> {
    let retainedVerified: UInt32
    let newlyApplied: UInt32
    let removedFlags: UInt32
    let requestedFlags: UInt32
    let operationIsRemoving: Bool
    let operationSpringBoardPID: Int32
    let operationID: String
    let mode: Int
    let motionDegraded: Bool
    let firstUnavailableResult: Int32?
    let verifiedFallbackResult: Int32?
    let writeActiveFlags: (Int) -> Void
    let readIslandMode: () -> Int
    let writeActiveMode: (Int) -> Void
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let log: (String, String) -> Void
    let recordDiagnostics: (String) -> Void
    let resetOperationUI: () -> Void
    let endGate: () -> Void
    let errorMessage: (Int32) -> String
    let successMessage: (UInt32, UInt32, Bool, Bool, EagleAuraStudioMode?) -> String
    let localizedText: (String, String) -> String
    let informationKind: NoticeKind
    let errorKind: NoticeKind
    let successKind: NoticeKind
    let showNotification: (String, String, NoticeKind) -> Void

    func completeSuccess(deadlineWarning: Bool = false) {
        let finalFlags = retainedVerified | newlyApplied
        writeActiveFlags(Int(finalFlags))
        writeActiveMode(readIslandMode())
        if finalFlags == 0 {
            writeSpringBoardPID(0)
            writeActiveMode(0)
            writeIslandMode(0)
            writeDockMode(0)
        } else {
            writeSpringBoardPID(Int(operationSpringBoardPID))
        }
        let sequenceStage = !operationIsRemoving &&
            newlyApplied == 0 && firstUnavailableResult != nil
            ? "sequence.unavailable"
            : "sequence.success"
        log(
            sequenceStage,
            "op=\(operationID) applied=0x\(String(newlyApplied, radix: 16)) " +
            "removed=0x\(String(removedFlags, radix: 16)) " +
            "degraded=\(motionDegraded) deadlineWarning=\(deadlineWarning)"
        )
        let diagnosticsSummary: String
        if operationIsRemoving {
            diagnosticsSummary = "Scoped removal completed and verified"
        } else if newlyApplied == 0, let firstUnavailableResult {
            diagnosticsSummary =
                "No mutation; selected host unavailable (result \(firstUnavailableResult))"
        } else if verifiedFallbackResult != nil {
            diagnosticsSummary = "Requested style unavailable; verified Glow fallback retained"
        } else {
            diagnosticsSummary = "Scoped apply completed and verified"
        }
        recordDiagnostics(diagnosticsSummary)
        resetOperationUI()
        if !deadlineWarning {
            endGate()
        }
        let baseResultMessage: String
        if let verifiedFallbackResult {
            baseResultMessage = errorMessage(verifiedFallbackResult)
        } else if !operationIsRemoving,
                  newlyApplied == 0,
                  let firstUnavailableResult {
            baseResultMessage = errorMessage(firstUnavailableResult)
        } else {
            baseResultMessage = successMessage(
                operationIsRemoving
                    ? removedFlags
                    : newlyApplied,
                requestedFlags,
                operationIsRemoving,
                motionDegraded,
                operationIsRemoving
                    ? nil
                    : EagleAuraStudioMode(rawValue: mode)
            )
        }
        let resultMessage: String
        if deadlineWarning {
            resultMessage = baseResultMessage + " " + localizedText(
                "Verification exceeded the safety deadline, so Eagle will not retry this surface. Fully close and reopen Eagle before another Aura Studio operation.",
                "La verificación superó el límite de seguridad, por lo que Eagle no volverá a intentar esta superficie. Cierra Eagle completamente y vuelve a abrirlo antes de otra operación de Aura Studio."
            )
        } else {
            resultMessage = baseResultMessage
        }
        let kind: NoticeKind = deadlineWarning || motionDegraded || verifiedFallbackResult != nil
            ? informationKind
            : (!operationIsRemoving && newlyApplied == 0 && firstUnavailableResult != nil ? errorKind : successKind)
        showNotification("Aura Studio", resultMessage, kind)
    }
}

