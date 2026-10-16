import Foundation

/// Owns Island catalog transport, validation and disk fallback outside the media facade.
/// Default ports retain the public cache location and shared network session.
nonisolated enum EagleIslandGalleryCatalogLoader {
    static func loadCatalog(
        force: Bool = false,
        fileManager: FileManager = .default,
        fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async throws -> [EagleIslandGalleryTheme] {
        let fm = fileManager
        let root = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("EagleGallery/Island", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let saved = root.appendingPathComponent("island-gallery-v1.json")
        var request = URLRequest(url: URL(string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/island-gallery-v1.json")!)
        request.timeoutInterval = 25
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        do {
            let (data, response) = try await fetch(request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, data.count <= 2 * 1024 * 1024 else { throw URLError(.badServerResponse) }
            let catalog = try JSONDecoder().decode(EagleIslandGalleryCatalog.self, from: data)
            guard catalog.isSupported else { throw URLError(.cannotParseResponse) }
            try data.write(to: saved, options: .atomic)
            return catalog.themes
        } catch {
            let data = try Data(contentsOf: saved)
            guard data.count <= 2 * 1024 * 1024 else { throw URLError(.cannotParseResponse) }
            let catalog = try JSONDecoder().decode(EagleIslandGalleryCatalog.self, from: data)
            guard catalog.isSupported else { throw URLError(.cannotParseResponse) }
            return catalog.themes
        }
    }
}
