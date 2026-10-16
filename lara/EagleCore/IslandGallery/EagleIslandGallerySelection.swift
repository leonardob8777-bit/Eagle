import Foundation

/// Synchronous selection, category memory and navigation coordination.
/// Storage remains supplied by the screen; reads are deferred to preserve ordering.
@MainActor
struct EagleIslandGallerySelection<Artwork: Identifiable> where Artwork.ID == String {
    let readVisibleArtworks: () -> [Artwork]
    let readApplying: () -> Bool
    let readSelectedID: () -> String
    let writeSelectedID: (String) -> Void
    let writeSelectedRaw: (Int) -> Void
    let readFilter: () -> EagleIslandGalleryFilter
    let writeFilter: (EagleIslandGalleryFilter) -> Void
    let readMemory: () -> [EagleIslandGalleryFilter: String]
    let writeMemory: ([EagleIslandGalleryFilter: String]) -> Void
    let rawStyle: (Artwork) -> Int
    let feedback: () -> Void

    private var visibleArtworks: [Artwork] { readVisibleArtworks() }
    private var applying: Bool { readApplying() }
    private var selectedID: String {
        get { readSelectedID() }
        nonmutating set { writeSelectedID(newValue) }
    }
    private var filter: EagleIslandGalleryFilter {
        get { readFilter() }
        nonmutating set { writeFilter(newValue) }
    }
    private var rememberedSelections: [EagleIslandGalleryFilter: String] {
        get { readMemory() }
        nonmutating set { writeMemory(newValue) }
    }

    var selected: Artwork? {
        visibleArtworks.first(where: { $0.id == selectedID }) ?? visibleArtworks.first
    }

    var selectionIndex: Int {
        visibleArtworks.firstIndex(where: { $0.id == selected?.id }) ?? 0
    }

    func select(_ item: Artwork) {
        guard !applying else { return }
        selectedID = item.id
        writeSelectedRaw(rawStyle(item))
        rememberedSelections[filter] = item.id
        feedback()
    }

    func selectFilter(_ value: EagleIslandGalleryFilter) {
        guard !applying else { return }
        if let selected { rememberedSelections[filter] = selected.id }
        filter = value
        if let remembered = rememberedSelections[value], visibleArtworks.contains(where: { $0.id == remembered }) {
            selectedID = remembered
        }
        synchronizeSelection()
        if let selected { writeSelectedRaw(rawStyle(selected)) }
    }

    func synchronizeSelection() {
        guard !applying else { return }
        if !visibleArtworks.contains(where: { $0.id == selectedID }), let first = visibleArtworks.first {
            selectedID = first.id
            writeSelectedRaw(rawStyle(first))
        }
    }

    func step(_ delta: Int) {
        guard !applying, visibleArtworks.count > 1 else { return }
        let next = (selectionIndex + delta + visibleArtworks.count) % visibleArtworks.count
        select(visibleArtworks[next])
    }
}
