import Foundation

/// Applied-state decisions. Preferences, RGB conversion and mode policy stay injected.
@MainActor
struct EagleAuraStudioProfileState<Target> {
    let readActiveFlags: () -> UInt32
    let flag: (Target) -> UInt32
    let readActiveMode: (Target) -> Int
    let mode: (Target) -> EagleAuraStudioMode
    let readDraftRGB: (Target) -> (Int, Int, Int)
    let readActiveRGB: (Target) -> (Int, Int, Int)

    func isTargetActive(_ target: Target) -> Bool {
        readActiveFlags() & flag(target) != 0
    }

    func activeMode(for target: Target) -> EagleAuraStudioMode? {
        let rawValue = readActiveMode(target)
        return EagleAuraStudioMode(rawValue: rawValue)
    }

    func draftMatchesActive(_ target: Target) -> Bool {
        guard isTargetActive(target), activeMode(for: target) == mode(target) else {
            return false
        }
        // A fixed palette matches by mode, without reading either RGB profile.
        if mode(target).usesFixedPalette { return true }

        let draftRGB = readDraftRGB(target)
        let activeRGB = readActiveRGB(target)
        return draftRGB == activeRGB
    }
}
