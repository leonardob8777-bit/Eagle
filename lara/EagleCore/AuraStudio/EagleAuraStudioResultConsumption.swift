import Foundation

/// Result interpretation and ordered profile updates. Storage and final effects are supplied by the app.
@MainActor
struct EagleAuraStudioResultConsumption {
    enum StoredField: CaseIterable {
        case flags, legacyMode, islandMode, dockMode, dockGalleryStyle, springBoardPID
        case islandRed, islandGreen, islandBlue, dockRed, dockGreen, dockBlue
    }

    let islandFlag: UInt32
    let dockFlag: UInt32
    let supportedFlags: UInt32
    let motionDegradedFlag: UInt32
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let readNewlyApplied: () -> UInt32
    let writeNewlyApplied: (UInt32) -> Void
    let readRemoved: () -> UInt32
    let writeRemoved: (UInt32) -> Void
    let readUnavailable: () -> Int32?
    let writeUnavailable: (Int32) -> Void
    let writeFallback: (Int32) -> Void
    let readMotionDegraded: () -> Bool
    let writeMotionDegraded: (Bool) -> Void
    let readDeadlineExceeded: () -> Bool
    let readStored: (StoredField) -> Int
    let writeStored: (StoredField, Int) -> Void
    let log: (String, String) -> Void
    let localizedText: (String, String) -> String
    let errorMessage: (Int32) -> String
    let failAfter: (String, Int32, String?) -> Void
    let finishRollback: (Int32, EagleAuraStudioOperationStep, String) -> Void

