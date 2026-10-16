import Foundation

struct SynchronizationSnapshot: Equatable {
    let selected: [UInt8]
    let preview: [UInt8]
    let filter: String
    let order: [[UInt8]]
    let started: Bool
    let memory: [[UInt8]?]

    init(_ session: EagleDockGallerySession) {
        selected = Array(session.selectedRemoteID.utf8)
        preview = Array(session.readyRemotePreviewID.utf8)
        filter = session.mediaFilter.rawValue
        order = session.shuffledRemoteIDs.map { Array($0.utf8) }
        started = session.visitStarted
        memory = EagleDockGalleryMediaFilter.allCases.map {
            session.rememberedSelections.restoredID(for: $0).map { Array($0.utf8) }
        }
    }
}

enum SynchronizationEvent: Equatable {
    case catalog([[UInt8]])
    case sessionRead(SynchronizationSnapshot)
    case sessionWrite(SynchronizationSnapshot)
    case shuffle([[UInt8]])
    case historyRead(String)
    case historyWrite(String, [UInt8])
    case visible(SynchronizationSnapshot)
    case selected
    case remember(SynchronizationSnapshot)
    case mutation(String)

    var kind: String {
        switch self {
        case .catalog: return "catalog"
        case .sessionRead: return "session-read"
        case .sessionWrite: return "session-write"
        case .shuffle: return "shuffle"
        case .historyRead(let category): return "read-" + category
        case .historyWrite(let category, _): return "write-" + category
        case .visible: return "visible"
        case .selected: return "selected"
        case .remember: return "remember"
        case .mutation(let boundary): return "mutate-" + boundary
        }
    }
}

@MainActor
class SynchronizationStorage {
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme

    @MainActor init() {}

    struct Catalog {
        unowned let storage: SynchronizationStorage
        var themes: [EagleDockGalleryTheme] { storage.readCatalog() }
    }

    var storedSession = EagleDockGallerySession()
    var catalogs: [[EagleDockGalleryTheme]] = []
    var catalogReads = 0
    var favoriteIDs: Set<String> = []
    var storedStatic = ""
    var storedLive = ""
    var shuffleOutput: [String] = []
    var shuffleInputs: [[String]] = []
    var events: [SynchronizationEvent] = []
    var mutateDuringShuffle = false
    var selectDuringVisible: String?
    var visibleReads = 0

    var remoteGallery: Catalog { Catalog(storage: self) }
    var session: EagleDockGallerySession {
        get {
            events.append(.sessionRead(SynchronizationSnapshot(storedSession)))
            return storedSession
        }
        set {
            events.append(.sessionWrite(SynchronizationSnapshot(newValue)))
            storedSession = newValue
        }
    }
    var shuffledRemoteIDs: [String] { session.shuffledRemoteIDs }
    var selectedRemoteID: String { session.selectedRemoteID }
    var mediaFilter: EagleDockGalleryMediaFilter { session.mediaFilter }
    var lastViewedStaticID: String {
        get { events.append(.historyRead("static")); return storedStatic }
        set { events.append(.historyWrite("static", Array(newValue.utf8))); storedStatic = newValue }
    }
    var lastViewedLiveID: String {
        get { events.append(.historyRead("live")); return storedLive }
        set { events.append(.historyWrite("live", Array(newValue.utf8))); storedLive = newValue }
    }
    var visibleRemoteThemes: [EagleDockGalleryTheme] {
        events.append(.visible(SynchronizationSnapshot(storedSession)))
        let result = computeVisible()
        visibleReads += 1
        if visibleReads == 1, let selected = selectDuringVisible {
            storedSession.selectedRemoteID = selected
            storedSession.readyRemotePreviewID = "visible-ready"
            events.append(.mutation("visible"))
        }
        return result
    }
    var selectedRemoteTheme: EagleDockGalleryTheme? {
        events.append(.selected)
        return computeSelected()
    }
    func rememberViewedTheme() {
        events.append(.remember(SynchronizationSnapshot(storedSession)))
        computeRemember()
    }
    func readCatalog() -> [EagleDockGalleryTheme] {
        precondition(!catalogs.isEmpty)
        let result = catalogs[min(catalogReads, catalogs.count - 1)]
        catalogReads += 1
        events.append(.catalog(result.map { Array($0.id.utf8) }))
        return result
    }
    func shuffle(_ additions: [String]) -> [String] {
        shuffleInputs.append(additions)
        // Set iteration order is unspecified. Compare the actual shuffle input
        // membership and multiplicity, while injecting one fixed permutation.
        events.append(.shuffle(additions.map { Array($0.utf8) }.sorted { $0.lexicographicallyPrecedes($1) }))
        precondition(Set(additions) == Set(shuffleOutput) && additions.count == shuffleOutput.count,
                     "Deterministic shuffle must receive exactly the expected new IDs")
        if mutateDuringShuffle {
            storedSession.readyRemotePreviewID = "shuffle-ready"
            storedSession.rememberedSelections.remember(id: "shuffle-memory", for: .live)
            events.append(.mutation("shuffle"))
        }
        return shuffleOutput
    }
    func run() { preconditionFailure("Fixture must implement the synchronization entry point") }
}

