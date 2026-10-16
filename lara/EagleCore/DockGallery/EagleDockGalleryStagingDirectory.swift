import Foundation

/// Owns temporary package-directory creation outside the Gallery screen.
/// The caller retains its file manager and original cleanup scope.
@MainActor
enum EagleDockGalleryStagingDirectory {
    typealias MakeIdentifier = @MainActor @Sendable () -> UUID

    static func create(
        beside destination: URL,
        themeID: String,
        fileManager: FileManager,
        makeIdentifier: MakeIdentifier = { UUID() }
    ) throws -> URL {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(themeID)-\(makeIdentifier().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }
}
