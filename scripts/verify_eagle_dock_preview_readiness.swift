import Foundation

struct PreviewReadinessSnapshot: Equatable {
    let displayed: [UInt8]?
    let selected: [UInt8]
    let ready: [UInt8]
    let order: [[UInt8]]
    let filter: String
    let started: Bool
    let memory: [[UInt8]?]

    init(_ storage: PreviewReadinessStorage) {
        displayed = storage.displayedID.map { Array($0.utf8) }
        selected = Array(storage.stored.selectedRemoteID.utf8)
        ready = Array(storage.stored.readyRemotePreviewID.utf8)
        order = storage.stored.shuffledRemoteIDs.map { Array($0.utf8) }
        filter = storage.stored.mediaFilter.rawValue
        started = storage.stored.visitStarted
        memory = EagleDockGalleryMediaFilter.allCases.map { storage.stored.rememberedSelections.restoredID(for: $0).map { Array($0.utf8) } }
    }
}

struct PreviewReadinessEvent: Equatable {
    let name: String
    let state: PreviewReadinessSnapshot
}

@MainActor
class PreviewReadinessStorage {
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    var stored = EagleDockGallerySession()
    var displayedID: String?
    var events: [PreviewReadinessEvent] = []
    var readinessAfterSelectedRead: String?
    var displayedAfterReadinessRead: String?
    @MainActor init() {}

    static func theme(_ id: String) -> EagleDockGalleryTheme {
        let url = URL(string: "https://fixture.invalid/preview")!
        return .init(id: id, version: 1, title: "", titleES: "", subtitle: "", subtitleES: "", accent: "",
                     previewURL: url, animatedPreviewURL: nil, packageURL: url, sha256: "", byteCount: 0,
                     frameCount: 1, fps: 1, width: 0, height: 0)
    }
    func record(_ name: String) { events.append(.init(name: name, state: PreviewReadinessSnapshot(self))) }
    var selectedRemoteTheme: EagleDockGalleryTheme? {
        record("selected-read")
        if let id = readinessAfterSelectedRead {
            stored.readyRemotePreviewID = id
            record("selected-read-mutation")
        }
        return displayedID.map(Self.theme)
    }
    var readyRemotePreviewID: String {
        get {
            record("ready-read")
            if let id = displayedAfterReadinessRead {
                displayedID = id
                record("ready-read-mutation")
            }
            return stored.readyRemotePreviewID
        }
        set { stored.readyRemotePreviewID = newValue; record("ready-write") }
    }
    func callback(for theme: RemoteDockGalleryTheme) -> (Bool) -> Void { preconditionFailure("Fixture override required") }
}

