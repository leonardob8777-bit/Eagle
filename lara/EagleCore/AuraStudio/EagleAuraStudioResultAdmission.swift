import Foundation

/// Decides whether an existing result may be consumed; native calls and timers remain caller-owned.
@MainActor
struct EagleAuraStudioResultAdmission {
    let currentPID: () -> Int32
    let readOperationID: () -> String?
    let readApplying: () -> Bool
    let readFinished: () -> Bool
    let writeFinished: (Bool) -> Void
    let cancelSoftProgress: () -> Void
    let cancelHardDeadline: () -> Void
    let endExclusive: (String) -> Void
    let log: (String, String) -> Void
    let writeActiveFlags: (Int) -> Void
    let writeActiveMode: (Int) -> Void
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let writeNewlyApplied: (UInt32) -> Void
    let readHealthy: () -> Bool
    let readTimedOut: () -> Bool
    let localizedText: (String, String) -> String
    let failAfter: (String, Int32, String?) -> Void

    func admit(
        result: Int32,
        processError: String?,
        operationID: String,
        operationSpringBoardPID: Int32,
        targetPID: Int32,
        springBoardPID: Int32,
        stepFlag: UInt32,
        stepEnglishName: String,
        stepSpanishName: String
    ) -> Bool {
        let liveSpringBoardPID = currentPID()
        guard readOperationID() == operationID,
              readApplying(),
              !readFinished() else {
            log(
                "step.native.late",
                "op=\(operationID) module=\(stepEnglishName) result=\(result)"
            )
            if springBoardPID != targetPID ||
                liveSpringBoardPID != targetPID {
                writeActiveFlags(0)
                writeActiveMode(0)
                writeIslandMode(0)
                writeDockMode(0)
                writeSpringBoardPID(0)
            }
            endExclusive("Aura \(stepEnglishName) \(operationID)")
            return false
        }
        writeFinished(true)
        cancelSoftProgress()
        cancelHardDeadline()
        endExclusive("Aura \(stepEnglishName) \(operationID)")

        if springBoardPID != targetPID ||
            liveSpringBoardPID != targetPID ||
            targetPID != operationSpringBoardPID {
            writeActiveFlags(0)
            writeActiveMode(0)
            writeIslandMode(0)
            writeDockMode(0)
            writeSpringBoardPID(0)
            writeRetained(0)
            writeNewlyApplied(0)
            writeRetained(readRetained() & ~stepFlag)
            failAfter(
                "SpringBoard restarted during \(stepEnglishName) " +
                "(PID \(targetPID) → \(liveSpringBoardPID))",
                result, nil
            )
            return false
        }
        if !readHealthy() ||
            readTimedOut() ||
            (processError?.isEmpty == false) {
            let transportReason = processError ??
                (readTimedOut()
                    ? "RemoteCall transport timed out"
                    : "RemoteCall session became unhealthy")
            writeRetained(readRetained() & ~stepFlag)
            failAfter(
                "\(stepEnglishName) RemoteCall error: \(transportReason)",
                result,
                localizedText(
                    "The protected call channel became unhealthy while \(stepEnglishName) was being checked. Eagle did not mark this surface as active.",
                    "El canal protegido de llamadas dejó de estar disponible mientras se verificaba \(stepSpanishName). Eagle no marcó esta superficie como activa."
                )
            )
            return false
        }
        return true
    }
}
