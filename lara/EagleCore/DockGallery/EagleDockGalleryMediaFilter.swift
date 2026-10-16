import Foundation

/// Public Gallery classification and labels, independent of screen state.
/// Classification deliberately does not validate a theme's package format.
nonisolated enum EagleDockGalleryMediaFilter: String, CaseIterable, Sendable {
    case still = "Static"
    case live = "Live"
    case favorites = "Favorites"

    var title: String {
        self == .favorites ? "Saves" : rawValue
    }

    var icon: String {
        switch self {
        case .still: return "sparkles"
        case .live: return "play.circle"
        case .favorites: return "heart"
        }
    }

    func includes(_ theme: EagleDockGalleryTheme, favorites: Set<String>) -> Bool {
        switch self {
        case .still: return theme.frameCount == 1
        case .live: return theme.frameCount > 1
        case .favorites: return favorites.contains(theme.id)
        }
    }
}