@main
@MainActor
private enum PreviewReadinessChecks {
    static func pair(displayed: String?, ready: String) -> [PreviewReadinessStorage] {
        let result: [PreviewReadinessStorage] = [PublicPreviewReadinessFixture(), OwnedPreviewReadinessFixture()]
        for fixture in result {
            fixture.displayedID = displayed
            fixture.stored.selectedRemoteID = "raw-selection-differs-from-displayed"
            fixture.stored.readyRemotePreviewID = ready
            fixture.stored.mediaFilter = .favorites
            fixture.stored.shuffledRemoteIDs = ["b", "a", "é"]
            fixture.stored.visitStarted = true
            fixture.stored.rememberedSelections.remember(id: "remembered", for: .live)
        }
        return result
    }
    static func parity(_ fixtures: [PreviewReadinessStorage]) {
        precondition(fixtures[0].events == fixtures[1].events, "Read/write events or observed state differ")
        precondition(PreviewReadinessSnapshot(fixtures[0]) == PreviewReadinessSnapshot(fixtures[1]), "Final session differs")
    }
    static func check(_ fixture: PreviewReadinessStorage, callback: (Bool) -> Void, value: Bool, id: String) {
        let before = PreviewReadinessSnapshot(fixture)
        let previousReady = fixture.stored.readyRemotePreviewID
        var names = ["selected-read"]
        var expectedReady = previousReady
        if fixture.displayedID == id {
            if value {
                expectedReady = id
                names.append("ready-write")
            } else {
                names.append("ready-read")
                if previousReady == id {
                    expectedReady = ""
                    names.append("ready-write")
                }
            }
        }
        fixture.events = []
        callback(value)
        precondition(fixture.events.map(\.name) == names, "Unexpected lazy read/write sequence")
        precondition(Array(fixture.stored.readyRemotePreviewID.utf8) == Array(expectedReady.utf8), "Stored ID bytes changed")
        let after = PreviewReadinessSnapshot(fixture)
        precondition(before.displayed == after.displayed && before.selected == after.selected && before.order == after.order &&
                     before.filter == after.filter && before.started == after.started && before.memory == after.memory,
                     "Readiness must not reset other session fields")
    }
    static func main() {
        let ids = ["a", "b", "", " ", "é", "e\u{301}", "🍀"]
        let displayed: [String?] = [nil] + ids.map(Optional.some)
        var cases = 0
        for id in ids {
            for selected in displayed {
                for initialReady in ids {
                    for value in [false, true] {
                        let fixtures = pair(displayed: selected, ready: initialReady)
                        let callbacks = fixtures.map { $0.callback(for: PreviewReadinessStorage.theme(id)) }
                        // Capture once, then deliver repeats and the opposite state.
                        for event in [value, value, !value] {
                            for index in fixtures.indices { check(fixtures[index], callback: callbacks[index], value: event, id: id) }
                            parity(fixtures)
                        }
                        cases += 1
                    }
                }
            }
        }
        let transitions = checkLateCallbacks()
        let mutations = checkReadMutations()
        print("PASS: \(cases) preview cases / \(cases * 6) original-and-owned callback deliveries; nil/empty/Unicode IDs, repeated writes, lazy reads and complete session preservation")
        print("PASS: \(transitions) delayed/reordered event checkpoints, retained callback captures and \(mutations) read-mutation scenarios; no media requests or rendering")
    }

    static func checkLateCallbacks() -> Int {
        let fixtures = pair(displayed: "a", ready: "")
        let a = fixtures.map { $0.callback(for: PreviewReadinessStorage.theme("a")) }
        let b = fixtures.map { $0.callback(for: PreviewReadinessStorage.theme("b")) }
        let events: [(String?, String, Bool)] = [
            ("a", "a", true), ("b", "a", false), ("b", "b", true),
            ("b", "a", true), ("b", "b", false), ("b", "b", false),
            (nil, "b", true), ("a", "b", false), ("a", "a", true), ("a", "a", true),
        ]
        for (selected, themeID, ready) in events {
            for index in fixtures.indices {
                fixtures[index].displayedID = selected
                check(fixtures[index], callback: themeID == "a" ? a[index] : b[index], value: ready, id: themeID)
            }
            parity(fixtures)
        }
        return events.count
    }

    static func checkReadMutations() -> Int {
        var cases = 0
        for selected in [nil, "a", "b"] as [String?] {
            for initial in ["a", "b", ""] {
                for replacement in ["a", "b", ""] {
                    for ready in [false, true] {
                        let fixtures = pair(displayed: selected, ready: initial)
                        for fixture in fixtures {
                            fixture.readinessAfterSelectedRead = replacement
                            fixture.displayedAfterReadinessRead = "changed-during-read"
                            fixture.callback(for: PreviewReadinessStorage.theme("a"))(ready)
                            let selectedMatches = selected == "a"
                            let expected = selectedMatches && ready ? "a" : (selectedMatches && replacement == "a" ? "" : replacement)
                            precondition(fixture.stored.readyRemotePreviewID == expected)
                            let hasReadyRead = selectedMatches && !ready
                            var names = ["selected-read", "selected-read-mutation"]
                            if hasReadyRead { names += ["ready-read", "ready-read-mutation"] }
                            if selectedMatches && (ready || replacement == "a") { names.append("ready-write") }
                            precondition(fixture.events.map(\.name) == names)
                            precondition(fixture.displayedID == (hasReadyRead ? "changed-during-read" : selected))
                        }
                        parity(fixtures)
                        cases += 1
                    }
                }
            }
        }
        return cases
    }
}
