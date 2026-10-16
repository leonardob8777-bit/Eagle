import Foundation

/// Aura editor eligibility and stored-mode fallback, with existing feature policy injected.
@MainActor
enum EagleAuraStudioModePolicy {
    static func allows(
        _ mode: EagleAuraStudioMode,
        isIsland: @autoclosure () -> Bool,
        pulseAllowed: () -> Bool,
        rainbowAllowed: () -> Bool
    ) -> Bool {
        switch mode {
        case .glow:
            return true
        case .pulse:
            return pulseAllowed()
        case .rainbow:
            // Animated palettes are Island-only. Dock keeps its independently
            // verified static renderer and cannot receive these modes.
            return isIsland() && rainbowAllowed()
        case .photo, .photoRainbow, .photoInferno, .photoSky, .photoVortex,
             .photoBubblegum, .photoTraffic:
            // Photo styles moved to Island Gallery. Keeping the enum values
            // here lets Aura Studio describe an active Gallery style without
            // exposing a second, conflicting Apply control.
            return false
        case .tint:
            // Keep the implementation available for future validation, but do
            // not expose or reselect Tint in the public Aura Studio build.
            return false
        }
    }

    static func normalizedMode(
        rawValue: Int,
        allows: (EagleAuraStudioMode) -> Bool
    ) -> EagleAuraStudioMode {
        let stored = EagleAuraStudioMode(rawValue: rawValue) ?? .glow
        return allows(stored) ? stored : .glow
    }
}
