import Foundation

/// Owns the original package preparation/replacement cleanup scope.
/// The caller creates staging first and supplies synchronous frame preparation.
@MainActor
enum EagleDockGalleryCacheCommit {
    static func commit(
        staging: URL,
        to destination: URL,
        fileManager: FileManager,
        prepareFrames: @MainActor () throws -> Void
    ) throws {
        do {
            try prepareFrames()
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}