@MainActor
final class DirectSynchronizationFixture: SynchronizationStorage {
    override func run() {
        EagleDockGallerySynchronization.synchronize(
            catalog: { remoteGallery.themes },
            readSession: { session },
            writeSession: { session = $0 },
            shuffle: { shuffle($0) },
            lastViewedStaticID: { lastViewedStaticID },
            lastViewedLiveID: { lastViewedLiveID },
            visibleThemes: { visibleRemoteThemes },
            rememberViewedTheme: { rememberViewedTheme() }
        )
    }
}

@main
private enum SynchronizationChecks {
    struct Scenario {
        let label: String
        let catalog: [EagleDockGalleryTheme]
        var laterCatalog: [EagleDockGalleryTheme]? = nil
        var previousOrder: [String] = []
        var selected = "missing"
        var preview = "ready"
        var filter: EagleDockGalleryMediaFilter = .still
        var favorites: Set<String> = []
        var lastStatic = "old-static"
        var lastLive = "old-live"
        var additions: [String] = []
        let expectedOrder: [String]
        let expectedSelected: String
        let expectedPreview: String
        let readsHistory: Bool
        let writesOrder: Bool
        let writesSelection: Bool
        let preference: String?
        var expectedPreferenceID: String? = nil
        var mutateDuringShuffle = false
        var selectDuringVisible: String? = nil

        var expectedKinds: [String] {
            var result = ["catalog", "session-read", "shuffle"]
            if mutateDuringShuffle { result.append("mutate-shuffle") }
            if readsHistory { result += ["read-static", "read-live", "catalog"] }
            result.append("session-read")
            if writesOrder { result.append("session-write") }
            result += ["visible", "catalog", "session-read", "session-read"]
            if selectDuringVisible != nil { result.append("mutate-visible") }
            result.append("session-read")
            if writesSelection { result.append("session-write") }
            result += ["remember", "selected", "visible", "catalog", "session-read", "session-read", "session-read"]
            if let preference { result.append("write-" + preference) }
            return result
        }
    }

    static func theme(_ id: String, _ frames: Int = 1) -> EagleDockGalleryTheme {
        let url = URL(string: "https://fixture.invalid/theme")!
        return EagleDockGalleryTheme(id: id, version: 1, title: "", titleES: "", subtitle: "", subtitleES: "", accent: "",
                                     previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
                                     frameCount: frames, fps: 1, width: 0, height: 0)
    }

    static func initialSession(_ scenario: Scenario) -> EagleDockGallerySession {
        var result = EagleDockGallerySession()
        result.shuffledRemoteIDs = scenario.previousOrder
        result.selectedRemoteID = scenario.selected
        result.readyRemotePreviewID = scenario.preview
        result.mediaFilter = scenario.filter
        result.visitStarted = true
        result.rememberedSelections.remember(id: "still-memory", for: .still)
        result.rememberedSelections.remember(id: "e\u{301}", for: .live)
        result.rememberedSelections.remember(id: "", for: .favorites)
        return result
    }

