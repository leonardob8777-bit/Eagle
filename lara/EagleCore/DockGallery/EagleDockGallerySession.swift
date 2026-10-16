import Foundation

/// Transient Gallery state. Preferences, I/O and UI effects remain outside it.
nonisolated struct EagleDockGallerySession: Sendable {
    var selectedRemoteID = ""
    var mediaFilter: EagleDockGalleryMediaFilter = .still
    var rememberedSelections: EagleDockGallerySelectionMemory = .init()
    var shuffledRemoteIDs: [String] = []
    var visitStarted = false
    var readyRemotePreviewID = ""

    mutating func beginVisit() {
        visitStarted = true
        shuffledRemoteIDs = []
        selectedRemoteID = ""
        readyRemotePreviewID = ""
        rememberedSelections = .init()
        mediaFilter = .still
    }

    /// The caller checks eligibility and snapshots the displayed ID before mutation.
    mutating func selectCategory(_ filter: EagleDockGalleryMediaFilter, remembering selectedThemeID: String?) {
        rememberedSelections.remember(id: selectedThemeID, for: mediaFilter)
        readyRemotePreviewID = ""
        mediaFilter = filter
        selectedRemoteID = rememberedSelections.restoredID(for: filter) ?? ""
    }

    /// The caller retains operation/count guards and supplies the existing arrow steps.
    mutating func step(_ step: Int, in themes: [EagleDockGalleryTheme]) {
        let current = EagleDockGallerySelection.currentIndex(in: themes, selectedID: selectedRemoteID)
        let next = EagleDockGallerySelection.nextIndex(current: current, step: step, count: themes.count)
        readyRemotePreviewID = ""
        selectedRemoteID = themes[next].id
    }

    /// An unchanged order requests no State write and preserves the stored IDs.
    func adoptingOrder(_ order: [String]) -> Self? {
        guard shuffledRemoteIDs != order else { return nil }
        var updated = self
        updated.shuffledRemoteIDs = order
        return updated
    }

    /// nil preserves the current session without a State write. An explicit
    /// replacement, even an empty ID, still resets the previous preview.
    func reconcilingSelection(in themes: [EagleDockGalleryTheme]) -> Self? {
        guard let replacementID = EagleDockGallerySelection.replacementID(in: themes, selectedID: selectedRemoteID) else { return nil }
        var updated = self
        updated.readyRemotePreviewID = ""
        updated.selectedRemoteID = replacementID
        return updated
    }
}
