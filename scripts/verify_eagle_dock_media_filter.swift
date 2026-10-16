import Foundation

@main
private enum EagleDockMediaFilterContract {
    static func main() async {
        MainActor.preconditionIsolated()
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let owned = EagleDockGalleryMediaFilter.allCases
        let baseline = BaselineDockGalleryMediaFilter.allCases
        expect(owned.map(\.rawValue) == baseline.map(\.rawValue), "Public case order or raw IDs changed")
        expect(owned.map(\.rawValue) == ["Static", "Live", "Favorites"], "Stored filter identities changed")
        expect(owned.map(\.title) == baseline.map(\.title), "Displayed titles differ from public")
        expect(owned.map(\.title) == ["Static", "Live", "Saves"], "Saves display title changed")
        expect(owned.map(\.icon) == baseline.map(\.icon), "Icons differ from public")
        expect(owned.map(\.icon) == ["sparkles", "play.circle", "heart"], "Original icons changed")
        expect(Set(owned).count == 3, "Filters no longer provide distinct Hashable identities")

        for raw in ["Static", "Live", "Favorites", "Saves", "All", "", "static", "live", "favorites",
                    " Static", "Static ", "LIVE", "Favorites\n", "🦅"] {
            expect(EagleDockGalleryMediaFilter(rawValue: raw)?.rawValue ==
                   BaselineDockGalleryMediaFilter(rawValue: raw)?.rawValue, "Raw-value lookup/invalid ID behavior changed")
        }
        var actualSelections: [EagleDockGalleryMediaFilter: String] = [:]
        var publicSelections: [BaselineDockGalleryMediaFilter: String] = [:]
        for (actual, original) in zip(owned, baseline) {
            actualSelections[actual] = actual.rawValue
            publicSelections[original] = original.rawValue
        }
        for (actual, original) in zip(owned, baseline) {
            expect(actualSelections[actual] == publicSelections[original], "Remembered selection lookup changed")
            actualSelections[EagleDockGalleryMediaFilter(rawValue: actual.rawValue)!] = "updated"
            publicSelections[BaselineDockGalleryMediaFilter(rawValue: original.rawValue)!] = "updated"
            expect(actualSelections[actual] == publicSelections[original], "Raw-value key replacement changed")
            expect(actualSelections.count == publicSelections.count && actualSelections.count == 3, "Dictionary identities changed")
        }

        let frameCounts = [Int.min, -1, 0, 1, 2, 6, 16, 17, 18, Int.max]
        let identifiers = ["", "same", "SAME", " same ", "🦅", "theme/1", "é", "e\u{301}"]
        let favorites: [Set<String>] = [[], ["same"], ["SAME"], [" same "], ["🦅"], ["theme/1"], ["é"], Set(identifiers)]
        let fields: [(fps: Double?, width: Int, height: Int, bytes: Int)] = [
            (nil, 1146, 318, 1024),
            (nil, 1146, 318, 0),
            (.nan, Int.max, Int.min, Int.max),
            (.infinity, 0, -1, -1),
            (-1, 1, 1, 30 * 1024 * 1024 + 1),
        ]
        let url = URL(string: "https://example.invalid/fixture")!
        var detachedCases: [(EagleDockGalleryMediaFilter, EagleDockGalleryTheme, Set<String>, Bool)] = []
        var sawSupported = false
        var sawUnsupported = false
        for count in frameCounts {
            for id in identifiers {
                for field in fields {
                    let theme = EagleDockGalleryTheme(
                        id: id, version: 1, title: "Unrelated title", titleES: "Título",
                        subtitle: "Unrelated subtitle", subtitleES: "Subtítulo", accent: "invalid",
                        previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "invalid",
                        byteCount: field.bytes, frameCount: count, fps: field.fps ?? (count == 1 ? 1 : 6),
                        width: field.width, height: field.height
                    )
                    sawSupported = sawSupported || theme.isSupportedPackage
                    sawUnsupported = sawUnsupported || !theme.isSupportedPackage
                    for saved in favorites {
                        for (actual, original) in zip(owned, baseline) {
                            let expected = original.includes(theme, favorites: saved)
                            expect(actual.includes(theme, favorites: saved) == expected,
                                   "Public classification changed with frame count, ID, favorites or unrelated package fields")
                            detachedCases.append((actual, theme, saved, expected))
                        }
                    }
                }
            }
        }
        expect(sawSupported && sawUnsupported, "Fixtures must cover supported and unsupported packages")
        let immutableCases = detachedCases
        let detachedMatches = await Task.detached {
            immutableCases.allSatisfy { filter, theme, saved, expected in
                filter.includes(theme, favorites: saved) == expected
            }
        }.value
        expect(detachedMatches, "Nonisolated Sendable filter changed when invoked outside MainActor")
        print("PASS: \(checks) actual/public filter checks across \(frameCounts.count) frame-count boundaries, \(identifiers.count) IDs, \(favorites.count) favorite sets and \(fields.count) unrelated package variants; raw IDs/labels/icons/dictionary behavior retained; \(immutableCases.count) detached classifications match")
    }
}
