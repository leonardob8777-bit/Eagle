import Foundation

/// Presentation lifecycle only. Native execution, operation gate and scheduling remain injected.
@MainActor
struct EagleAuraStudioOperationUI {
    let writeApplying: (Bool) -> Void
    let writeRemoval: (Bool) -> Void
    let writeStepIndex: (Int) -> Void
    let writeStepCount: (Int) -> Void
    let writeOperationID: (String?) -> Void
    let writeStage: (String) -> Void
    let localizedText: (String, String) -> String
    let log: (String, String) -> Void
    let scheduleOnMain: (@escaping @MainActor @Sendable () -> Void) -> Void
    let endGate: () -> Void
    let showNotice: (String) -> Void

    func begin(operationID: String, isRemoving: Bool, stepCount: Int) {
        writeApplying(true)
        writeRemoval(isRemoving)
        writeStepIndex(0)
        writeStepCount(stepCount)
        writeOperationID(operationID)
        writeStage(localizedText(
            "Preparing a fresh SpringBoard session…",
            "Preparando una sesión nueva de SpringBoard…"
        ))
    }

    func reset() {
        writeApplying(false)
        writeStage("")
        writeStepIndex(0)
        writeStepCount(0)
        writeRemoval(false)
        writeOperationID(nil)
    }

    func finish(message: String) {
        log("finish", "error=true")
        scheduleOnMain {
            endGate()
            writeOperationID(nil)
            writeApplying(false)
            writeStage("")
            writeStepIndex(0)
            writeStepCount(0)
            writeRemoval(false)
            showNotice(message)
        }
    }
}
