import Foundation

/// Fail-closed presentation/state coordination after the caller reports an unverified outcome.
/// Native verification, quarantine implementation and session ownership stay injected.
@MainActor
struct EagleAuraStudioUnverifiedFailure {
    let operationID: String
    let retainedVerified: UInt32
    let newlyApplied: UInt32
    let removedFlags: UInt32
    let islandFlag: UInt32
    let dockFlag: UInt32
    let targetTitle: () -> String
    let writeActiveFlags: (Int) -> Void
    let readActiveFlags: () -> Int
    let writeActiveMode: (Int) -> Void
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let currentSpringBoardPID: () -> Int32
    let quarantine: (String) -> Void
    let writeSafetyBlocked: (Bool) -> Void
    let lockGate: () -> Void
    let log: (String, String) -> Void
    let recordDiagnostics: (String) -> Void
    let resetOperationUI: () -> Void
    let localizedText: (String, String) -> String
    let showNotice: (String) -> Void

    func failAfterNativeCall(
        _ reason: String,
        result: Int32? = nil,
        userDetail: String? = nil
    ) {
        let resultText = result.map { " result=\($0)" } ?? ""
        log(
            "breaker.open",
            "op=\(operationID) applied=0x\(String(newlyApplied, radix: 16)) " +
            "removed=0x\(String(removedFlags, radix: 16))" +
            resultText + " reason=\(reason)"
        )
        writeActiveFlags(Int(retainedVerified | newlyApplied))
        if readActiveFlags() & Int(islandFlag) == 0 {
            writeActiveMode(0)
            writeIslandMode(0)
        }
        if readActiveFlags() & Int(dockFlag) == 0 {
            writeDockMode(0)
        }
        if readActiveFlags() == 0 {
            writeSpringBoardPID(0)
        } else {
            writeSpringBoardPID(Int(currentSpringBoardPID()))
        }
        quarantine(reason)
        writeSafetyBlocked(true)
        lockGate()
        recordDiagnostics(reason)
        resetOperationUI()
        let baseMessage = localizedText(
            "Aura Studio stopped because \(targetTitle()) could not be verified. The other aura was not changed and no automatic respring was attempted. Share the diagnostic report, then fully close and reopen Eagle before another test.",
            "Aura Studio se detuvo porque no pudo verificar \(targetTitle()). No se cambió la otra aura ni se intentó un respring automático. Comparte el informe y luego cierra y abre Eagle completamente antes de otra prueba."
        )
        let detailSuffix = userDetail.map { "\n\n\($0)" } ?? ""
        showNotice(baseMessage + detailSuffix)
    }
}

