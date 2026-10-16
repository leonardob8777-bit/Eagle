import Foundation

/// Public ordered Gallery projection, independent of selection and screen state.
nonisolated enum EagleDockGalleryCollection {
    static func visible(
        themes: [EagleDockGalleryTheme],
        orderedIDs: [String],
        filter: EagleDockGalleryMediaFilter,
        favorites: Set<String>
    ) -> [EagleDockGalleryTheme] {
        let themesByID = Dictionary(themes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return orderedIDs.compactMap { themesByID[$0] }
            .filter { filter.includes($0, favorites: favorites) }
    }
}
