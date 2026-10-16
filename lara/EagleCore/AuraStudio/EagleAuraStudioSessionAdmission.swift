import Foundation

/// Validates a prepared handle without owning or creating a native session.
@MainActor
struct EagleAuraStudioAdmittedSession<Session> {
    let process: Session
    let targetPID: Int32
}

@MainActor
struct EagleAuraStudioSessionAdmission<Session> {
    let readOperationID: () -> String?
    let readApplying: () -> Bool
    let readPID: (Session) -> Int32
    let readIsolated: (Session) -> Bool
    let currentPID: () -> Int32
    let beginExclusive: (String, Session) -> Bool
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let writeNewlyApplied: (UInt32) -> Void
    let writeActiveFlags: (Int) -> Void
    let writeActiveMode: (Int) -> Void
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let failBefore: (String) -> Void
    let failAfter: (String) -> Void

    func admit(
        process: Session?,
        sessionError: String?,
        operationID: String,
        operationSpringBoardPID: Int32,
        stepFlag: UInt32,
        stepEnglishName: String
    ) -> EagleAuraStudioAdmittedSession<Session>? {
        guard readOperationID() == operationID, readApplying() else { return nil }
        guard let process else {
            let reason = sessionError ?? "Fresh SpringBoard session was unavailable"
            let isReadOnlyPreflight =
                reason.localizedCaseInsensitiveContains("access is not ready") ||
                reason.localizedCaseInsensitiveContains("still running") ||
                reason.localizedCaseInsensitiveContains("safety locked")
            if isReadOnlyPreflight {
                failBefore(reason)
            } else {
                // RemoteCall initialization can already install target
                // exception ports and create a helper thread. Any
                // failure after that point is a transport event, not a
                // harmless host miss, so this run must fail closed.
                writeRetained(readRetained() & ~stepFlag)
                failAfter(reason)
            }
            return nil
        }

        let targetPID = readPID(process)
        let currentPID = currentPID()
        guard targetPID > 0,
              readIsolated(process) else {
            failBefore(
                "Fresh session identity check failed " +
                "(target \(targetPID), current \(currentPID), " +
                "isolated \(readIsolated(process)))"
            )
            return nil
        }
        guard currentPID == targetPID,
              targetPID == operationSpringBoardPID else {
            writeRetained(0)
            writeNewlyApplied(0)
            writeActiveFlags(0)
            writeActiveMode(0)
            writeIslandMode(0)
            writeDockMode(0)
            writeSpringBoardPID(0)
            failAfter(
                "SpringBoard changed while preparing \(stepEnglishName) " +
                "(operation \(operationSpringBoardPID), target \(targetPID), " +
                "current \(currentPID))"
            )
            return nil
        }
        guard beginExclusive("Aura \(stepEnglishName) \(operationID)", process) else {
            failBefore(
                "Could not acquire the serialized \(stepEnglishName) session"
            )
            return nil
        }
        return EagleAuraStudioAdmittedSession(process: process, targetPID: targetPID)
    }
}
