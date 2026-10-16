import Foundation

/// Composes cache-directory lookup and image validation outside the Gallery screen.
/// The original synchronous cache-hit rules and directory service defaults are retained.
@MainActor
struct EagleDockGalleryPackageCache {
    struct Location {
        let directory: URL
        let isValid: Bool
    }

    private let directories: EagleDockGalleryCacheDirectory

    nonisolated init(directories: EagleDockGalleryCacheDirectory = EagleDockGalleryCacheDirectory()) {
        self.directories = directories
    }

    func locate(_ theme: EagleDockGalleryTheme) throws -> Location {
        let directory = try directories.directory(for: theme)
        return Location(directory: directory, isValid: Self.isValid(in: directory, theme: theme))
    }

    static func isValid(in directory: URL, theme: EagleDockGalleryTheme) -> Bool {
        EagleDockGalleryCachedFrames.areValid(in: directory, theme: theme) { data, theme in
            EagleDockGalleryFrameImage.isValid(data, theme: theme)
        }
    }
}
