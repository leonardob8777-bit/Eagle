import Foundation

/// Owns cache-root creation and theme-directory naming outside the screen.
/// Retains the public store's actor context and per-operation manager lookup.
@MainActor
struct EagleDockGalleryCacheDirectory {
    typealias FileManagerProvider = @MainActor @Sendable () -> FileManager

    private let fileManager: FileManagerProvider

    nonisolated init(fileManager: @escaping FileManagerProvider = { FileManager.default }) {
        self.fileManager = fileManager
    }

    func directory(for theme: EagleDockGalleryTheme) throws -> URL {
        let root = try fileManager().url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("EagleGallery/Dock", isDirectory: true)
        try fileManager().createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(theme.id)-v\(theme.version)", isDirectory: true)
    }
}
