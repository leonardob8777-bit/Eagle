import Foundation

/// Recovers the existing saved selection without owning preference storage.
/// Callbacks remain synchronous and lazy to preserve read/write ordering.
@MainActor
enum EagleDockGalleryStoredSelection {
    static func reconcile(
        selectedRaw: () -> Int,
        setSelectedRaw: (Int) -> Void,
        hasVerifiedDock: () -> Bool,
        activeRaw: () -> Int,
        setActiveRaw: (Int) -> Void,
        activeDockModeRaw: () -> Int,
        setActiveDockModeRaw: (Int) -> Void,
        activeRemoteID: () -> String,
        setActiveRemoteID: (String) -> Void
    ) {
        if EagleDockGalleryBuiltInTheme(rawValue: selectedRaw()) == nil {
            setSelectedRaw(EagleDockGalleryBuiltInTheme.bubblegum.rawValue)
        }
        if hasVerifiedDock(),
           EagleDockGalleryBuiltInTheme(rawValue: activeRaw()) != nil,
           activeDockModeRaw() == 1 {
            // 1.0.2 stored Gallery artwork as generic Dock Glow. Preserve
            // the verified selection once, then use the exact style mode.
            setActiveDockModeRaw(activeRaw())
        } else if !hasVerifiedDock() || EagleDockGalleryBuiltInTheme(rawValue: activeDockModeRaw()) == nil {
            setActiveRaw(0)
        }
        if hasVerifiedDock(), activeRemoteID().isEmpty,
           let legacyID = remoteID(forLegacyMode: activeDockModeRaw()) {
            setActiveRemoteID(legacyID)
        }
    }

    nonisolated static func remoteID(forLegacyMode mode: Int) -> String? {
        [
            15: "bubblegum", 16: "springfield", 17: "bikini-bottom",
            18: "neon-chase", 19: "neon-drift", 20: "glitch-orbit",
            21: "pop-glasses", 22: "inferno-wings", 23: "cool-cat",
            24: "cyber-love", 25: "padded-room", 26: "noir-vision",
            27: "thirsty-cat", 28: "duck-mood", 29: "blue-screen",
            30: "walking-flame", 31: "prism-blur"
        ][mode]
    }
}
