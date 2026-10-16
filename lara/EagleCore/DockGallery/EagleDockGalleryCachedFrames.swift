import Foundation

/// Owns cached-frame traversal and reads outside the Gallery screen.
/// The app supplies synchronous image validation in the original actor context.
@MainActor
enum EagleDockGalleryCachedFrames {
    typealias Read = @MainActor @Sendable (URL, Data.ReadingOptions) throws -> Data
    typealias ValidateFrame = @MainActor @Sendable (Data, EagleDockGalleryTheme) -> Bool

    static func areValid(
        in directory: URL,
        theme: EagleDockGalleryTheme,
        read: Read = { url, options in
            try Data(contentsOf: url, options: options)
        },
        validateFrame: ValidateFrame
    ) -> Bool {
        guard theme.isSupportedPackage else { return false }
        return (1...theme.frameCount).allSatisfy { index in
            let url = directory.appendingPathComponent(String(format: "frame%02d.png", index))
            guard let data = try? read(url, .mappedIfSafe) else { return false }
            return validateFrame(data, theme)
        }
    }
}
