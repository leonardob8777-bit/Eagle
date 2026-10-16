import Foundation

typealias IslandGalleryFilter = EagleIslandGalleryFilter

@MainActor final class Recorder {
    var identifier = ""
    var raw = 9
    var category: IslandGalleryFilter = .all
    var memory: [IslandGalleryFilter: String] = [:]
    var busy = false
    var tripBusyOnIDWrite = false
    var ids = ["still", "live-a", "live-b"]
    var favorites: Set<String> = ["still", "live-b"]
    var query = ""
    var events: [String] = []
    var snapshot: String {
        "\(identifier)|\(raw)|\(category.rawValue)|\(busy)|" + memory.keys.sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue)=\(memory[$0]!)" }.joined(separator: ",")
    }
}

@MainActor struct IslandGalleryArtwork: Identifiable {
    let identifier: String
    let recorder: Recorder
    var id: String { recorder.events.append("art.id.\(identifier)"); return identifier }
    struct Style { let rawValue: Int }
    var style: Style {
        recorder.events.append("art.style.\(identifier)")
        return Style(rawValue: identifier.hasPrefix("live") ? 36 : 9)
    }
}

@MainActor struct UISelectionFeedbackGenerator {
    static var recorder: Recorder?
    func selectionChanged() { Self.recorder!.events.append("feedback") }
}

enum Action {
    case selected, index, select(String), category(IslandGalleryFilter), sync, step(Int)
}

@MainActor class Host {
    let recorder: Recorder
    init(_ recorder: Recorder) { self.recorder = recorder }
    func artwork(_ id: String) -> IslandGalleryArtwork { .init(identifier: id, recorder: recorder) }
    var applying: Bool { recorder.events.append("busy.read"); return recorder.busy }
    var selectedID: String {
        get { recorder.events.append("id.read"); return recorder.identifier }
        set {
            recorder.events.append("id.write.\(newValue)"); recorder.identifier = newValue
            if recorder.tripBusyOnIDWrite { recorder.busy = true }
        }
    }
    var selectedRaw: Int {
        get { recorder.events.append("style.read"); return recorder.raw }
        set { recorder.events.append("style.write.\(newValue)"); recorder.raw = newValue }
    }
    var filter: IslandGalleryFilter {
        get { recorder.events.append("filter.read"); return recorder.category }
        set { recorder.events.append("filter.write.\(newValue.rawValue)"); recorder.category = newValue }
    }
    var rememberedSelections: [IslandGalleryFilter: String] {
        get { recorder.events.append("memory.read"); return recorder.memory }
        set { recorder.events.append("memory.write"); recorder.memory = newValue }
    }
    var visibleArtworks: [IslandGalleryArtwork] {
        recorder.events.append("visible.read.\(recorder.category.rawValue)")
        return recorder.ids.filter {
            (recorder.query.isEmpty || $0.contains(recorder.query)) &&
            recorder.category.includes(isLive: $0.hasPrefix("live"), artworkID: $0, favorites: recorder.favorites)
        }.map(artwork)
    }
    func run(_ action: Action) -> String { fatalError("override required") }
}

@main struct Checks {
    static func main() {
        let actions: [Action] = [.selected, .index, .select("still"), .select("live-b"), .select("unknown"),
                                 .category(.all), .category(.live), .category(.still), .category(.favorites),
                                 .sync, .step(-1), .step(0), .step(1), .step(3)]
        let lists = [[], ["still"], ["live-a"], ["still", "live-a", "live-b"], ["live-b", "still", "live-a"], ["still", "still", "live-a"]]
        let memories: [[IslandGalleryFilter: String]] = [[:], [.all: "still", .live: "live-b", .still: "still", .favorites: "live-b"], [.all: "missing", .live: "missing", .still: "live-a", .favorites: "missing"]]
        var cases = 0
        var events = 0
        func compare(_ old: PublicHost, _ owned: OwnedHost, _ action: Action) {
            old.recorder.events = []; owned.recorder.events = []
            let expected = old.run(action)
            let actual = owned.run(action)
            precondition(expected == actual, "Return differs")
            precondition(old.recorder.snapshot == owned.recorder.snapshot, "State differs")
            precondition(old.recorder.events == owned.recorder.events,
                         "Ordered reads/effects differ:\n\(old.recorder.events)\n\(owned.recorder.events)")
            events += owned.recorder.events.count
            cases += 1
        }
        for list in lists {
            for id in ["", "still", "live-a", "live-b", "missing"] {
                for category in IslandGalleryFilter.allCases {
                    for memory in memories {
                        for mode in 0..<3 {
                            for action in actions {
                                func seed() -> Recorder {
                                    let r = Recorder()
                                    r.ids = list; r.identifier = id; r.category = category; r.memory = memory
                                    r.busy = mode == 1; r.tripBusyOnIDWrite = mode == 2
                                    return r
                                }
                                let old = PublicHost(seed()), owned = OwnedHost(seed())
                                compare(old, owned, action)
                                if mode == 1 {
                                    switch action {
                                    case .selected, .index: break
                                    default: precondition(owned.recorder.events == ["busy.read"])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        print("PASS: \(cases) public/owned selection/category/navigation cases; \(events) ordered events")
        let initialCases = cases
        var sequences = 0
        for memory in memories {
            for initial in IslandGalleryFilter.allCases {
                let a = Recorder(), b = Recorder()
                a.memory = memory; b.memory = memory; a.category = initial; b.category = initial
                let old = PublicHost(a), owned = OwnedHost(b)
                for round in 0..<8 {
                    for action in actions { compare(old, owned, action) }
                    // Changes model the existing observers, not new production observers.
                    a.query = round % 2 == 0 ? "missing" : "live"; b.query = a.query
                    compare(old, owned, .sync); compare(old, owned, .selected)
                    a.query = ""; b.query = ""
                    a.favorites = round % 2 == 0 ? [] : ["live-a"]; b.favorites = a.favorites
                    compare(old, owned, .category(.favorites)); compare(old, owned, .sync)
                    a.ids = round % 2 == 0 ? ["still"] : ["still", "live-a", "live-b"]; b.ids = a.ids
                    compare(old, owned, .sync); compare(old, owned, .category(.all))
                    compare(old, owned, .step(-1)); compare(old, owned, .step(1))
                }
                sequences += 1
            }
        }
        print("PASS: \(sequences) sustained mixed sequences / \(cases-initialCases) actions; search, favorites, catalog arrival/removal and category memory")
        // Independent expectations for important behavior, not just differential checks.
        let state = Recorder(), host = OwnedHost(state)
        _ = host.run(.category(.live)); _ = host.run(.step(-1))
        precondition(state.identifier == "live-b" && state.raw == 36)
        _ = host.run(.category(.still)); precondition(state.identifier == "still")
        _ = host.run(.category(.live)); precondition(state.identifier == "live-b")
        state.ids = []; let before = state.snapshot
        _ = host.run(.sync); _ = host.run(.step(1))
        precondition(state.snapshot == before && host.run(.selected) == "<nil>")
        state.busy = true; state.events = []
        _ = host.run(.category(.all)); precondition(state.events == ["busy.read"])
        print("PASS: explicit wrap/category recall/empty-list/busy invariants; no UI, persistence, network or native execution")
    }
}
