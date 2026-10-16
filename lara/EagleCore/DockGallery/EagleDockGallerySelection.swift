import Foundation

/// Public selection/index rules over a value snapshot, without screen state.
nonisolated enum EagleDockGallerySelection {
    /// A single preference update. Persistence and its timing stay in the UI.
    enum LastViewed: Sendable {
        case still(String)
        case live(String)
    }

    /// Uses the displayed theme, not the active category (which may be Saves).
    /// Preserve the public else branch, including zero/negative frame counts.
    static func lastViewed(_ theme: EagleDockGalleryTheme?) -> LastViewed? {
        guard let theme else { return nil }
        if theme.frameCount > 1 {
            return .live(theme.id)
        } else {
            return .still(theme.id)
        }
    }

    static func selected(in themes: [EagleDockGalleryTheme], selectedID: String) -> EagleDockGalleryTheme? {
        themes.first(where: { $0.id == selectedID }) ??
            themes.first
    }

    static func currentIndex(in themes: [EagleDockGalleryTheme], selectedID: String) -> Int {
        themes.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    /// Retains the original arithmetic. The screen keeps its count/operation
    /// guards and supplies the existing arrow steps; this is not a clamping API.
    static func nextIndex(current: Int, step: Int, count: Int) -> Int {
        (current + step + count) % count
    }

    /// nil keeps the current selection and preview. A non-nil empty ID still
    /// requests a reset when no visible theme remains, even if the ID was empty.
    static func replacementID(in themes: [EagleDockGalleryTheme], selectedID: String) -> String? {
        if !themes.contains(where: { $0.id == selectedID }) {
            return themes.first?.id ?? ""
        }
        return nil
    }
}
