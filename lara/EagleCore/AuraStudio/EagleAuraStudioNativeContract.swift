import Foundation

/// Pure interpretation of one-surface Aura results. This never acquires access or calls the native engine.
nonisolated enum EagleAuraStudioNativeContract {
    static func target(
        for flags: UInt32,
        islandFlag: UInt32,
        dockFlag: UInt32
    ) -> EagleAuraStudioTarget? {
        switch flags {
        case islandFlag: return .island
        case dockFlag: return .dock
        default: return nil
        }
    }

    static func isScopedUnavailable(
        result: Int32,
        target: EagleAuraStudioTarget,
        mode: EagleAuraStudioMode,
        isRemoval: Bool
    ) -> Bool {
        guard !isRemoval else { return false }
        switch (result, target, mode) {
        case (-2, .island, _),
             (-17, .island, .tint),
             (-20, .dock, _):
            return true
        default:
            return false
        }
    }

    static func verifiedFallbackMode(
        result: Int32,
        target: EagleAuraStudioTarget,
        requestedMode: EagleAuraStudioMode
    ) -> EagleAuraStudioMode? {
        switch (result, target, requestedMode) {
        case (-15, .island, .rainbow),
             (-16, .island, .tint):
            return .glow
        default:
            return nil
        }
    }

    static func isScopedVerifiedRollback(
        result: Int32,
        target: EagleAuraStudioTarget,
        isRemoval: Bool
    ) -> Bool {
        !isRemoval && result == -12 && target == .island
    }

    static func hasExactAppliedSurface(
        result: Int32,
        requestedFlag: UInt32,
        supportedFlags: UInt32
    ) -> Bool {
        guard result >= 0 else { return false }
        return UInt32(bitPattern: result) & supportedFlags == requestedFlag
    }

#if DEBUG
    /// Lightweight pure contract checks for projects that currently have no
    /// XCTest target. They log rather than trap on a physical beta device.
    static var invariantsHold: Bool {
        let island: UInt32 = 1
        let dock: UInt32 = 1 << 5
        let supported = island | dock
        return target(for: island, islandFlag: island, dockFlag: dock) == .island &&
            target(for: dock, islandFlag: island, dockFlag: dock) == .dock &&
            target(for: supported, islandFlag: island, dockFlag: dock) == nil &&
            isScopedUnavailable(
                result: -20,
                target: .dock,
                mode: .glow,
                isRemoval: false
            ) &&
            !isScopedUnavailable(
                result: -20,
                target: .island,
                mode: .glow,
                isRemoval: false
            ) &&
            !isScopedUnavailable(
                result: -20,
                target: .dock,
                mode: .glow,
                isRemoval: true
            ) &&
            verifiedFallbackMode(
                result: -16,
                target: .island,
                requestedMode: .tint
            ) == .glow &&
            verifiedFallbackMode(
                result: -16,
                target: .dock,
                requestedMode: .glow
            ) == nil &&
            hasExactAppliedSurface(
                result: Int32(island),
                requestedFlag: island,
                supportedFlags: supported
            ) &&
            !hasExactAppliedSurface(
                result: Int32(supported),
                requestedFlag: island,
                supportedFlags: supported
            )
    }
#endif
}
