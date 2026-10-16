import Foundation

/// Step selection, progress presentation and continuation; native work remains caller-owned.
@MainActor
enum EagleAuraStudioStepFlow {
    static func begin(
        index: Int,
        steps: [EagleAuraStudioOperationStep],
        operationID: String,
        readOperationID: () -> String?,
        readApplying: () -> Bool,
        writeStepIndex: (Int) -> Void,
        writeStage: (String) -> Void,
        localizedText: (String, String) -> String,
        log: (String, String) -> Void,
        complete: () -> Void
    ) -> EagleAuraStudioOperationStep? {
        guard readOperationID() == operationID, readApplying() else { return nil }
        guard index < steps.count else {
            complete()
            return nil
        }
        let step = steps[index]
        writeStepIndex(index + 1)
        writeStage(localizedText(
            "Preparing \(step.englishName) safely…",
            "Preparando \(step.spanishName) de forma segura…"
        ))
        log(
            "step.session.begin",
            "op=\(operationID) index=\(index) module=\(step.englishName) " +
            "flag=0x\(String(step.flag, radix: 16))"
        )
        return step
    }

    static func nativeStarted(
        operationID: String,
        step: EagleAuraStudioOperationStep,
        operation: EagleAuraStudioOperation,
        targetPID: Int32,
        writeStage: (String) -> Void,
        localizedText: (String, String) -> String,
        log: (String, String) -> Void
    ) {
        writeStage(localizedText(
            operation.isRemoving
                ? "Removing \(step.englishName) only…"
                : "Applying \(step.englishName) only…",
            operation.isRemoving
                ? "Eliminando solo \(step.spanishName)…"
                : "Aplicando solo \(step.spanishName)…"
        ))
        log(
            "step.native.begin",
            "op=\(operationID) module=\(step.englishName) " +
            "action=\(operation.isRemoving ? "remove" : "apply") " +
            "pid=\(targetPID) flag=0x\(String(step.flag, radix: 16))"
        )
    }

    static func advance(
        index: Int,
        deadlineExceeded: Bool,
        complete: (Bool) -> Void,
        runNext: (Int) -> Void
    ) {
        if deadlineExceeded {
            complete(true)
        } else {
            runNext(index + 1)
        }
    }
}
