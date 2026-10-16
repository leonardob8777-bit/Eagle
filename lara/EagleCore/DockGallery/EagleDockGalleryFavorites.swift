import Foundation

/// Public favorite-ID membership and JSON rules, without storage or screen state.
nonisolated enum EagleDockGalleryFavorites {
    static func toggling(_ ids: Set<String>, id: String) -> Set<String> {
        var updated = ids
        if !updated.insert(id).inserted { updated.remove(id) }
        return updated
    }

    static func decode(_ json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    static func encode(_ ids: Set<String>) -> String? {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
