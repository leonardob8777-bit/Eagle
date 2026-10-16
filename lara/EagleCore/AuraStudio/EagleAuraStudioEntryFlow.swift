import Foundation

/// Orders Aura entry and channel-change preparation; UI, storage and safety checks stay injected.
@MainActor
struct EagleAuraStudioEntryFlow {
    let readMigrated: () -> Bool
    let readLegacyMode: () -> Int
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let markMigrated: () -> Void
    let normalizeDraftModes: () -> Void
    let islandAvailable: () -> Bool
    let readSelectedTarget: () -> Int
    let writeSelectedTarget: (Int) -> Void
    let islandTargetRaw: Int
    let dockTargetRaw: Int
    let reconcileActiveState: () -> Void
    let safetyLocked: () -> Bool
    let markSafetyBlocked: () -> Void
    let isApplying: () -> Bool

    func prepareForAppearance() {
        if !readMigrated() {
            let legacyMode = EagleAuraStudioMode(rawValue: readLegacyMode()) ?? .glow
            writeIslandMode(legacyMode.rawValue)
            writeDockMode((legacyMode == .tint ? EagleAuraStudioMode.glow : legacyMode).rawValue)
            markMigrated()
        }
        normalizeDraftModes()
        if !islandAvailable(),
           readSelectedTarget() == islandTargetRaw {
            writeSelectedTarget(dockTargetRaw)
        }
        reconcileActiveState()
        if safetyLocked() { markSafetyBlocked() }
    }

    func releaseChannelChanged() {
        guard !isApplying() else { return }
        normalizeDraftModes()
    }
}
