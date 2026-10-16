import Foundation

@main
private enum EagleDockVisitOrderChecks {
    static func theme(_ id: String, frames: Int = 1) -> EagleDockGalleryTheme {
        let url = URL(string: "https://fixture.invalid/theme")!
        return EagleDockGalleryTheme(
            id: id, version: 1, title: "unused", titleES: "", subtitle: "", subtitleES: "", accent: "",
            previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
            frameCount: frames, fps: 1, width: 0, height: 0
        )
    }

    static func main() async {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let catalog = [theme("a"), theme("b"), theme("b", frames: 17), theme("c")]
        let update = EagleDockGalleryVisitOrder.pendingUpdate(
            themes: catalog, orderedIDs: ["gone", "b", "a", "b"]
        )
        expect(update.retainedIDs == ["b", "a", "b"], "Refresh must retain order and repeated existing IDs")
        expect(update.additions == ["c"], "Only genuinely new catalog IDs may be added")
        let empty = EagleDockGalleryVisitOrder.pendingUpdate(themes: [], orderedIDs: ["a", "b"])
        expect(empty.retainedIDs.isEmpty && empty.additions.isEmpty, "Empty catalog must remove all previous IDs")
        let newVisit = EagleDockGalleryVisitOrder.pendingUpdate(themes: catalog, orderedIDs: [])
        expect(newVisit.retainedIDs.isEmpty, "New visit must have no retained IDs")
        expect(Set(newVisit.additions) == ["a", "b", "c"] && newVisit.additions.count == 3,
               "New IDs must be unique; Set iteration order is deliberately unspecified")
        let refreshed = EagleDockGalleryVisitOrder.pendingUpdate(themes: catalog, orderedIDs: ["c", "b", "a", "b"])
        expect(refreshed.retainedIDs == ["c", "b", "a", "b"] && refreshed.additions.isEmpty,
               "Repeated refresh must preserve the established order")

        let identityCatalog = [theme(""), theme("é"), theme("e\u{301}"), theme(" x "), theme("x"), theme("X")]
        let identity = EagleDockGalleryVisitOrder.pendingUpdate(themes: identityCatalog, orderedIDs: ["X", "", "e\u{301}", " x "])
        expect(identity.retainedIDs == ["X", "", "e\u{301}", " x "], "Stored identity spelling/order must be preserved")
        expect(identity.additions == ["x"], "IDs must use native String equality without trimming or lowercasing")

        let four = [theme("s1"), theme("s2"), theme("l1", frames: 17), theme("l2", frames: 2)]
        let interleaved = ["l1", "s1", "l2", "s2"]
        let swapped = EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: interleaved, lastViewedStaticID: "s1", lastViewedLiveID: "l1", themes: four
        )
        expect(swapped == ["l2", "s2", "l1", "s1"], "Swap the first two positions of each category, not adjacent whole-list entries")
        expect(interleaved == ["l1", "s1", "l2", "s2"], "Adjustment must leave the input array intact")
        expect(EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: interleaved, lastViewedStaticID: "missing", lastViewedLiveID: "l2", themes: four
        ) == interleaved, "A later or missing last-viewed ID must not trigger a swap")
        expect(EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: ["s1", "l1"], lastViewedStaticID: "s1", lastViewedLiveID: "l1", themes: four
        ) == ["s1", "l1"], "A single visible item in a category must not move")
        expect(EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: [], lastViewedStaticID: "s1", lastViewedLiveID: "l1", themes: four
        ).isEmpty, "Empty visit order must remain empty")
        expect(EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: ["foreign", "zero", "s1", "s2"], lastViewedStaticID: "s1", lastViewedLiveID: "zero",
            themes: four + [theme("zero", frames: 0)]
        ) == ["foreign", "zero", "s2", "s1"], "Unclassified/missing IDs keep their positions; no package-validity rule is added")

        // Duplicate catalog IDs may belong to both categories. Preserve the
        // public sequential behavior even when the second swap undoes the first.
        let overlap = [theme("a"), theme("a", frames: 17), theme("b"), theme("b", frames: 17)]
        expect(EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: ["a", "b"], lastViewedStaticID: "a", lastViewedLiveID: "b", themes: overlap
        ) == ["a", "b"], "Do not deduplicate catalog objects before determining their categories")
        let asymmetric = [theme("x"), theme("x", frames: 17), theme("s"), theme("l", frames: 17)]
        expect(EagleDockGalleryVisitOrder.avoidingLastViewed(
            order: ["x", "s", "l"], lastViewedStaticID: "x", lastViewedLiveID: "x", themes: asymmetric
        ) == ["s", "l", "x"], "Static adjustment must happen before Live adjustment")

        let large = (0..<428).map { theme("theme-\($0)", frames: $0 < 232 ? 1 : 17) }
        let previous = (0..<428).reversed().map { "theme-\($0)" }
        let reduced = Array(large.dropFirst(17)) + [theme("new-s"), theme("new-l", frames: 17)]
        let largeUpdate = EagleDockGalleryVisitOrder.pendingUpdate(themes: reduced, orderedIDs: previous)
        expect(largeUpdate.retainedIDs == (17..<428).reversed().map { "theme-\($0)" },
               "Large refresh must only remove absent IDs without rearranging the rest")
        expect(Set(largeUpdate.additions) == ["new-s", "new-l"] && largeUpdate.additions.count == 2,
               "Large refresh must add exactly the new identities")

        // Explicit outcomes exercise the new decision rather than duplicating
        // its implementation. Suppliers expose eager/repeated/reordered reads.
        let resolutionCases: [(
            label: String, catalog: [EagleDockGalleryTheme], previous: [String],
            additions: [String], lastStatic: String, lastLive: String,
            expected: [String], readsHistory: Bool
        )] = [
            ("fresh interleaved", four, [], interleaved, "s1", "l1", swapped, true),
            ("retained category opening", four, ["s1"], ["s2", "l1", "l2"],
             "s1", "l1", ["s1", "s2", "l1", "l2"], false),
            ("retained repetitions", four, ["gone", "l1", "s1", "l1"], ["l2", "s2"],
             "s1", "l1", ["l1", "s1", "l1", "l2", "s2"], false),
            ("all previous removed", four, ["gone"], interleaved,
             "s1", "l1", swapped, true),
            ("empty catalog", [], ["gone"], [], "s1", "l1", [], true),
            ("overlapping categories", overlap, [], ["a", "b"], "a", "b", ["a", "b"], true),
            ("chosen addition order", four, [], ["s2", "l2", "l1", "s1"],
             "missing", "missing", ["s2", "l2", "l1", "s1"], true),
            ("established order", four, swapped, [], "s2", "l2", swapped, false),
        ]
        for scenario in resolutionCases {
            var reads: [String] = []
            func staticHistory() -> String { reads.append("static"); return scenario.lastStatic }
            func liveHistory() -> String { reads.append("live"); return scenario.lastLive }
            func catalogSnapshot() -> [EagleDockGalleryTheme] { reads.append("catalog"); return scenario.catalog }
            let pending = EagleDockGalleryVisitOrder.pendingUpdate(
                themes: scenario.catalog, orderedIDs: scenario.previous
            )
            let retainedBefore = pending.retainedIDs
            let additionsBefore = pending.additions
            let resolved = pending.resolvedOrder(
                shuffledAdditions: scenario.additions,
                lastViewedStaticID: staticHistory(),
                lastViewedLiveID: liveHistory(),
                themes: catalogSnapshot()
            )
            expect(resolved == scenario.expected, "Incorrect resolved visit order: \(scenario.label)")
            expect(reads == (scenario.readsHistory ? ["static", "live", "catalog"] : []),
                   "History/catalog reads changed: \(scenario.label)")
            expect(pending.retainedIDs == retainedBefore && pending.additions == additionsBefore,
                   "Resolving must not mutate the pending update: \(scenario.label)")
        }

        let detached = await Task.detached {
            let result = EagleDockGalleryVisitOrder.pendingUpdate(themes: catalog, orderedIDs: ["b", "gone", "a"])
            let adjusted = EagleDockGalleryVisitOrder.avoidingLastViewed(
                order: interleaved, lastViewedStaticID: "s1", lastViewedLiveID: "l1", themes: four
            )
            return (result, adjusted)
        }.value
        expect(detached.0.retainedIDs == ["b", "a"] && detached.0.additions == ["c"] && detached.1 == swapped,
               "Pure update/result values must work outside MainActor")
        let detachedOrder = await Task.detached {
            EagleDockGalleryVisitOrder.pendingUpdate(themes: four, orderedIDs: [])
                .resolvedOrder(shuffledAdditions: interleaved,
                               lastViewedStaticID: "s1", lastViewedLiveID: "l1", themes: four)
        }.value
        expect(detachedOrder == swapped, "Order resolution must work outside MainActor")
        print("PASS: \(checks) focused visit-order assertions: refresh/removal/repetition, category positions/overlap, identity semantics, 428 themes and detached use")
    }
}
