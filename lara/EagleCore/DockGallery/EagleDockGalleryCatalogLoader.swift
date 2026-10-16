import Foundation

/// Owns the public catalog request and data pipeline outside the Gallery screen.
/// Retains MainActor execution and the shared session used by the public store.
@MainActor
struct EagleDockGalleryCatalogLoader {
    typealias Fetch = @MainActor @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let catalogURL = URL(string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/dock-v1.json?catalog=21")!
    private let fetch: Fetch

    nonisolated init(fetch: @escaping Fetch = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.fetch = fetch
    }

    func load(force: Bool = false) async throws -> [EagleDockGalleryTheme] {
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 25
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
        let (data, response) = try await fetch(request)
        try EagleDockGalleryCatalogResponse.validate(
            data: data,
            httpStatusCode: (response as? HTTPURLResponse)?.statusCode
        )
        return try EagleDockGalleryCatalog.decodeSupportedThemes(from: data)
    }
}
