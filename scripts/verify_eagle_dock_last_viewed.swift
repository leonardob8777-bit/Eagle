import Foundation

nonisolated enum LastViewedEvent: Equatable, Sendable {
    case selected
    case visible
    case write(String, [UInt8])
}

@main
private enum EagleDockLastViewedContract {
    nonisolated static func theme(_ id: String, frames: Int) -> EagleDockGalleryTheme {
        let url = URL(string: "https://example.invalid/fixture")!
        return EagleDockGalleryTheme(
            id: id, version: 1, title: "different-title", titleES: "título",
            subtitle: "", subtitleES: "", accent: "#00AAFF", previewURL: url,
            animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
            frameCount: frames, fps: 0, width: 0, height: 0
        )
    }

    nonisolated static func event(_ result: EagleDockGallerySelection.LastViewed?) -> LastViewedEvent? {
        switch result {
        case .still(let id): return .write("static", Array(id.utf8))
        case .live(let id): return .write("live", Array(id.utf8))
        case nil: return nil
        }
    }

    static func main() async {
        MainActor.preconditionIsolated()
        let ids = ["", "same", " Same ", "theme/live", "é", "e\u{301}", "🦅"]
        let frames = [Int.min, -1, 0, 1, 2, 17, Int.max]
        let themes = frames.flatMap { count in ids.map { theme($0, frames: count) } }
        let inputs: [EagleDockGalleryTheme?] = [nil] + themes.map(Optional.some)
        var pureCases = 0
        for input in inputs {
            let expected = input.map { LastViewedEvent.write($0.frameCount > 1 ? "live" : "static", Array($0.id.utf8)) }
            precondition(event(EagleDockGallerySelection.lastViewed(input)) == expected,
                         "Last-viewed slot, exact ID bytes or nil handling changed")
            pureCases += 1
        }
        let detachedCases = await Task.detached {
            var count = 0
            for input in inputs {
                let expected = input.map { LastViewedEvent.write($0.frameCount > 1 ? "live" : "static", Array($0.id.utf8)) }
                precondition(event(EagleDockGallerySelection.lastViewed(input)) == expected,
                             "Detached last-viewed decision differs")
                count += 1
            }
            return count
        }.value

        let catalogs = [[], [theme("only", frames: 1)], [theme("only", frames: 17)],
                        [theme("dup", frames: 1), theme("dup", frames: 17)],
                        [theme("dup", frames: 17), theme("dup", frames: 1)],
                        themes, Array(themes.reversed())]
        let selectedIDs = ids + ["missing", "only", "dup"]
        let histories = [("", ""), ("static-prior", "live-prior"), ("é", "e\u{301}"), ("same", "same")]
        var screenCases = 0
        var nilCases = 0
        var staticWrites = 0
        var liveWrites = 0
        for catalog in catalogs {
            for filter in EagleDockGalleryMediaFilter.allCases {
                for favorites in [Set<String>(), Set(catalog.map(\.id))] {
                    for id in selectedIDs {
                        for (priorStatic, priorLive) in histories {
                            let reference = PublicLastViewedFixture()
                            let owned = OwnedLastViewedFixture()
                            reference.remoteGallery.themes = catalog
                            owned.remoteGallery.themes = catalog
                            reference.mediaFilter = filter
                            owned.mediaFilter = filter
                            reference.favoriteIDs = favorites
                            owned.favoriteIDs = favorites
                            reference.selectedRemoteID = id
                            owned.selectedRemoteID = id
                            reference.shuffledRemoteIDs = Array(catalog.map(\.id).reversed())
                            owned.shuffledRemoteIDs = reference.shuffledRemoteIDs
                            reference.lastViewedStaticID = priorStatic
                            owned.lastViewedStaticID = priorStatic
                            reference.lastViewedLiveID = priorLive
                            owned.lastViewedLiveID = priorLive
                            // Derive the visible theme independently from the existing
                            // displayed getter, then clear instrumentation before each call.
                            let displayed = reference.selectedRemoteTheme
                            let expectedWrite = displayed.map {
                                LastViewedEvent.write($0.frameCount > 1 ? "live" : "static", Array($0.id.utf8))
                            }
                            for _ in 0..<3 {
                                reference.events = []
                                owned.events = []
                                reference.rememberViewedTheme()
                                owned.rememberViewedTheme()
                                let expectedEvents: [LastViewedEvent] = [.selected, .visible] + (expectedWrite.map { [$0] } ?? [])
                                precondition(owned.events == reference.events && owned.events == expectedEvents,
                                             "Reads/write order, slot or repeated assignment changed")
                                precondition(Array(owned.lastViewedStaticID.utf8) == Array(reference.lastViewedStaticID.utf8) &&
                                             Array(owned.lastViewedLiveID.utf8) == Array(reference.lastViewedLiveID.utf8),
                                             "Preference output bytes differ from the public helper")
                                let expectedStatic = displayed.flatMap { $0.frameCount > 1 ? nil : $0.id } ?? priorStatic
                                let expectedLive = displayed.flatMap { $0.frameCount > 1 ? $0.id : nil } ?? priorLive
                                precondition(Array(owned.lastViewedStaticID.utf8) == Array(expectedStatic.utf8) &&
                                             Array(owned.lastViewedLiveID.utf8) == Array(expectedLive.utf8),
                                             "Unrelated slot changed or stored ID was normalized")
                                precondition(Array(owned.selectedRemoteID.utf8) == Array(id.utf8) &&
                                             owned.mediaFilter == filter && owned.favoriteIDs == favorites &&
                                             owned.shuffledRemoteIDs == reference.shuffledRemoteIDs &&
                                             owned.remoteGallery.themes == catalog,
                                             "Remembering changed selection/category/catalog/order/favorites")
                                if let displayed {
                                    if displayed.frameCount > 1 { liveWrites += 1 } else { staticWrites += 1 }
                                } else { nilCases += 1 }
                                screenCases += 1
                            }
                        }
                    }
                }
            }
        }
        precondition(nilCases > 0 && staticWrites > 0 && liveWrites > 0)
        print("PASS: \(pureCases) pure + \(detachedCases) detached last-viewed decisions; \(screenCases) screen calls (\(nilCases) nil, \(staticWrites) Static, \(liveWrites) Live); exact bytes, Saves, invalid counts, duplicate/fallback IDs, untouched slot and repeated-write parity")
    }
}
