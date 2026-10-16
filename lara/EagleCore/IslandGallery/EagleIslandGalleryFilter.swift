import Foundation

/// Island category metadata and inclusion rules, independent of presentation.
/// Deferred properties preserve the original per-category artwork reads.
nonisolated enum EagleIslandGalleryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, live, still, favorites
    var id: String { rawValue }
    func title(localizedText: (String, String) -> String) -> String {
        switch self {
        case .all: return localizedText("All", "Todo")
        case .live: return "Live"
        case .still: return "Static"
        case .favorites: return "Saves"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .live: return "play.circle"
        case .still: return "sparkles"
        case .favorites: return "heart"
        }
    }
    func includes(
        isLive: @autoclosure () -> Bool,
        artworkID: @autoclosure () -> String,
        favorites: Set<String>
    ) -> Bool {
        switch self {
        case .all: return true
        case .live: return isLive()
        case .still: return !isLive()
        case .favorites: return favorites.contains(artworkID())
        }
    }
}
