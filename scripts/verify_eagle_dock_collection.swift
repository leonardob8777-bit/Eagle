import Foundation

@main
private enum EagleDockCollectionContract {
    static func theme(_ id: String, frames: Int, token: Int) -> EagleDockGalleryTheme {
        let url = URL(string: "https://example.invalid/fixture/\(token)")!
        return EagleDockGalleryTheme(
            id: id, version: token, title: "title-\(token)", titleES: "título-\(token)",
            subtitle: "subtitle-\(token)", subtitleES: "subtítulo-\(token)", accent: "color-\(token)",
            previewURL: url, animatedPreviewURL: token % 2 == 0 ? url : nil, packageURL: url,
            sha256: "hash-\(token)", byteCount: token % 4 == 0 ? 0 : 1024,
            frameCount: frames, fps: frames == 1 ? 1 : 6, width: 1146, height: 318
        )
    }

    static func main() async {
        MainActor.preconditionIsolated()
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let staticTheme = theme("s", frames: 1, token: 1)
        let liveTheme = theme("l", frames: 17, token: 2)
        let firstStatic = theme("dup", frames: 1, token: 3)
        let secondLive = theme("dup", frames: 17, token: 4)
        let unsupported = theme("unsupported", frames: 2, token: 8)
        let identities = [theme("", frames: 1, token: 5), theme("é", frames: 1, token: 6),
                          theme("e\u{301}", frames: 17, token: 7), theme(" s ", frames: 1, token: 9),
                          theme("S", frames: 17, token: 10), theme("🦅", frames: 6, token: 11)]
        let mixed = [staticTheme, liveTheme, firstStatic, secondLive, unsupported] + identities
        let large = (0..<428).map { theme("large-\($0)", frames: $0 % 2 == 0 ? 1 : 17, token: $0 + 100) }
        let catalogs = [[], [staticTheme], [liveTheme], [firstStatic, secondLive], [secondLive, firstStatic],
                        mixed, Array(mixed.reversed()), identities, large]
        let alphabet = ["s", "l", "dup", "missing", "", "é"]
        var orders: [[String]] = [[]]
        for id in alphabet { orders.append([id]) }
        for first in alphabet {
            for second in alphabet { orders.append([first, second]) }
        }
        orders.append(contentsOf: [
            ["dup", "missing", "dup", "s", "l"], ["S", " s ", "s", "🦅", "unsupported"],
            ["é", "e\u{301}", "é", ""], mixed.map(\.id), Array(mixed.map(\.id).reversed()),
            large.map(\.id), Array(large.map(\.id).reversed()) + ["large-0", "missing"],
        ])
        let favorites: [Set<String>] = [[], ["s"], ["dup"], ["", "é"], ["l", "DUP"],
                                        Set(mixed.map(\.id) + large.map(\.id))]
        let actualFilters = EagleDockGalleryMediaFilter.allCases
        let publicFilters = BaselineDockGalleryMediaFilter.allCases
        expect(actualFilters.map(\.rawValue) == publicFilters.map(\.rawValue), "Fixture filter identity/order mismatch")
        var detachedCases: [([EagleDockGalleryTheme], [String], EagleDockGalleryMediaFilter, Set<String>, [EagleDockGalleryTheme])] = []
        for catalog in catalogs {
            for order in orders {
                for saved in favorites {
                    for (actualFilter, publicFilter) in zip(actualFilters, publicFilters) {
                        let expected = BaselineDockGalleryCollection.visible(
                            themes: catalog, orderedIDs: order, filter: publicFilter, favorites: saved
                        )
                        let actual = EagleDockGalleryCollection.visible(
                            themes: catalog, orderedIDs: order, filter: actualFilter, favorites: saved
                        )
                        expect(actual == expected, "Complete theme objects/order/repetitions differ from public projection")
                        detachedCases.append((catalog, order, actualFilter, saved, expected))
                    }
                }
            }
        }

        // Filtering before deduplication would incorrectly select the second
        // qualifying object. Check full objects with deliberately different fields.
        expect(EagleDockGalleryCollection.visible(themes: [firstStatic, secondLive], orderedIDs: ["dup"],
                                                  filter: .live, favorites: []).isEmpty, "Live filtering preceded first-per-ID selection")
        expect(EagleDockGalleryCollection.visible(themes: [firstStatic, secondLive], orderedIDs: ["dup"],
                                                  filter: .still, favorites: []) == [firstStatic], "Static first object changed")
        expect(EagleDockGalleryCollection.visible(themes: [secondLive, firstStatic], orderedIDs: ["dup"],
                                                  filter: .still, favorites: []).isEmpty, "Static filtering preceded first-per-ID selection")
        expect(EagleDockGalleryCollection.visible(themes: [secondLive, firstStatic], orderedIDs: ["dup"],
                                                  filter: .live, favorites: []) == [secondLive], "Live first object changed")
        expect(EagleDockGalleryCollection.visible(themes: [firstStatic, secondLive], orderedIDs: ["dup", "missing", "dup"],
                                                  filter: .favorites, favorites: ["dup"]) == [firstStatic, firstStatic],
               "Ordered-ID repetitions or omission of missing IDs changed")
        expect(EagleDockGalleryCollection.visible(themes: mixed, orderedIDs: [], filter: .favorites,
                                                  favorites: Set(mixed.map(\.id))).isEmpty, "Unordered catalog themes were appended")
        expect(!unsupported.isSupportedPackage, "Unsupported fixture accidentally became supported")
        expect(EagleDockGalleryCollection.visible(themes: [unsupported], orderedIDs: ["unsupported"],
                                                  filter: .live, favorites: []) == [unsupported], "Collection added package validation")

        let frameCounts = [Int.min, -1, 0, 1, 2, 6, 16, 17, 18, Int.max]
        for count in frameCounts {
            let value = theme("boundary", frames: count, token: 20)
            for (actualFilter, publicFilter) in zip(actualFilters, publicFilters) {
                let expected = BaselineDockGalleryCollection.visible(themes: [value], orderedIDs: ["boundary", "boundary"],
                                                                     filter: publicFilter, favorites: ["boundary"])
                expect(EagleDockGalleryCollection.visible(themes: [value], orderedIDs: ["boundary", "boundary"],
                                                         filter: actualFilter, favorites: ["boundary"]) == expected,
                       "Frame-count boundary or Favorites classification changed")
            }
        }
        let catalogSnapshot = mixed
        let repeatOrder = mixed.map(\.id)
        let orderSnapshot = repeatOrder
        let repeated = EagleDockGalleryCollection.visible(themes: mixed, orderedIDs: repeatOrder, filter: .still, favorites: [])
        expect(!repeated.isEmpty, "Repeated-call fixture must exercise a nonempty projection")
        expect(EagleDockGalleryCollection.visible(themes: mixed, orderedIDs: repeatOrder, filter: .still, favorites: []) == repeated,
               "Repeated invocation gained mutable state")
        expect(mixed == catalogSnapshot && repeatOrder == orderSnapshot, "Collection modified caller inputs")

        let immutableCases = detachedCases
        let detachedMatches = await Task.detached {
            immutableCases.allSatisfy { catalog, order, filter, saved, expected in
                EagleDockGalleryCollection.visible(themes: catalog, orderedIDs: order, filter: filter, favorites: saved) == expected
            }
        }.value
        expect(detachedMatches, "Nonisolated projection changed outside MainActor")
        print("PASS: \(checks) actual/public collection checks across \(catalogs.count) catalogs, \(orders.count) ID orders, \(favorites.count) favorite sets and 3 filters; complete metadata, first-before-filter, repetitions/omissions/Unicode/empty and 428-theme catalog retained; \(immutableCases.count) detached projections match")
    }
}
