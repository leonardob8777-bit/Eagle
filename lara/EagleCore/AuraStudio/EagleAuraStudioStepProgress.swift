import Foundation

/// Progress and deadline effects for one step. Scheduling and cancellation stay with the caller.
@MainActor
struct EagleAuraStudioStepProgress {
    let operationID: String
    let step: EagleAuraStudioOperationStep
    let readOperationID: () -> String?
    let readApplying: () -> Bool
    let readFinished: () -> Bool
    let writeStage: (String) -> Void
    let writeDeadlineExceeded: (Bool) -> Void
    let localizedText: (String, String) -> String
    let log: (String, String) -> Void
    let quarantine: (String) -> Void
    let writeSafetyBlocked: (Bool) -> Void
    let lockGate: () -> Void

    func reportProgress() {
        guard readOperationID() == operationID,
              readApplying(),
              !readFinished() else { return }
        writeStage(localizedText(
            "\(step.englishName) is responding · verifying the live result…",
            "\(step.spanishName) está respondiendo · verificando el resultado en vivo…"
        ))
        log(
            "step.native.progress",
            "op=\(operationID) module=\(step.englishName) elapsed=10"
        )
    }

    func deadlineReached() {
        guard readOperationID() == operationID,
              readApplying(),
              !readFinished() else { return }
        writeDeadlineExceeded(true)
        let reason = "\(step.englishName) exceeded the 60-second safety deadline"
        log(
            "step.native.deadline",
            "op=\(operationID) module=\(step.englishName) elapsed=60"
        )
        writeStage(localizedText(
            "Still waiting safely for \(step.englishName) · no automatic retry will start…",
            "Aún esperando de forma segura a \(step.spanishName) · no se iniciará otro intento automático…"
        ))
        quarantine(reason)
        writeSafetyBlocked(true)
        lockGate()
    }
}
