import Foundation

/// Reconciles saved Aura metadata without owning preferences or querying the system.
@MainActor
struct EagleAuraStudioReconciliation {
    enum Field: CaseIterable {
        case flags, legacyMode, islandMode, dockMode, dockGalleryStyle, springBoardPID
    }

    let lookupCurrentPID: () -> Int32
    let decodeFlags: (Int) -> UInt32
    let supportedFlags: UInt32
    let deviceSupportedFlags: () -> UInt32
    let islandFlag: UInt32
    let dockFlag: UInt32
    let read: (Field) -> Int
    let write: (Field, Int) -> Void
    let diagnosticsToken: () -> String
    let log: (String, String) -> Void

    func reconcilePersistedActiveState(currentPID providedPID: Int32? = nil) {
        let currentPID = providedPID ?? lookupCurrentPID()
        let rawSavedFlags = decodeFlags(read(.flags)) & supportedFlags
        let savedFlags = rawSavedFlags & deviceSupportedFlags()
        if rawSavedFlags != savedFlags {
            log(
                "state.hardware-pruned",
                "before=0x\(String(rawSavedFlags, radix: 16)) " +
                "after=0x\(String(savedFlags, radix: 16)) " +
                "\(diagnosticsToken())"
            )
            write(.flags, Int(savedFlags))
            write(.islandMode, 0)
        }
        guard savedFlags != 0 else {
            write(.flags, 0)
            write(.legacyMode, 0)
            write(.islandMode, 0)
            write(.dockMode, 0)
            write(.dockGalleryStyle, 0)
            write(.springBoardPID, 0)
            return
        }

        // Auras live inside SpringBoard. A badge saved by an older build, or
        // by a SpringBoard PID that no longer exists, cannot be called active.
        guard read(.springBoardPID) > 0,
              currentPID == Int32(read(.springBoardPID)) else {
            log(
                "state.expired",
                "savedPID=\(read(.springBoardPID)) currentPID=\(currentPID) " +
                "flags=0x\(String(savedFlags, radix: 16))"
            )
            write(.flags, 0)
            write(.legacyMode, 0)
            write(.islandMode, 0)
            write(.dockMode, 0)
            write(.dockGalleryStyle, 0)
            write(.springBoardPID, 0)
            return
        }

        // Mode/color metadata never outlives its surface flag. This matters
        // when one profile is restored while the other remains active.
        if savedFlags & islandFlag == 0 {
            write(.legacyMode, 0)
            write(.islandMode, 0)
        }
        if savedFlags & dockFlag == 0 {
            write(.dockMode, 0)
            write(.dockGalleryStyle, 0)
        }

        // One-time migration from the original shared style field.
        if savedFlags & islandFlag != 0, read(.islandMode) == 0 {
            write(.islandMode, read(.legacyMode))
        }
        if savedFlags & dockFlag != 0, read(.dockMode) == 0 {
            write(.dockMode, read(.legacyMode))
        }
    }
}
