import Foundation

/// Commits presentation state only after the caller has verified native rollback.
/// This component does not perform rollback, verify a session or retry an operation.
@MainActor
struct EagleAuraStudioVerifiedRollback {
    let previouslyVerified: UInt32
    let newlyApplied: UInt32
    let operationSpringBoardPID: Int32
    let operationID: String
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let writeActiveFlags: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let log: (String, String) -> Void
    let recordDiagnostics: (String) -> Void
    let resetOperationUI: () -> Void
    let endGate: () -> Void
    let errorMessage: (Int32) -> String
    let localizedText: (String, String) -> String
    let showNotice: (String) -> Void

    func finishVerifiedRollback(
        _ result: Int32,
        stepFlag: UInt32,
        stepEnglishName: String,
        reason: String
    ) {
        // -12 is a native, fail-closed Island contract: the candidate
        // could not be read back, so native code synchronously removes it
        // (or restores the previously committed Island) before returning.
        // Reaching this path also means PID and RemoteCall health were
        // already revalidated above. Keep the error visible, preserve the
        // previously verified state, and permit a fresh manual retry.
        writeRetained(readRetained() | (previouslyVerified & stepFlag))
        let finalFlags = readRetained() | newlyApplied
        writeActiveFlags(Int(finalFlags))
        writeSpringBoardPID(finalFlags == 0
            ? 0
            : Int(operationSpringBoardPID))
        log(
            "step.rollback-verified",
            "op=\(operationID) module=\(stepEnglishName) " +
            "result=\(result) previous=0x\(String(previouslyVerified, radix: 16)) " +
            "retained=0x\(String(finalFlags, radix: 16)) retry=fresh-session"
        )
        recordDiagnostics(reason)
        resetOperationUI()
        endGate()
        showNotice(
            errorMessage(result) + " " + localizedText(
                "SpringBoard and the protected call session remained healthy. No restart is required; you may retry this profile, and the other aura was not changed.",
                "SpringBoard y la sesión protegida permanecieron en buen estado. No necesitas reiniciar; puedes volver a intentar este perfil y no se cambió la otra aura."
            )
        )
    }
}

