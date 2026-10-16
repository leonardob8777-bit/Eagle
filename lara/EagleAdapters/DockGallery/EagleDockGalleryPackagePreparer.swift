import Foundation

/// Owns synchronous package-file preparation at Eagle's image adapter boundary.
/// Downloading and presentation state remain with the caller; diagnostics are injected.
@MainActor
enum EagleDockGalleryPackagePreparer {
    static func prepare(
        _ data: Data,
        theme: EagleDockGalleryTheme,
        destination: URL,
        log: @escaping @Sendable (String) -> Void
    ) throws -> URL {
        let archive = try EagleDockGalleryPackageArchive(
            data: data,
            frameCount: theme.frameCount,
            log: log
        )
        let files = archive.files

        let fm = FileManager.default
        let staging = try EagleDockGalleryStagingDirectory.create(
            beside: destination,
            themeID: theme.id,
            fileManager: fm
        )
        try EagleDockGalleryCacheCommit.commit(staging: staging, to: destination, fileManager: fm) {
            for entry in files {
                let frameData = try archive.extract(entry)
                try EagleDockGalleryFrameImage.validate(frameData, theme: theme)
                try EagleDockGalleryFrameWriter.write(frameData, framePath: entry.path, in: staging)
            }
            guard EagleDockGalleryPackageCache.isValid(in: staging, theme: theme) else {
                throw URLError(.cannotDecodeContentData)
            }
        }
        return destination
    }
}
