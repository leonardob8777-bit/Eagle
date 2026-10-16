import Foundation

/// Coordinates screen loading and recovery; transport and UI state stay injected.
/// Runs in the caller's task, preserving cancellation and main-actor ordering.
@MainActor
enum EagleIslandGalleryLoadFlow {
    static func load<Theme: Sendable>(
        force: Bool = false,
        readLoading: () -> Bool,
        writeLoading: (Bool) -> Void,
        fetch: @MainActor (Bool) async throws -> [Theme],
        writeThemes: ([Theme]) -> Void,
        writeFailed: (Bool) -> Void,
        restoreSelection: () -> Void,
        synchronizeSelection: () -> Void
    ) async {
        guard !readLoading() else { return }
        writeLoading(true)
        defer { writeLoading(false) }
        do {
            let themes = try await fetch(force)
            guard !Task.isCancelled else { return }
            writeThemes(themes)
            writeFailed(false)
            restoreSelection()
            synchronizeSelection()
        } catch {
            if !Task.isCancelled { writeFailed(true) }
        }
    }
}
