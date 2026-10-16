import Foundation

/// Per-visit category selections, owned as a value by the Gallery screen.
nonisolated struct EagleDockGallerySelectionMemory: Sendable {
    private var ids: [EagleDockGalleryMediaFilter: String] = [:]

    mutating func remember(id: String?, for filter: EagleDockGalleryMediaFilter) {
        ids[filter] = id
    }

    func restoredID(for filter: EagleDockGalleryMediaFilter) -> String? {
        ids[filter]
    }
}
