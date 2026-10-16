import Foundation

@main
private enum EagleDockSelectionMemoryChecks {
    static func theme(_ id: String) -> EagleDockGalleryTheme {
        let url = URL(string: "https://fixture.invalid/theme")!
        return EagleDockGalleryTheme(
            id: id, version: 1, title: "unused", titleES: "", subtitle: "", subtitleES: "", accent: "",
            previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
            frameCount: 1, fps: 1, width: 0, height: 0
        )
    }

    static func main() async {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        var memory = EagleDockGallerySelectionMemory()
        expect(EagleDockGalleryMediaFilter.allCases.allSatisfy { memory.restoredID(for: $0) == nil },
               "A new visit must have no saved category selections")
        memory.remember(id: "static-2", for: .still)
        memory.remember(id: "live-3", for: .live)
        memory.remember(id: "saved-1", for: .favorites)
        expect(memory.restoredID(for: .still) == "static-2" && memory.restoredID(for: .live) == "live-3" &&
               memory.restoredID(for: .favorites) == "saved-1", "Each category must retain its own selection")
        memory.remember(id: nil, for: .live)
        expect(memory.restoredID(for: .live) == nil && memory.restoredID(for: .still) == "static-2" &&
               memory.restoredID(for: .favorites) == "saved-1", "Remembering nil must remove only that category's previous entry")
        memory.remember(id: "", for: .live)
        expect(memory.restoredID(for: .live) == .some(""), "An explicitly empty ID must be distinguishable from a missing entry")
        let snapshot = memory
        memory.remember(id: "new-static", for: .still)
        expect(snapshot.restoredID(for: .still) == "static-2" && memory.restoredID(for: .still) == "new-static",
               "Memory must have independent value-copy semantics")
        memory = .init()
        expect(EagleDockGalleryMediaFilter.allCases.allSatisfy { memory.restoredID(for: $0) == nil },
               "Visit reset must clear every category")
        for id in ["", " x ", "X", "é", "e\u{301}", "🦅"] {
            memory.remember(id: id, for: .favorites)
            expect(memory.restoredID(for: .favorites)?.utf8.elementsEqual(id.utf8) == true,
                   "Storage must preserve the exact ID, without normalization")
        }

        let visible = [theme("first"), theme("current"), theme("current")]
        expect(EagleDockGallerySelection.replacementID(in: visible, selectedID: "current") == nil,
               "A visible selection keeps its preview even when it is not first")
        expect(EagleDockGallerySelection.replacementID(in: visible, selectedID: "gone") == "first",
               "A missing remembered theme falls back to the first visible theme")
        expect(EagleDockGallerySelection.replacementID(in: [], selectedID: "gone") == .some(""),
               "An emptied category requests an explicit reset")
        expect(EagleDockGallerySelection.replacementID(in: [], selectedID: "") == .some(""),
               "An empty category must reset even if selected ID was already empty")
        expect(EagleDockGallerySelection.replacementID(in: [theme("")], selectedID: "") == nil,
               "A visible empty-ID theme is valid and keeps its preview")
        expect(EagleDockGallerySelection.replacementID(in: [theme("")], selectedID: "missing") == .some(""),
               "Falling back to an empty-ID theme must still request a reset")
        expect(EagleDockGallerySelection.replacementID(in: [theme("first"), theme("é")], selectedID: "e\u{301}") == nil,
               "Matching retains Swift String canonical Unicode equality")
        expect(EagleDockGallerySelection.replacementID(in: [theme("x"), theme("X")], selectedID: " X ") == "x",
               "Matching must not trim or fold case")

        let detached = await Task.detached {
            var copy = snapshot
            copy.remember(id: nil, for: .favorites)
            return (copy, EagleDockGallerySelection.replacementID(in: visible, selectedID: "gone"))
        }.value
        expect(detached.0.restoredID(for: .favorites) == nil && snapshot.restoredID(for: .favorites) == "saved-1" &&
               detached.1 == "first", "Core memory and replacement must work independently outside MainActor")
        print("PASS: \(checks) focused memory/recovery assertions: category isolation, nil removal/empty ID, value copies/reset, exact stored IDs, fallback/keep and detached use")
    }
}
