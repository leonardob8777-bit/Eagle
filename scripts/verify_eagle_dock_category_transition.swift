import Foundation

struct CategoryTheme { let id: String }
struct CategoryStore { var downloadingID: String? }
struct CategoryInput {
    let state: EagleDockGallerySession
    let applying: Bool
    let downloadingID: String?
    let displayedID: String?
}

// Compare the stored bytes too: Swift String equality alone equates canonically
// equivalent Unicode IDs, while this transition must preserve their encoding.
struct CategorySnapshot: Equatable {
    let filter: String
    let selected: [UInt8]
    let preview: [UInt8]
    let order: [[UInt8]]
    let started: Bool
    let memory: [[UInt8]?]

    init(filter: EagleDockGalleryMediaFilter, selected: String, preview: String,
         order: [String], started: Bool, memory: [String?]) {
        self.filter = filter.rawValue
        self.selected = Array(selected.utf8)
        self.preview = Array(preview.utf8)
        self.order = order.map { Array($0.utf8) }
        self.started = started
        self.memory = memory.map { $0.map { Array($0.utf8) } }
    }
}

@main
private enum EagleDockCategoryChecks {
    static func main() async {
        let filters = EagleDockGalleryMediaFilter.allCases
        let displayedIDs: [String?] = [nil, "", "actual", "UPPER", " spaced ", "é", "e\u{301}", "💠"]
        let memorySeeds: [[String?]] = [
            [nil, nil, nil], ["saved-static", "saved-live", "saved-saves"],
            ["", "", nil], ["e\u{301}", "é", "💠"],
        ]
        var cases = 0
        var allowed = 0
        for original in filters {
            for target in filters {
                for applying in [false, true] {
                    for download in [nil, "", "downloading"] as [String?] {
                        for displayed in displayedIDs {
                            for seed in memorySeeds {
                                for selected in ["stale", ""] {
                                    for preview in ["", "ready"] {
                                        for order in [[], ["b", "a", "b"]] as [[String]] {
                                            for started in [false, true] {
                                                var state = EagleDockGallerySession()
                                                state.mediaFilter = original
                                                state.selectedRemoteID = selected
                                                state.readyRemotePreviewID = preview
                                                state.shuffledRemoteIDs = order
                                                state.visitStarted = started
                                                for (filter, id) in zip(filters, seed) {
                                                    state.rememberedSelections.remember(id: id, for: filter)
                                                }
                                                let input = CategoryInput(state: state, applying: applying,
                                                                          downloadingID: download, displayedID: displayed)
                                                let baseline = BaselineCategoryFixture(input)
                                                let owned = OwnedCategoryFixture(input)
                                                let before = baseline.snapshot()
                                                precondition(owned.snapshot() == before)
                                                baseline.selectMediaFilter(target)
                                                owned.selectMediaFilter(target)
                                                precondition(owned.snapshot() == baseline.snapshot(), "State differs from exact public helper")
                                                precondition(owned.events == baseline.events, "Public read/sync/feedback ordering changed")
                                                precondition(owned.readSnapshots == baseline.readSnapshots &&
                                                             owned.syncSnapshots == baseline.syncSnapshots, "State at external boundaries differs")
                                                if original == target || applying || download != nil {
                                                    precondition(owned.snapshot() == before && owned.events.isEmpty,
                                                                 "A blocked or repeated category must not read selection, mutate, sync or give feedback")
                                                } else {
                                                    allowed += 1
                                                    precondition(owned.events == ["read", "sync", "feedback"])
                                                    precondition(owned.readSnapshots == [before], "Displayed ID must be read before mutation")
                                                    precondition(owned.syncSnapshots == [owned.snapshot()], "Synchronization must see completed transition")
                                                    precondition(owned.session.mediaFilter == target && owned.session.readyRemotePreviewID.isEmpty)
                                                    precondition(owned.session.shuffledRemoteIDs == order && owned.session.visitStarted == started)
                                                    let saved = owned.session.rememberedSelections.restoredID(for: original)
                                                    precondition(saved.map { Array($0.utf8) } == displayed.map { Array($0.utf8) },
                                                                 "Remember displayed identity, including nil deletion and stored empty IDs")
                                                    let restored = state.rememberedSelections.restoredID(for: target) ?? ""
                                                    precondition(Array(owned.session.selectedRemoteID.utf8) == Array(restored.utf8))
                                                }
                                                cases += 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        var original = EagleDockGallerySession()
        original.selectedRemoteID = "original"
        original.readyRemotePreviewID = "original-ready"
        original.rememberedSelections.remember(id: "saved-live", for: .live)
        let copy = original
        let transitioned = await Task.detached {
            var result = copy
            result.selectCategory(.live, remembering: "displayed-static")
            return result
        }.value
        precondition(transitioned.mediaFilter == .live && transitioned.selectedRemoteID == "saved-live" &&
                     transitioned.readyRemotePreviewID.isEmpty &&
                     transitioned.rememberedSelections.restoredID(for: .still) == "displayed-static")
        precondition(original.selectedRemoteID == "original" && original.readyRemotePreviewID == "original-ready" &&
                     original.rememberedSelections.restoredID(for: .still) == nil,
                     "A detached copy's transition must not mutate the original session")
        print("PASS: \(cases) exact public/owned category cases (\(allowed) allowed); guard no-ops, snapshot/sync/feedback order, nil/empty/Unicode memory, preserved visit order/flag and detached copy isolation")
    }
}
