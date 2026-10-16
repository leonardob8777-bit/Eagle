import Foundation

/// Owns the public theme-package request and integrity check outside the screen.
/// Retains the public store's actor context and shared-session behavior.
@MainActor
struct EagleDockGalleryPackageDownloader {
    typealias Fetch = @MainActor @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let fetch: Fetch

    nonisolated init(fetch: @escaping Fetch = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.fetch = fetch
    }

    func download(_ theme: EagleDockGalleryTheme) async throws -> Data {
        var request = URLRequest(url: theme.packageURL)
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await fetch(request)
        try EagleDockGalleryPackageValidation.validateDownload(
            data,
            httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
            expectedByteCount: theme.byteCount,
            expectedSHA256: theme.sha256
        )
        return data
    }
}
