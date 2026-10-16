import Foundation

struct InteractionSnapshot: Equatable {
    let filter: String
    let selected: [UInt8]
    let preview: [UInt8]
    let order: [[UInt8]]
    let started: Bool
    let memory: [[UInt8]?]
    init(_ state: EagleDockGallerySession) {
        filter = state.mediaFilter.rawValue
        selected = Array(state.selectedRemoteID.utf8)
        preview = Array(state.readyRemotePreviewID.utf8)
        order = state.shuffledRemoteIDs.map { Array($0.utf8) }
        started = state.visitStarted
        memory = EagleDockGalleryMediaFilter.allCases.map { state.rememberedSelections.restoredID(for: $0).map { Array($0.utf8) } }
    }
}

struct InteractionEvent: Equatable {
    let name: String
    let state: InteractionSnapshot
    let favoritesJSON: [UInt8]
}

@MainActor
class InteractionStorage {
    typealias MediaFilter = EagleDockGalleryMediaFilter
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    struct DisplayedTheme { let id: String }
    struct Download {
        unowned let owner: InteractionStorage
        var downloadingID: String? { owner.record("download"); return owner.downloadID }
    }
    var stored = EagleDockGallerySession()
    var applying = false
    var downloadID: String?
    var displayedID: String? = "shown"
    var themes: [EagleDockGalleryTheme] = []
    var storedFavoritesJSON = "[]"
    var mutateOnRead = false
    var mutateEffect = false
    var events: [InteractionEvent] = []
    @MainActor init() {}

    func record(_ name: String) {
        events.append(InteractionEvent(name: name, state: InteractionSnapshot(stored), favoritesJSON: Array(storedFavoritesJSON.utf8)))
    }
    var favoriteIDs: Set<String> {
        record("favorites-read")
        return EagleDockGalleryFavorites.decode(storedFavoritesJSON)
    }
    var favoriteIDsJSON: String {
        get { storedFavoritesJSON }
        set { storedFavoritesJSON = newValue; record("favorites-write") }
    }
    var session: EagleDockGallerySession {
        get { record("session-read"); return stored }
        set { stored = newValue; record("session-write") }
    }
    var mediaFilter: MediaFilter { session.mediaFilter }
    var isApplying: Bool { record("applying"); return applying }
    var remoteGallery: Download { Download(owner: self) }
    func mutateRead() {
        if mutateOnRead {
            stored.visitStarted = false
            stored.rememberedSelections.remember(id: "read-mutation", for: .favorites)
            record("read-mutation")
        }
    }
    var selectedRemoteTheme: DisplayedTheme? {
        record("selected")
        mutateRead()
        return displayedID.map { DisplayedTheme(id: $0) }
    }
    var visibleRemoteThemes: [EagleDockGalleryTheme] {
        record("visible")
        mutateRead()
        return themes
    }
    func synchronizeRemoteSelection() {
        record("sync")
        if mutateEffect { stored.readyRemotePreviewID = "synchronized"; record("effect-mutation") }
    }
    func rememberViewedTheme() {
        record("remember")
        if mutateEffect { stored.readyRemotePreviewID = "remembered"; record("effect-mutation") }
    }
    func feedback(_ kind: String) { record("feedback-" + kind) }
    func category(_ filter: MediaFilter) { preconditionFailure("Fixture override required") }
    func navigate(_ step: Int) { preconditionFailure("Fixture override required") }
    func favorite(_ theme: RemoteDockGalleryTheme) { preconditionFailure("Fixture override required") }
    func begin() { preconditionFailure("Fixture override required") }
}

