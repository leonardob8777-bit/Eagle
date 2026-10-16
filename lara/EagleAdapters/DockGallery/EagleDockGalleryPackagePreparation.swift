import Foundation

/// Coordinates the original cache/download/file flow outside the Gallery screen.
/// Presentation hooks are synchronous and nonescaping; diagnostics are obtained late.
@MainActor
struct EagleDockGalleryPackagePreparation {
    private let downloader: EagleDockGalleryPackageDownloader
    private let cache: EagleDockGalleryPackageCache

    nonisolated init(
        downloader: EagleDockGalleryPackageDownloader = EagleDockGalleryPackageDownloader(),
        cache: EagleDockGalleryPackageCache = EagleDockGalleryPackageCache()
    ) {
        self.downloader = downloader
        self.cache = cache
    }

    func prepare(
        _ theme: EagleDockGalleryTheme,
        diagnostics: @MainActor @Sendable () -> (@Sendable (String) -> Void),
        willDownload: @MainActor @Sendable () -> Void,
        didFinish: @MainActor @Sendable () -> Void
    ) async throws -> URL {
        let location = try cache.locate(theme)
        let destination = location.directory
        if location.isValid { return destination }
        willDownload()
        defer { didFinish() }

        let data = try await downloader.download(theme)

        return try EagleDockGalleryPackagePreparer.prepare(
            data,
            theme: theme,
            destination: destination,
            log: diagnostics()
        )
    }
}