    static func main() {
        let four = [theme("s1"), theme("s2"), theme("l1", 17), theme("l2", 2)]
        var scenarios: [Scenario] = [
            Scenario(label: "fresh sequential category swaps", catalog: four,
                     lastStatic: "s1", lastLive: "l1", additions: ["l1", "s1", "l2", "s2"],
                     expectedOrder: ["l2", "s2", "l1", "s1"], expectedSelected: "s2", expectedPreview: "",
                     readsHistory: true, writesOrder: true, writesSelection: true, preference: "static"),
            Scenario(label: "retained order with additions", catalog: four, previousOrder: ["s1", "l1"],
                     selected: "s1", lastStatic: "s1", lastLive: "l1", additions: ["l2", "s2"],
                     expectedOrder: ["s1", "l1", "l2", "s2"], expectedSelected: "s1", expectedPreview: "ready",
                     readsHistory: false, writesOrder: true, writesSelection: false, preference: "static"),
            Scenario(label: "unchanged order and valid selection", catalog: four, previousOrder: ["s2", "l2", "s1", "l1"],
                     selected: "s1", lastStatic: "s1",
                     expectedOrder: ["s2", "l2", "s1", "l1"], expectedSelected: "s1", expectedPreview: "ready",
                     readsHistory: false, writesOrder: false, writesSelection: false, preference: "static"),
            Scenario(label: "removed catalog and explicit empty replacement", catalog: [], previousOrder: ["gone"], selected: "",
                     expectedOrder: [], expectedSelected: "", expectedPreview: "",
                     readsHistory: true, writesOrder: true, writesSelection: true, preference: nil),
            Scenario(label: "already empty still writes explicit replacement", catalog: [], selected: "", preview: "",
                     expectedOrder: [], expectedSelected: "", expectedPreview: "",
                     readsHistory: true, writesOrder: false, writesSelection: true, preference: nil),
            Scenario(label: "favorites stale selection persists displayed live theme", catalog: four,
                     previousOrder: ["s1", "l1", "s2", "l2"], filter: .favorites, favorites: ["l1"],
                     expectedOrder: ["s1", "l1", "s2", "l2"], expectedSelected: "l1", expectedPreview: "",
                     readsHistory: false, writesOrder: false, writesSelection: true, preference: "live"),
            Scenario(label: "empty favorites keep both preferences", catalog: four,
                     previousOrder: ["s1", "l1", "s2", "l2"], selected: "l1", filter: .favorites,
                     expectedOrder: ["s1", "l1", "s2", "l2"], expectedSelected: "", expectedPreview: "",
                     readsHistory: false, writesOrder: false, writesSelection: true, preference: nil),
            Scenario(label: "fresh live selection", catalog: [theme("l1", 17), theme("l2", 2)],
                     filter: .live, lastLive: "l1", additions: ["l1", "l2"],
                     expectedOrder: ["l2", "l1"], expectedSelected: "l2", expectedPreview: "",
                     readsHistory: true, writesOrder: true, writesSelection: true, preference: "live"),
            Scenario(label: "all old IDs removed starts fresh history", catalog: [theme("s1"), theme("s2")],
                     previousOrder: ["gone"], lastStatic: "s1", additions: ["s1", "s2"],
                     expectedOrder: ["s2", "s1"], expectedSelected: "s2", expectedPreview: "",
                     readsHistory: true, writesOrder: true, writesSelection: true, preference: "static"),
            Scenario(label: "fresh avoidance reads later catalog", catalog: [theme("s1"), theme("s2")],
                     laterCatalog: [theme("s1")], lastStatic: "s1", additions: ["s1", "s2"],
                     expectedOrder: ["s1", "s2"], expectedSelected: "s1", expectedPreview: "",
                     readsHistory: true, writesOrder: true, writesSelection: true, preference: "static"),
            Scenario(label: "retained repeated IDs", catalog: [theme("s1"), theme("s2")],
                     previousOrder: ["gone", "s1", "s1"], selected: "s1", additions: ["s2"],
                     expectedOrder: ["s1", "s1", "s2"], expectedSelected: "s1", expectedPreview: "ready",
                     readsHistory: false, writesOrder: true, writesSelection: false, preference: "static"),
            Scenario(label: "order commit reads session after shuffle", catalog: [theme("s1")],
                     selected: "s1", additions: ["s1"],
                     expectedOrder: ["s1"], expectedSelected: "s1", expectedPreview: "shuffle-ready",
                     readsHistory: true, writesOrder: true, writesSelection: false, preference: "static", mutateDuringShuffle: true),
            Scenario(label: "reconciliation reads session after visible snapshot", catalog: [theme("s1"), theme("s2")],
                     previousOrder: ["s1", "s2"],
                     expectedOrder: ["s1", "s2"], expectedSelected: "s2", expectedPreview: "visible-ready",
                     readsHistory: false, writesOrder: false, writesSelection: false, preference: "static", selectDuringVisible: "s2"),
        ]
        for (stored, catalogID) in [("é", "e\u{301}"), ("e\u{301}", "é")] {
            scenarios.append(Scenario(label: "Unicode no-op retains stored bytes \(Array(stored.utf8))", catalog: [theme(catalogID)],
                                      previousOrder: [stored], selected: stored,
                                      expectedOrder: [stored], expectedSelected: stored, expectedPreview: "ready",
                                      readsHistory: false, writesOrder: false, writesSelection: false, preference: "static",
                                      expectedPreferenceID: catalogID))
        }

        var runs = 0
        for scenario in scenarios {
            let initial = initialSession(scenario)
            var expected = initial
            expected.shuffledRemoteIDs = scenario.expectedOrder
            expected.selectedRemoteID = scenario.expectedSelected
            expected.readyRemotePreviewID = scenario.expectedPreview
            if scenario.mutateDuringShuffle {
                expected.rememberedSelections.remember(id: "shuffle-memory", for: .live)
            }
            var afterOrder = initial
            afterOrder.shuffledRemoteIDs = scenario.expectedOrder
            if scenario.mutateDuringShuffle {
                afterOrder.readyRemotePreviewID = "shuffle-ready"
                afterOrder.rememberedSelections.remember(id: "shuffle-memory", for: .live)
            }
            let fixtures: [SynchronizationStorage] = [PreviousSynchronizationFixture(), DirectSynchronizationFixture(), ScreenSynchronizationFixture()]
            for fixture in fixtures {
                fixture.storedSession = initial
                fixture.catalogs = [scenario.catalog] + (scenario.laterCatalog.map { [$0] } ?? [])
                fixture.favoriteIDs = scenario.favorites
                fixture.storedStatic = scenario.lastStatic
                fixture.storedLive = scenario.lastLive
                fixture.shuffleOutput = scenario.additions
                fixture.mutateDuringShuffle = scenario.mutateDuringShuffle
                fixture.selectDuringVisible = scenario.selectDuringVisible
                fixture.run()

                precondition(SynchronizationSnapshot(fixture.storedSession) == SynchronizationSnapshot(expected),
                             "Final session or preserved fields differ: \(scenario.label)")
                precondition(fixture.events.map(\.kind) == scenario.expectedKinds,
                             "Read/write/persistence order differs: \(scenario.label): \(fixture.events.map(\.kind))")
                precondition(fixture.shuffleInputs.count == 1, "Exactly one shuffle, including empty additions: \(scenario.label)")
                precondition(Set(fixture.shuffleInputs[0]) == Set(scenario.additions) && fixture.shuffleInputs[0].count == scenario.additions.count)
                precondition(fixture.catalogReads == (scenario.readsHistory ? 4 : 3),
                             "Prior owned avoidance reads one fresh category snapshot; displayed getters add their two reads")
                let visibleStates = fixture.events.compactMap { event -> SynchronizationSnapshot? in
                    if case .visible(let state) = event { return state }; return nil
                }
                let rememberedStates = fixture.events.compactMap { event -> SynchronizationSnapshot? in
                    if case .remember(let state) = event { return state }; return nil
                }
                precondition(visibleStates == [SynchronizationSnapshot(afterOrder), SynchronizationSnapshot(expected)],
                             "Visible snapshot must follow order commit; persistence must use the final displayed state")
                precondition(rememberedStates == [SynchronizationSnapshot(expected)], "Remember exactly once after reconciliation")
                let preferenceID = scenario.expectedPreferenceID ?? scenario.expectedSelected
                precondition(Array(fixture.storedStatic.utf8) == Array((scenario.preference == "static" ? preferenceID : scenario.lastStatic).utf8))
                precondition(Array(fixture.storedLive.utf8) == Array((scenario.preference == "live" ? preferenceID : scenario.lastLive).utf8))
                runs += 1
            }
            precondition(fixtures[0].events == fixtures[1].events && fixtures[0].events == fixtures[2].events,
                         "Actual coordinator/screen must preserve every prior inline event and snapshot: \(scenario.label)")
        }
        print("PASS: \(scenarios.count) synchronization scenarios across \(runs) prior-inline/coordinator/screen runs; exact read/write/persistence traces and one deterministic shuffle")
        print("PASS: fresh/retained/empty/favorites/Unicode no-ops, explicit empty replacement, session rereads and lazy single category snapshot")
    }
}
