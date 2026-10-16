import Foundation

@main
private enum EagleDockSelectionContract {
    static func theme(_ id: String, token: Int) -> EagleDockGalleryTheme {
        let url = URL(string: "https://example.invalid/fixture/\(token)")!
        return EagleDockGalleryTheme(
            id: id, version: token, title: "title-\(token)", titleES: "título-\(token)",
            subtitle: "subtitle-\(token)", subtitleES: "subtítulo-\(token)", accent: "color-\(token)",
            previewURL: url, animatedPreviewURL: token % 2 == 0 ? url : nil, packageURL: url,
            sha256: "hash-\(token)", byteCount: token % 4 == 0 ? 0 : 1024,
            frameCount: token % 2 == 0 ? 17 : 1, fps: token % 2 == 0 ? 6 : 1, width: 1146, height: 318
        )
    }

    static func main() async {
        MainActor.preconditionIsolated()
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let first = theme("dup", token: 1)
        let second = theme("dup", token: 2)
        let identities = [theme("", token: 3), theme("é", token: 4), theme("e\u{301}", token: 5),
                          theme(" x ", token: 6), theme("x", token: 7), theme("X", token: 8), theme("🦅", token: 9)]
        let mixed = [first, second] + identities
        let large = (0..<428).map { theme("large-\($0)", token: $0 + 100) }
        let catalogs = [[], [first], [second], [first, second], [second, first],
                        mixed, Array(mixed.reversed()), identities, large]
        let selectedIDs = ["missing", "dup", "", "é", "e\u{301}", " x ", "x", "X", "🦅", "DUP",
                           "large-0", "large-214", "large-427", "large-428"]
        var detachedSelections: [([EagleDockGalleryTheme], String, EagleDockGalleryTheme?, Int)] = []
        for catalog in catalogs {
            for id in selectedIDs {
                let expectedTheme = BaselineDockGallerySelection.selected(in: catalog, selectedID: id)
                let expectedIndex = BaselineDockGallerySelection.currentIndex(in: catalog, selectedID: id)
                expect(EagleDockGallerySelection.selected(in: catalog, selectedID: id) == expectedTheme,
                       "First match/fallback complete metadata changed")
                expect(EagleDockGallerySelection.currentIndex(in: catalog, selectedID: id) == expectedIndex,
                       "First current index/default changed")
                detachedSelections.append((catalog, id, expectedTheme, expectedIndex))

                let baseline = BaselineSelectionScreenFixture()
                let owned = OwnedSelectionScreenFixture()
                baseline.themes = catalog
                owned.themes = catalog
                baseline.selectedRemoteID = id
                owned.selectedRemoteID = id
                expect(owned.selectedRemoteTheme == baseline.selectedRemoteTheme,
                       "Actual selected getter differs from public value result")
                let publicReads = catalog.contains(where: { $0.id == id }) ? 1 : 2
                expect(baseline.snapshotReads == publicReads && owned.snapshotReads == 1,
                       "Expected documented value-snapshot evaluation count")
                baseline.snapshotReads = 0
                owned.snapshotReads = 0
                let publicPosition = baseline.remotePositionText.components(separatedBy: " / ")
                let paddedPosition = publicPosition.map { String(format: "%02d", Int($0)!) }.joined(separator: " / ")
                expect(owned.remotePositionText == paddedPosition,
                       "Position values or accepted two-digit formatting changed")
                expect(owned.snapshotReads == 1 && baseline.snapshotReads == 1,
                       "Position getter changed snapshot evaluation count")
                if catalog.isEmpty {
                    expect(owned.remotePositionText == "01 / 00", "Public empty position values changed")
                }
            }
        }
        expect(first != second, "Duplicate fixtures must differ in full metadata")
        expect(EagleDockGallerySelection.selected(in: [first, second], selectedID: "dup") == first,
               "Duplicate selection must keep first complete object")
        expect(EagleDockGallerySelection.currentIndex(in: [second, first], selectedID: "dup") == 0,
               "Duplicate current index must be the first occurrence")
        expect(EagleDockGallerySelection.selected(in: [second, first], selectedID: "missing") == second,
               "Missing identity fallback must be first, not a normalized/matching title")

        var detachedIndices: [(Int, Int, Int, Int)] = []
        for count in [1, 2, 3, 9, 17, 428] {
            for current in 0..<count {
                // Bounded scalars only. Negative remainders are compared, never
                // used as array indices. No zero divisor/overflow is executed.
                for step in [-2 * count - 1, -count - 1, -count, -1, 0, 1, count, count + 1, 2 * count + 1] {
                    let expected = BaselineDockGallerySelection.nextIndex(current: current, step: step, count: count)
                    expect(EagleDockGallerySelection.nextIndex(current: current, step: step, count: count) == expected,
                           "Exact public bounded remainder arithmetic changed")
                    detachedIndices.append((current, step, count, expected))
                }
            }
        }
        expect(EagleDockGallerySelection.nextIndex(current: 0, step: -4, count: 3) == -1,
               "Do not turn the original arithmetic into a positive-modulo API")
        expect(EagleDockGallerySelection.nextIndex(current: 0, step: -1, count: 3) == 2,
               "Previous arrow should wrap at the first item")
        expect(EagleDockGallerySelection.nextIndex(current: 2, step: 1, count: 3) == 0,
               "Next arrow should wrap at the last item")

        var screenCases = 0
        var detachedSteps: [(EagleDockGallerySession, [EagleDockGalleryTheme], Int, String)] = []
        for catalog in catalogs {
            for id in selectedIDs {
                for step in [-1, 1] {
                    for lock in 0..<6 {
                        let baseline = BaselineSelectionScreenFixture()
                        let owned = OwnedSelectionScreenFixture()
                        baseline.themes = catalog
                        owned.themes = catalog
                        baseline.selectedRemoteID = id
                        owned.selectedRemoteID = id
                        baseline.readyRemotePreviewID = "ready"
                        owned.readyRemotePreviewID = "ready"
                        baseline.isApplying = lock == 1 || lock == 3 || lock == 5
                        owned.isApplying = baseline.isApplying
                        baseline.remoteGallery.downloadingID = lock >= 4 ? "" : (lock == 2 || lock == 3 ? "download" : nil)
                        owned.remoteGallery.downloadingID = baseline.remoteGallery.downloadingID
                        owned.session.mediaFilter = .favorites
                        owned.session.rememberedSelections.remember(id: "", for: .still)
                        owned.session.rememberedSelections.remember(id: "e\u{301}", for: .live)
                        owned.session.shuffledRemoteIDs = ["b", "a", "b"]
                        owned.session.visitStarted = true
                        let before = owned.session
                        baseline.events = []
                        owned.events = []
                        baseline.stepRemote(step)
                        owned.stepRemote(step)
                        expect(Array(owned.selectedRemoteID.utf8) == Array(baseline.selectedRemoteID.utf8) &&
                               Array(owned.readyRemotePreviewID.utf8) == Array(baseline.readyRemotePreviewID.utf8) &&
                               owned.events == baseline.events && owned.snapshotReads == baseline.snapshotReads,
                               "Actual guarded step differs in state/snapshot/effect sequence")
                        expect(owned.listReadStates == baseline.listReadStates && owned.rememberStates == baseline.rememberStates,
                               "State at list-read and persistence boundaries differs")
                        expect(owned.session.mediaFilter == .favorites && owned.session.visitStarted &&
                               owned.session.shuffledRemoteIDs == ["b", "a", "b"] &&
                               owned.session.rememberedSelections.restoredID(for: .still) == .some("") &&
                               owned.session.rememberedSelections.restoredID(for: .live).map { Array($0.utf8) } == Array("e\u{301}".utf8) &&
                               owned.session.rememberedSelections.restoredID(for: .favorites) == nil,
                               "Navigation must not modify category, memory, visit order or flag")
                        if lock > 0 || catalog.count < 2 {
                            expect(owned.selectedRemoteID == id && owned.readyRemotePreviewID == "ready" && owned.events.isEmpty,
                                   "Locked/empty/single-item step must leave state/effects untouched")
                            expect(owned.snapshotReads == (lock > 0 ? 0 : 1), "Operation guard moved after snapshot")
                        } else {
                            let result = owned.selectedRemoteID
                            expect(owned.events == ["remember::" + result, "haptic"] &&
                                   owned.rememberStates == [[Array(result.utf8), []]] &&
                                   owned.listReadStates == [[Array(id.utf8), Array("ready".utf8)]],
                                   "List snapshot must precede mutation; persistence sees cleared preview/new ID before feedback")
                            detachedSteps.append((before, catalog, step, baseline.selectedRemoteID))
                        }
                        expect(before.selectedRemoteID == id && before.readyRemotePreviewID == "ready",
                               "Navigation must leave a prior session copy untouched")
                        screenCases += 1
                    }
                }
            }
        }
        let empty = [EagleDockGalleryTheme]()
        expect(EagleDockGallerySelection.selected(in: empty, selectedID: "") == nil &&
               EagleDockGallerySelection.currentIndex(in: empty, selectedID: "") == 0,
               "Empty nil/index-zero contract changed")
        let snapshot = mixed
        let repeated = EagleDockGallerySelection.selected(in: mixed, selectedID: "dup")
        expect(EagleDockGallerySelection.selected(in: mixed, selectedID: "dup") == repeated && mixed == snapshot,
               "Pure repeated selection gained mutation or shared state")

        let immutableSelections = detachedSelections
        let immutableIndices = detachedIndices
        let detachedMatches = await Task.detached {
            immutableSelections.allSatisfy { themes, id, selected, index in
                EagleDockGallerySelection.selected(in: themes, selectedID: id) == selected &&
                    EagleDockGallerySelection.currentIndex(in: themes, selectedID: id) == index
            } && immutableIndices.allSatisfy { current, step, count, expected in
                EagleDockGallerySelection.nextIndex(current: current, step: step, count: count) == expected
            }
        }.value
        expect(detachedMatches, "Nonisolated pure selection/index differs outside MainActor")
        let immutableSteps = detachedSteps
        let detachedStepMatches = await Task.detached {
            immutableSteps.allSatisfy { original, themes, step, expectedID in
                var changed = original
                changed.step(step, in: themes)
                return Array(changed.selectedRemoteID.utf8) == Array(expectedID.utf8) &&
                    changed.readyRemotePreviewID.isEmpty && original.readyRemotePreviewID == "ready" &&
                    changed.mediaFilter == original.mediaFilter && changed.visitStarted == original.visitStarted &&
                    changed.shuffledRemoteIDs == original.shuffledRemoteIDs &&
                    EagleDockGalleryMediaFilter.allCases.allSatisfy {
                        changed.rememberedSelections.restoredID(for: $0).map { Array($0.utf8) } ==
                        original.rememberedSelections.restoredID(for: $0).map { Array($0.utf8) }
                    }
            }
        }.value
        expect(detachedStepMatches, "Owned navigation differs outside MainActor or mutates unrelated session values")
        print("PASS: \(checks) actual/public selection checks; \(catalogs.count) catalogs/\(selectedIDs.count) IDs, \(immutableIndices.count) bounded arithmetic cases, \(screenCases) inert guarded screen cases; complete duplicate metadata/Unicode/empty/428 themes and documented snapshot counts; \(immutableSelections.count + immutableIndices.count) detached cases match")
        print("PASS: \(immutableSteps.count) detached session navigation cases; exact UTF-8 IDs, preview reset, preserved category/memory/order/flag and copy isolation")
    }
}
