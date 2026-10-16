import Foundation

struct ReconciliationSnapshot: Equatable {
    let selected: [UInt8]
    let preview: [UInt8]
    let filter: String
    let order: [[UInt8]]
    let started: Bool
    let memory: [[UInt8]?]

    init(_ state: EagleDockGallerySession) {
        selected = Array(state.selectedRemoteID.utf8)
        preview = Array(state.readyRemotePreviewID.utf8)
        filter = state.mediaFilter.rawValue
        order = state.shuffledRemoteIDs.map { Array($0.utf8) }
        started = state.visitStarted
        memory = EagleDockGalleryMediaFilter.allCases.map {
            state.rememberedSelections.restoredID(for: $0).map { Array($0.utf8) }
        }
    }
}

@main
private enum ReconciliationChecks {
    static func theme(_ id: String, _ frames: Int = 1) -> EagleDockGalleryTheme {
        let url = URL(string: "https://fixture.invalid/theme")!
        return EagleDockGalleryTheme(id: id, version: 1, title: "", titleES: "", subtitle: "", subtitleES: "", accent: "",
                                     previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
                                     frameCount: frames, fps: 1, width: 0, height: 0)
    }

    static func main() async {
        let orderCases: [(previous: [String], proposed: [String], changes: Bool)] = [
            ([], [], false),
            (["a", "a"], ["a", "a"], false),
            (["é"], ["e\u{301}"], false),
            (["e\u{301}"], ["é"], false),
            ([], [""], true),
            (["a"], [], true),
            (["a", "b"], ["b", "a"], true),
            (["a", "a"], ["a"], true),
            ([" x "], ["x"], true),
            (["x"], ["X", "e\u{301}"], true),
        ]
        for scenario in orderCases {
            var original = EagleDockGallerySession()
            original.selectedRemoteID = "selected"
            original.readyRemotePreviewID = "ready"
            original.mediaFilter = .favorites
            original.visitStarted = true
            original.shuffledRemoteIDs = scenario.previous
            original.rememberedSelections.remember(id: "still", for: .still)
            original.rememberedSelections.remember(id: "e\u{301}", for: .live)
            original.rememberedSelections.remember(id: "", for: .favorites)
            let before = ReconciliationSnapshot(original)
            let result = original.adoptingOrder(scenario.proposed)
            if scenario.changes {
                var expected = original
                expected.shuffledRemoteIDs = scenario.proposed
                precondition(result.map(ReconciliationSnapshot.init) == ReconciliationSnapshot(expected),
                             "Order adoption must preserve all other session fields and exact proposed ID bytes")
            } else {
                precondition(result == nil, "Equal orders, including canonical Unicode equivalents, must request no write")
            }
            precondition(ReconciliationSnapshot(original) == before, "Order adoption must leave its input unchanged")
        }

        // Equal String values can have different bytes. The actual screen's
        // no-write branch must retain the original bytes and ready selection.
        for pair in [("é", "e\u{301}"), ("e\u{301}", "é")] {
            var original = EagleDockGallerySession()
            original.selectedRemoteID = pair.0
            original.readyRemotePreviewID = "ready"
            original.shuffledRemoteIDs = [pair.0]
            let previous = PreviousReconciliationFixture()
            let owned = OwnedReconciliationFixture()
            previous.session = original
            owned.session = original
            previous.remoteGallery.themes = [theme(pair.0)]
            owned.remoteGallery.themes = [theme(pair.0)]
            previous.writes = 0
            owned.writes = 0
            previous.synchronizeFixture(order: [pair.1])
            owned.synchronizeFixture(order: [pair.1])
            let unchanged = ReconciliationSnapshot(original)
            precondition(previous.writes == 0 && owned.writes == 0)
            precondition(ReconciliationSnapshot(previous.session) == unchanged && ReconciliationSnapshot(owned.session) == unchanged)
            precondition(previous.visibleStates == [unchanged] && owned.visibleStates == [unchanged])
            precondition(previous.rememberStates == [unchanged] && owned.rememberStates == [unchanged])
        }

        let large = (0..<428).map { theme("large-\($0)", $0 % 2 == 0 ? 1 : 17) }
        let catalogs: [[EagleDockGalleryTheme]] = [
            [], [theme("")], [theme("a"), theme("b", 17)],
            [theme("a"), theme("a", 17), theme("b", 17)],
            [theme("é"), theme("e\u{301}", 17), theme("", 17)],
            [theme("a", 17), theme("b"), theme(" c ", 17)], large,
        ]
        var cases = 0
        var preserved = 0
        var replacements = 0
        for catalog in catalogs {
            let ids = catalog.map(\.id)
            for filter in EagleDockGalleryMediaFilter.allCases {
                for favorites in [Set<String>(), Set(ids), Set(["a", "", "large-214"])] {
                    for order in [ids, Array(ids.reversed()), ["missing"] + ids + Array(ids.prefix(1))] {
                        for previousOrder in [order, ["stale"]] {
                            for selected in ["missing", "a", "b", "", "é", "e\u{301}", "large-214"] {
                                for preview in ["", "ready"] {
                                    var initial = EagleDockGallerySession()
                                    initial.selectedRemoteID = selected
                                    initial.readyRemotePreviewID = preview
                                    initial.mediaFilter = filter
                                    initial.shuffledRemoteIDs = previousOrder
                                    initial.visitStarted = previousOrder.isEmpty
                                    initial.rememberedSelections.remember(id: "", for: .still)
                                    initial.rememberedSelections.remember(id: "é", for: .favorites)
                                    let before = ReconciliationSnapshot(initial)
                                    let previous = PreviousReconciliationFixture()
                                    let owned = OwnedReconciliationFixture()
                                    previous.session = initial
                                    owned.session = initial
                                    previous.remoteGallery.themes = catalog
                                    owned.remoteGallery.themes = catalog
                                    previous.favoriteIDs = favorites
                                    owned.favoriteIDs = favorites
                                    previous.writes = 0
                                    owned.writes = 0

                                    let changedOrder = previousOrder != order
                                    var expected = initial
                                    if changedOrder { expected.shuffledRemoteIDs = order }
                                    let afterOrder = ReconciliationSnapshot(expected)
                                    let visible = EagleDockGalleryCollection.visible(themes: catalog, orderedIDs: expected.shuffledRemoteIDs,
                                                                                    filter: filter, favorites: favorites)
                                    let missing = !visible.contains { $0.id == selected }
                                    let proposed = expected.reconcilingSelection(in: visible)
                                    if missing {
                                        replacements += 1
                                        expected.readyRemotePreviewID = ""
                                        expected.selectedRemoteID = visible.first?.id ?? ""
                                        precondition(proposed.map(ReconciliationSnapshot.init) == ReconciliationSnapshot(expected),
                                                     "Explicit replacement must clear preview, including empty-to-empty ID")
                                    } else {
                                        preserved += 1
                                        precondition(proposed == nil, "A valid selection must request no session assignment")
                                    }
                                    previous.synchronizeFixture(order: order)
                                    owned.synchronizeFixture(order: order)
                                    let final = ReconciliationSnapshot(expected)
                                    precondition(ReconciliationSnapshot(previous.session) == final && ReconciliationSnapshot(owned.session) == final)
                                    precondition(owned.visibleStates == [afterOrder] && previous.visibleStates == [afterOrder],
                                                 "Visible list must read after order adoption, before preview/selection changes")
                                    precondition(owned.rememberStates == [final] && previous.rememberStates == [final])
                                    precondition(owned.events == ["visible", "remember"] && owned.events == previous.events,
                                                 "One list read must precede reconciliation and one persistence call must follow")
                                    precondition(owned.writes == (changedOrder ? 1 : 0) + (missing ? 1 : 0),
                                                 "Do not write session on keep; commit one complete explicit replacement")
                                    precondition(previous.writes == (changedOrder ? 1 : 0) + (missing ? 2 : 0),
                                                 "Previous fixture must retain its two per-field replacement writes")
                                    precondition(ReconciliationSnapshot(initial) == before, "Reconciliation must not modify the input copy")
                                    cases += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        var seed = EagleDockGallerySession()
        seed.selectedRemoteID = "gone"
        seed.readyRemotePreviewID = "ready"
        seed.rememberedSelections.remember(id: "saved", for: .live)
        let snapshot = seed
        let visible = [theme("first")]
        let detached = await Task.detached {
            let replacement = snapshot.reconcilingSelection(in: visible)!
            return (replacement, replacement.reconcilingSelection(in: visible), snapshot.reconcilingSelection(in: []))
        }.value
        precondition(detached.0.selectedRemoteID == "first" && detached.0.readyRemotePreviewID.isEmpty && detached.1 == nil)
        precondition(detached.2?.selectedRemoteID == "" && detached.2?.rememberedSelections.restoredID(for: .live) == "saved")
        precondition(seed.selectedRemoteID == "gone" && seed.readyRemotePreviewID == "ready")
        let detachedOrder = await Task.detached {
            let reordered = snapshot.adoptingOrder(["b", "a", "b"])!
            return (reordered, reordered.adoptingOrder(["b", "a", "b"]))
        }.value
        var expectedDetached = seed
        expectedDetached.shuffledRemoteIDs = ["b", "a", "b"]
        precondition(ReconciliationSnapshot(detachedOrder.0) == ReconciliationSnapshot(expectedDetached) && detachedOrder.1 == nil)
        precondition(seed.shuffledRemoteIDs.isEmpty)
        print("PASS: \(orderCases.count) direct order-adoption cases, two real-helper Unicode no-write cases, detached adoption/no-op and exact session-copy isolation")
        print("PASS: \(cases) reconciliation scenarios (\(preserved) keep, \(replacements) replace); order/read/commit/persistence sequence, no-op writes, empty/Unicode/duplicate/428-theme catalogs, favorites and all session fields")
        print("PASS: detached keep/replace/empty reconciliation and input-copy isolation")
    }
}