@main
private enum InteractionChecks {
    enum Action { case category(EagleDockGalleryMediaFilter), step(Int) }
    struct Scenario {
        let label: String
        let action: Action
        var applying = false
        var download: String? = nil
        var displayed: String? = "shown"
        var selected = "s1"
        var themes: [EagleDockGalleryTheme] = []
        var mutateRead = false
        var mutateEffect = false
        let expectedEvents: [String]
        let expectedSelected: String
        let expectedFilter: EagleDockGalleryMediaFilter
        let writes: Int
    }
    static func theme(_ id: String) -> EagleDockGalleryTheme {
        let url = URL(string: "https://fixture.invalid/theme")!
        return EagleDockGalleryTheme(id: id, version: 1, title: "", titleES: "", subtitle: "", subtitleES: "", accent: "",
                                     previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
                                     frameCount: 1, fps: 1, width: 0, height: 0)
    }
    static func main() {
        let categoryEvents = ["session-read", "applying", "download", "selected", "session-read", "session-write", "sync", "feedback-category"]
        let stepEvents = ["applying", "download", "visible", "session-read", "session-write", "remember", "feedback-step"]
        let pair = [theme("s1"), theme("s2")]
        let cases: [Scenario] = [
            .init(label: "same category short circuit", action: .category(.still), applying: true, download: "busy",
                  expectedEvents: ["session-read"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "category applying guard", action: .category(.live), applying: true, download: "busy",
                  expectedEvents: ["session-read", "applying"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "category empty download ID guard", action: .category(.live), download: "",
                  expectedEvents: ["session-read", "applying", "download"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "live category and displayed memory", action: .category(.live),
                  expectedEvents: categoryEvents, expectedSelected: "saved-live", expectedFilter: .live, writes: 1),
            .init(label: "nil displayed memory deletion", action: .category(.favorites), displayed: nil,
                  expectedEvents: categoryEvents, expectedSelected: "saved-favorite", expectedFilter: .favorites, writes: 1),
            .init(label: "empty displayed identity", action: .category(.live), displayed: "",
                  expectedEvents: categoryEvents, expectedSelected: "saved-live", expectedFilter: .live, writes: 1),
            .init(label: "Unicode displayed identity", action: .category(.live), displayed: "e\u{301}",
                  expectedEvents: categoryEvents, expectedSelected: "saved-live", expectedFilter: .live, writes: 1),
            .init(label: "category read before copying state", action: .category(.live), mutateRead: true,
                  expectedEvents: ["session-read", "applying", "download", "selected", "read-mutation", "session-read", "session-write", "sync", "feedback-category"],
                  expectedSelected: "saved-live", expectedFilter: .live, writes: 1),
            .init(label: "category feedback after synchronization", action: .category(.live), mutateEffect: true,
                  expectedEvents: Array(categoryEvents.dropLast()) + ["effect-mutation", "feedback-category"],
                  expectedSelected: "saved-live", expectedFilter: .live, writes: 1),
            .init(label: "step applying guard", action: .step(1), applying: true,
                  expectedEvents: ["applying"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "step download guard", action: .step(-1), download: "busy",
                  expectedEvents: ["applying", "download"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "step empty list", action: .step(1),
                  expectedEvents: ["applying", "download", "visible"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "step singleton list", action: .step(1), themes: [theme("s1")],
                  expectedEvents: ["applying", "download", "visible"], expectedSelected: "s1", expectedFilter: .still, writes: 0),
            .init(label: "next", action: .step(1), themes: pair,
                  expectedEvents: stepEvents, expectedSelected: "s2", expectedFilter: .still, writes: 1),
            .init(label: "previous wraps", action: .step(-1), themes: pair,
                  expectedEvents: stepEvents, expectedSelected: "s2", expectedFilter: .still, writes: 1),
            .init(label: "stale selection fallback", action: .step(1), selected: "gone", themes: pair,
                  expectedEvents: stepEvents, expectedSelected: "s2", expectedFilter: .still, writes: 1),
            .init(label: "navigation reads after visible provider", action: .step(1), themes: pair, mutateRead: true,
                  expectedEvents: ["applying", "download", "visible", "read-mutation", "session-read", "session-write", "remember", "feedback-step"],
                  expectedSelected: "s2", expectedFilter: .still, writes: 1),
            .init(label: "navigation feedback after remembering", action: .step(1), themes: pair, mutateEffect: true,
                  expectedEvents: Array(stepEvents.dropLast()) + ["effect-mutation", "feedback-step"],
                  expectedSelected: "s2", expectedFilter: .still, writes: 1),
        ]
        for scenario in cases {
            let fixtures: [InteractionStorage] = [PreviousInteractionFixture(), OwnedInteractionFixture()]
            for fixture in fixtures {
                fixture.stored.selectedRemoteID = scenario.selected
                fixture.stored.readyRemotePreviewID = "ready"
                fixture.stored.shuffledRemoteIDs = ["s2", "s1", "s2"]
                fixture.stored.visitStarted = true
                fixture.stored.rememberedSelections.remember(id: "saved-static", for: .still)
                fixture.stored.rememberedSelections.remember(id: "saved-live", for: .live)
                fixture.stored.rememberedSelections.remember(id: "saved-favorite", for: .favorites)
                fixture.applying = scenario.applying
                fixture.downloadID = scenario.download
                fixture.displayedID = scenario.displayed
                fixture.themes = scenario.themes
                fixture.mutateOnRead = scenario.mutateRead
                fixture.mutateEffect = scenario.mutateEffect
                let before = InteractionSnapshot(fixture.stored)
                switch scenario.action {
                case .category(let filter): fixture.category(filter)
                case .step(let step): fixture.navigate(step)
                }
                precondition(fixture.events.map(\.name) == scenario.expectedEvents, "Incorrect event sequence: \(scenario.label)")
                precondition(fixture.events.filter { $0.name == "session-write" }.count == scenario.writes)
                precondition(fixture.stored.selectedRemoteID == scenario.expectedSelected && fixture.stored.mediaFilter == scenario.expectedFilter)
                precondition(fixture.stored.shuffledRemoteIDs == ["s2", "s1", "s2"])
                if scenario.writes == 0 { precondition(InteractionSnapshot(fixture.stored) == before) }
                if scenario.mutateRead {
                    precondition(!fixture.stored.visitStarted && fixture.stored.rememberedSelections.restoredID(for: .favorites) == "read-mutation")
                }
                if scenario.writes > 0, case .category = scenario.action {
                    precondition(fixture.stored.rememberedSelections.restoredID(for: .still).map { Array($0.utf8) } == scenario.displayed.map { Array($0.utf8) })
                }
            }
            precondition(fixtures[0].events == fixtures[1].events, "Previous and owned event/state traces differ: \(scenario.label)")
            precondition(InteractionSnapshot(fixtures[0].stored) == InteractionSnapshot(fixtures[1].stored))
        }
        print("PASS: \(cases.count) action scenarios / \(cases.count * 2) previous-and-owned runs; exact guard short circuits, reads, single writes, synchronization/persistence/feedback and state snapshots")
        checkFavoritesAndVisits()
    }

    static func checkFavoritesAndVisits() {
        // Busy flags do not block these actions in the original screen. Real
        // effects are inert; snapshots verify what each effect would observe.
        let initialJSON = ["[]", "[\"keep\",\"s1\"]", "invalid-json", "[\"é\",\"☀️\"]"]
        for json in initialJSON {
            for id in ["s1", "", "é"] {
                let fixtures: [InteractionStorage] = [PreviousInteractionFixture(), OwnedInteractionFixture()]
                for fixture in fixtures {
                    fixture.storedFavoritesJSON = json
                    fixture.stored.readyRemotePreviewID = "before"
                    fixture.applying = true
                    fixture.downloadID = "busy"
                    fixture.mutateEffect = true
                    let original = EagleDockGalleryFavorites.decode(json)
                    fixture.favorite(theme(id))
                    precondition(fixture.events.map(\.name) == ["favorites-read", "favorites-write", "sync", "effect-mutation", "feedback-favorite"])
                    precondition(EagleDockGalleryFavorites.decode(fixture.storedFavoritesJSON) == EagleDockGalleryFavorites.toggling(original, id: id))
                    // Repeated taps must read the newly saved value, not an old capture.
                    fixture.favorite(theme(id))
                    precondition(EagleDockGalleryFavorites.decode(fixture.storedFavoritesJSON) == original)
                }
                precondition(fixtures[0].events == fixtures[1].events)
                precondition(fixtures[0].storedFavoritesJSON == fixtures[1].storedFavoritesJSON)
            }
        }
        for filter in EagleDockGalleryMediaFilter.allCases {
            for mutateEffect in [false, true] {
                let fixtures: [InteractionStorage] = [PreviousInteractionFixture(), OwnedInteractionFixture()]
                for fixture in fixtures {
                    fixture.stored.mediaFilter = filter
                    fixture.stored.selectedRemoteID = "selected"
                    fixture.stored.readyRemotePreviewID = "ready"
                    fixture.stored.shuffledRemoteIDs = ["2", "1"]
                    fixture.stored.rememberedSelections.remember(id: "saved", for: filter)
                    fixture.storedFavoritesJSON = "[\"preserved\"]"
                    fixture.applying = true
                    fixture.downloadID = "busy"
                    fixture.mutateEffect = mutateEffect
                    for _ in 0..<2 {
                        fixture.events = []
                        fixture.begin()
                        var expected = EagleDockGallerySession()
                        expected.beginVisit()
                        if mutateEffect { expected.readyRemotePreviewID = "synchronized" }
                        precondition(InteractionSnapshot(fixture.stored) == InteractionSnapshot(expected))
                        precondition(fixture.storedFavoritesJSON == "[\"preserved\"]")
                        precondition(fixture.events.map(\.name) == ["session-read", "session-write", "sync"] + (mutateEffect ? ["effect-mutation"] : []))
                    }
                }
                precondition(fixtures[0].events == fixtures[1].events)
            }
        }
        print("PASS: 12 favorite scenarios with repeated taps and 6 repeated-visit scenarios; exact previous/owned persistence, reset and effect snapshots")
    }
}
