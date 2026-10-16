import Foundation

/// Owns Island favorite decoding and toggle/write/feedback sequencing.
/// The screen retains its existing AppStorage key and observation behavior.
nonisolated enum EagleIslandGalleryFavorites {
    static func decode(_ json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    @MainActor
    static func toggle(
        applying: () -> Bool,
        favorites: () -> Set<String>,
        artworkID: () -> String,
        save: (String) -> Void,
        feedback: () -> Void
    ) {
        guard !applying() else { return }
        var ids = favorites()
        if !ids.insert(artworkID()).inserted { ids.remove(artworkID()) }
        if let data = try? JSONEncoder().encode(ids.sorted()), let json = String(data: data, encoding: .utf8) {
            save(json)
        }
        feedback()
    }
}
