import Foundation

/// Owns atomic frame writes after the app's existing image validation.
/// The caller retains the original staging and cleanup scope.
@MainActor
enum EagleDockGalleryFrameWriter {
    typealias Write = @MainActor @Sendable (Data, URL, Data.WritingOptions) throws -> Void

    static func write(
        _ data: Data,
        framePath: String,
        in directory: URL,
        using write: Write = { data, url, options in
            try data.write(to: url, options: options)
        }
    ) throws {
        try write(data, directory.appendingPathComponent(framePath), .atomic)
    }
}
