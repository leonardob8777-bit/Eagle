import Foundation

/// Builds the Island collection and its visible projection without owning UI types.
@MainActor
enum EagleIslandGalleryCollection {
    static func assemble<Styles: Collection, Theme: Identifiable, Artwork>(
        styles: () -> Styles,
        isAvailable: (Styles.Element) -> Bool,
        remoteStyle: Styles.Element,
        themes: () -> [Theme],
        makeArtwork: (Styles.Element, Theme?) -> Artwork
    ) -> [Artwork] where Styles.Element: Equatable, Theme.ID == String {
        styles().filter(isAvailable).map { style in
            makeArtwork(style, style == remoteStyle
                ? themes().first(where: { $0.id == "singularity-live" }) : nil)
        } + themes().filter { $0.id != "singularity-live" }.map { makeArtwork(remoteStyle, $0) }
    }

    static func visible<Artwork: Identifiable>(
        search: () -> String,
        artworks: () -> [Artwork],
        filter: () -> EagleIslandGalleryFilter,
        favorites: () -> Set<String>,
        isLive: (Artwork) -> Bool,
        title: (Artwork) -> String,
        subtitle: (Artwork) -> String
    ) -> [Artwork] where Artwork.ID == String {
        let query = search().trimmingCharacters(in: .whitespacesAndNewlines)
        return artworks().filter { item in
            filter().includes(isLive: isLive(item), artworkID: item.id, favorites: favorites()) &&
                (query.isEmpty || title(item).localizedStandardContains(query) ||
                 subtitle(item).localizedStandardContains(query) || item.id.localizedStandardContains(query))
        }
    }
}