    func consume(
        result: Int32,
        operation: EagleAuraStudioOperation,
        operationID: String,
        target: EagleAuraStudioTarget,
        requestedMode: EagleAuraStudioMode,
        step: EagleAuraStudioOperationStep,
        index: Int,
        previouslyVerified: UInt32,
        springBoardPID: Int32,
        mode: Int,
        redValue: Int32,
        greenValue: Int32,
        blueValue: Int32,
        complete: (Bool) -> Void,
        runNext: (Int) -> Void
    ) {
        if operation.isRemoving {
            guard result == 0 else {
                writeRetained(readRetained() & ~step.flag)
                failAfter(
                    "\(step.englishName) removal could not be verified",
                    result,
                    errorMessage(result)
                )
                return
            }
            writeRetained(readRetained() & ~step.flag)
            writeRemoved(readRemoved() | step.flag)
            if step.flag == islandFlag {
                writeStored(.islandMode, 0)
                writeStored(.legacyMode, 0)
            } else if step.flag == dockFlag {
                writeStored(.dockMode, 0)
                writeStored(.dockGalleryStyle, 0)
            }
            writeStored(.flags, Int(readRetained() | readNewlyApplied()))
            writeStored(.springBoardPID, readStored(.flags) == 0
                ? 0
                : Int(springBoardPID))
            log(
                "step.remove.success",
                "op=\(operationID) module=\(step.englishName) " +
                "removed=0x\(String(readRemoved(), radix: 16))"
            )
            EagleAuraStudioStepFlow.advance(
                index: index,
                deadlineExceeded: readDeadlineExceeded(),
                complete: complete,
                runNext: runNext
            )
            return
        }
        if let fallbackMode =
            EagleAuraStudioNativeContract.verifiedFallbackMode(
                result: result,
                target: target,
                requestedMode: requestedMode
            ) {
            // These results explicitly guarantee that the
            // static black Glow core was restored and verified.
            // Keep that truthful state without opening the
            // circuit breaker or attempting to reapply Tint.
            writeNewlyApplied(readNewlyApplied() | islandFlag)
            writeRetained(readRetained() & ~islandFlag)
            writeStored(.flags, Int(readRetained() | readNewlyApplied()))
            writeStored(.springBoardPID, Int(springBoardPID))
            writeStored(.legacyMode, fallbackMode.rawValue)
            writeStored(.islandMode, fallbackMode.rawValue)
            writeStored(.islandRed, Int(redValue))
            writeStored(.islandGreen, Int(greenValue))
            writeStored(.islandBlue, Int(blueValue))
            writeFallback(result)
            log(
                "step.fallback",
                "op=\(operationID) module=\(step.englishName) result=\(result) verified=glow"
            )
            EagleAuraStudioStepFlow.advance(
                index: index,
                deadlineExceeded: readDeadlineExceeded(),
                complete: complete,
                runNext: runNext
            )
            return
        }
        if result == -15 || result == -16 {
            writeRetained(readRetained() & ~step.flag)
            failAfter(
                "Native fallback did not match the requested \(step.englishName) profile",
                result,
                localizedText(
                    "Eagle rejected a fallback intended for a different surface or style. No profile was reported as applied.",
                    "Eagle rechazó un fallback destinado a otra superficie o estilo. Ningún perfil se marcó como aplicado."
                )
            )
            return
        }
        if EagleAuraStudioNativeContract.isScopedUnavailable(
            result: result,
            target: target,
            mode: requestedMode,
            isRemoval: operation.isRemoving
        ) {
            // The native contract defines these as read-only
            // host/preflight misses. They are safe to report as
            // unavailable while preserving the other profile's
            // independently verified state.
            if readUnavailable() == nil {
                writeUnavailable(result)
            }
            writeRetained(readRetained() | previouslyVerified & step.flag)
            writeStored(.flags, Int(readRetained() | readNewlyApplied()))
            if readStored(.flags) & Int(islandFlag) == 0 {
                writeStored(.legacyMode, 0)
            }
            log(
                "step.unavailable",
                "op=\(operationID) module=\(step.englishName) result=\(result) mutation=none"
            )
            EagleAuraStudioStepFlow.advance(
                index: index,
                deadlineExceeded: readDeadlineExceeded(),
                complete: complete,
                runNext: runNext
            )
            return
        }
        if result == -2 || result == -17 || result == -20 {
            writeRetained(readRetained() & ~step.flag)
            failAfter(
                "Native capability result did not match \(step.englishName)",
                result,
                localizedText(
                    "SpringBoard returned a capability code for another surface or style. Eagle did not update either profile.",
                    "SpringBoard devolvió un código de capacidad para otra superficie o estilo. Eagle no actualizó ningún perfil."
                )
            )
            return
        }
        if EagleAuraStudioNativeContract.isScopedVerifiedRollback(
            result: result,
            target: target,
            isRemoval: operation.isRemoving
        ) && !readDeadlineExceeded() {
            finishRollback(
                result,
                step,
                "\(step.englishName) rejected candidate and verified native rollback (result -12)"
            )
            return
        }
        if result == -12 {
            writeRetained(readRetained() & ~step.flag)
            failAfter(
                "Native rollback result did not match \(step.englishName) or exceeded its deadline",
                result, nil
            )
            return
        }
        guard result >= 0 else {
            writeRetained(readRetained() & ~step.flag)
            failAfter(
                "\(step.englishName) returned unverified native error \(result)",
                result,
                errorMessage(result)
            )
            return
        }
        let rawResult = UInt32(bitPattern: result)
        guard EagleAuraStudioNativeContract.hasExactAppliedSurface(
            result: result,
            requestedFlag: step.flag,
            supportedFlags: supportedFlags
        ) else {
            writeRetained(readRetained() & ~step.flag)
            failAfter(
                "\(step.englishName) returned a missing or cross-surface verification mask",
                result,
                localizedText(
                    "SpringBoard returned without confirming the requested \(step.englishName) surface, so Eagle cleared only that surface's verified badge.",
                    "SpringBoard terminó sin confirmar la superficie \(step.spanishName) solicitada, por lo que Eagle borró solo el indicador verificado de esa superficie."
                )
            )
            return
        }

        writeNewlyApplied(readNewlyApplied() | step.flag)
        writeRetained(readRetained() & ~step.flag)
        writeMotionDegraded(readMotionDegraded() ||
            rawResult & motionDegradedFlag != 0)
        writeStored(.flags, Int(readRetained() | readNewlyApplied()))
        writeStored(.springBoardPID, Int(springBoardPID))
        if step.flag == islandFlag {
            writeStored(.legacyMode, mode)
            writeStored(.islandMode, mode)
            writeStored(.islandRed, Int(redValue))
            writeStored(.islandGreen, Int(greenValue))
            writeStored(.islandBlue, Int(blueValue))
        } else if step.flag == dockFlag {
            writeStored(.dockMode, mode)
            writeStored(.dockGalleryStyle, 0)
            writeStored(.dockRed, Int(redValue))
            writeStored(.dockGreen, Int(greenValue))
            writeStored(.dockBlue, Int(blueValue))
        }
        log(
            "step.success",
            "op=\(operationID) module=\(step.englishName) applied=0x\(String(readNewlyApplied(), radix: 16))"
        )
        EagleAuraStudioStepFlow.advance(
            index: index,
            deadlineExceeded: readDeadlineExceeded(),
            complete: complete,
            runNext: runNext
        )
    }
}
