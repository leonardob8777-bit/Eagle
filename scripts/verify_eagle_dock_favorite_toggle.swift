import Foundation

nonisolated enum FavoriteToggleEvent: Equatable, Sendable {
    case read([UInt8])
    case write([UInt8])
    case synchronize([UInt8])
    case feedback
}

@main
private enum EagleDockFavoriteToggleContract {
    nonisolated static func bytes(_ ids: Set<String>) -> [[UInt8]] {
        ids.sorted().map { Array($0.utf8) }
    }

    // Independent membership formulation, deliberately not the production
    // insert().inserted branch. Equality retains Swift's Unicode semantics.
    nonisolated static func reference(_ original: Set<String>, id: String) -> Set<String> {
        var result = original
        if original.contains(id) { result.remove(id) } else { result.insert(id) }
        return result
    }

    static func theme(_ id: String) -> EagleDockGalleryTheme {
        let url = URL(string: "https://example.invalid/favorite")!
        return EagleDockGalleryTheme(
            id: id, version: 1, title: "not-the-id", titleES: "título",
            subtitle: "", subtitleES: "", accent: "#00AAFF", previewURL: url,
            animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
            frameCount: 0, fps: 0, width: 0, height: 0
        )
    }

    static func main() async throws {
        MainActor.preconditionIsolated()
        let ids = ["", "a", "A", " a ", "é", "e\u{301}", "É", "🦅", "主题", "slash/",
                   "quote\"", "backslash\\", "line\n", "null\0"]
        let powersetIDs = ["", "a", "A", " a ", "é", "🦅", "slash/", "quote\""]
        var groups: [Set<String>] = [
            [], ["e\u{301}"], ["é"], ["a", " a ", "A"], Set(ids),
            Set((0..<512).map { "favorite-\($0)" }), [String(repeating: "🦅x", count: 8192)],
        ]
        for mask in 0..<(1 << powersetIDs.count) {
            groups.append(Set(powersetIDs.enumerated().compactMap { index, id in
                mask & (1 << index) == 0 ? nil : id
            }))
        }
        var cases = 0
        for original in groups {
            let originalBytes = bytes(original)
            for id in ids {
                let expected = reference(original, id: id)
                let actual = EagleDockGalleryFavorites.toggling(original, id: id)
                precondition(bytes(actual) == bytes(expected), "Exact membership/identity bytes changed")
                precondition(actual.contains(id) != original.contains(id), "Selected membership must flip")
                precondition(actual.count == original.count + (original.contains(id) ? -1 : 1), "Unrelated IDs changed")
                precondition(bytes(original) == originalBytes, "Input value was mutated")
                let repeated = EagleDockGalleryFavorites.toggling(actual, id: id)
                precondition(bytes(repeated) == bytes(reference(expected, id: id)), "Repeated toggle differs")
                precondition(repeated == original, "Two toggles must restore semantic membership")
                // Byte equality with original is intentionally not required here:
                // removing decomposed é and adding composed é keeps public behavior.
                cases += 1
            }
        }
        let detachedGroups = groups
        let detachedCases = await Task.detached {
            var count = 0
            for original in detachedGroups {
                for id in ids {
                    precondition(bytes(EagleDockGalleryFavorites.toggling(original, id: id)) ==
                                 bytes(reference(original, id: id)), "Detached membership differs")
                    count += 1
                }
            }
            return count
        }.value

        var storedInputs = ["", " ", "[]", " [ ] \n", "null", "true", "1", "{}", "[null]", "[1]",
                            "[\"a\",null]", "[\"a\"]garbage", "[", "[\"a\",]",
                            "[\"a\",\"a\"]", "[\"e\\u0301\",\"é\"]",
                            #"["quote\"","backslash\\","line\n","null\u0000"]"#]
        for group in groups {
            storedInputs.append(String(data: try JSONEncoder().encode(group.sorted()), encoding: .utf8)!)
        }
        var screenCalls = 0
        for stored in storedInputs {
            for id in ids {
                let baseline = PublicFavoriteToggleFixture()
                let owned = OwnedFavoriteToggleFixture()
                baseline.favoriteIDsJSON = stored
                owned.favoriteIDsJSON = stored
                let theme = theme(id)
                for _ in 0..<3 {
                    let before = Array(owned.favoriteIDsJSON.utf8)
                    baseline.events = []
                    owned.events = []
                    baseline.toggleFavorite(theme)
                    owned.toggleFavorite(theme)
                    let after = Array(baseline.favoriteIDsJSON.utf8)
                    let expectedEvents: [FavoriteToggleEvent] = [
                        .read(before), .write(after), .synchronize(after), .feedback,
                    ]
                    precondition(owned.events == baseline.events && owned.events == expectedEvents,
                                 "Read/write/synchronization/feedback order or counts changed")
                    precondition(Array(owned.favoriteIDsJSON.utf8) == after, "Exact persisted JSON differs")
                    screenCalls += 1
                }
            }
        }
        print("PASS: \(cases) membership + \(detachedCases) detached cases; \(screenCalls) actual/public helper calls over \(storedInputs.count) stored inputs, \(ids.count) IDs and repeated toggles; exact bytes, malformed JSON, input isolation and write/sync/feedback parity")
        print("NOTE: normal String sets do not exercise actual encoder failure; its early-return guard is source-verified, not fault-injected")
    }
}
