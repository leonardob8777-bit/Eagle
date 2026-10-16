import Foundation
typealias IslandGalleryFilter = EagleIslandGalleryFilter

@MainActor enum Trace { static var current = Recorder() }
@MainActor final class Recorder {
    var events: [String] = []
    var raw = 9
    var identifier = ""
    var flags = 0
    var mode = 0
    var liveID = "singularity-live"
    var activeID: String?
    var catalog: [Theme] = []
    var catalogReads = 0
    var changeCatalog = false
    var category: IslandGalleryFilter = .all
    var query = ""
    var saved: Set<String> = []
    var spanish = false
    var snapshot: String { "\(raw)|\(identifier)" }
}

enum IslandGalleryStyle: Int, CaseIterable {
    case starlight = 9, other = 10, duck = 32, blue = 33, flame = 34, singularityLive = 36
    var isAvailableInGallery: Bool {
        Trace.current.events.append("available.\(rawValue)")
        return rawValue < 32 || rawValue == 36
    }
}
struct Theme: Identifiable {
    let key: String
    let animated: Bool
    let label: String
    var id: String { Trace.current.events.append("theme.id.\(key).\(label)"); return key }
}
struct IslandGalleryArtwork: Identifiable {
    let style: IslandGalleryStyle
    let liveTheme: Theme?
    init(style: IslandGalleryStyle, liveTheme: Theme? = nil) {
        Trace.current.events.append("make.\(style.rawValue).\(liveTheme?.label ?? "nil")")
        self.style = style; self.liveTheme = liveTheme
    }
    var snapshot: String { "\(style.rawValue)|\(liveTheme?.key ?? "nil")|\(liveTheme?.label ?? "nil")" }
    var id: String {
        Trace.current.events.append("art.id.\(snapshot)")
        return liveTheme?.id ?? (style == .singularityLive ? "singularity-live" : "island-\(style.rawValue)")
    }
    var isLive: Bool {
        Trace.current.events.append("live.\(snapshot)")
        return style == .singularityLive && (liveTheme?.animated ?? true)
    }
    var title: String {
        Trace.current.events.append("title.\(snapshot)")
        return Trace.current.spanish ? "Océano \(liveTheme?.label ?? "Luz")" : "Ocean \(liveTheme?.label ?? "Light")"
    }
    var subtitle: String {
        Trace.current.events.append("subtitle.\(snapshot)")
        return Trace.current.spanish ? "Arte en movimiento" : "Art in motion"
    }
}
extension EagleIslandGalleryFilter {
    func includes(_ item: IslandGalleryArtwork, favorites: Set<String>) -> Bool {
        includes(isLive: item.isLive, artworkID: item.id, favorites: favorites)
    }
}
struct ActiveArtwork {
    let value: String
    var id: String { Trace.current.events.append("active.id"); return value }
}
@MainActor class Host {
    let recorder: Recorder
    init(_ recorder: Recorder) { self.recorder = recorder }
    var liveThemes: [Theme] {
        recorder.events.append("catalog.read")
        recorder.catalogReads += 1
        return recorder.changeCatalog && recorder.catalogReads > 1 ? [] : recorder.catalog
    }
    var search: String { recorder.events.append("search.read"); return recorder.query }
    var filter: IslandGalleryFilter { recorder.events.append("filter.read"); return recorder.category }
    var favorites: Set<String> { recorder.events.append("favorites.read"); return recorder.saved }
    var selectedRaw: Int {
        get { recorder.events.append("raw.read"); return recorder.raw }
        set { recorder.events.append("raw.write.\(newValue)"); recorder.raw = newValue }
    }
    var selectedID: String {
        get { recorder.events.append("id.read"); return recorder.identifier }
        set { recorder.events.append("id.write.\(newValue)"); recorder.identifier = newValue }
    }
    var activeFlagsRaw: Int { recorder.events.append("flags.read"); return recorder.flags }
    var activeIslandModeRaw: Int { recorder.events.append("mode.read"); return recorder.mode }
    var activeLiveID: String { recorder.events.append("liveID.read"); return recorder.liveID }
    var activeArtwork: ActiveArtwork? {
        recorder.events.append("active.read")
        return recorder.activeID.map { ActiveArtwork(value: $0) }
    }
    func collection(_ visible: Bool) -> [String] { fatalError("override required") }
    func restore() { fatalError("override required") }
}

@main struct Checks {
    static func main() {
        var recoveryCases = 0, recoveryEvents = 0
        for raw in [-1, 9, 10, 32, 33, 34, 36, 999] {
            for id in ["", "island-32", "island-33", "island-34", "unloaded-live", "unknown"] {
                for flags in [-1, 0, 1, 2, 3] {
                    for mode in [0, 9, 32, 36] {
                        for live in ["", "singularity-live", "unloaded-live"] {
                            for active: String? in [nil, "island-10", "remote-active"] {
                                func seed() -> Recorder {
                                    let r = Recorder(); r.raw = raw; r.identifier = id; r.flags = flags
                                    r.mode = mode; r.liveID = live; r.activeID = active; return r
                                }
                                let a = seed(), b = seed()
                                let old = PublicHost(a), owned = OwnedHost(b)
                                for _ in 0..<2 {
                                    a.events = []; b.events = []
                                    old.restore(); owned.restore()
                                    precondition(a.snapshot == b.snapshot && a.events == b.events,
                                                 "Recovery differs: \(a.events) / \(b.events)")
                                    recoveryCases += 1; recoveryEvents += b.events.count
                                }
                            }
                        }
                    }
                }
            }
        }
        print("PASS: \(recoveryCases) public/owned repeated-recovery cases; \(recoveryEvents) ordered events")
        let one = Theme(key: "singularity-live", animated: true, label: "First")
        let duplicate = Theme(key: "singularity-live", animated: false, label: "Second")
        let live = Theme(key: "blue-live", animated: true, label: "BLUE")
        let still = Theme(key: "remote-static", animated: false, label: "Still")
        let catalogs: [[Theme]] = [[], [one], [live, still], [one, live, duplicate, still], [still, live, live], [Theme(key: "", animated: false, label: "🌈")]]
        var collectionCases = 0, collectionEvents = 0
        for catalog in catalogs {
            for category in IslandGalleryFilter.allCases {
                for query in ["", " \n ", "ocean", "OcÉaNo", "motion", "ARTE", "blue-live", "missing", "🌈", " BLUE "] {
                    for saved: Set<String> in [[], ["singularity-live"], ["island-9", "remote-static"], ["blue-live", "missing"]] {
                        for spanish in [false, true] {
                            for changing in [false, true] {
                                for visible in [false, true] {
                                    func seed() -> Recorder {
                                        let r = Recorder(); r.catalog = catalog; r.category = category; r.query = query
                                        r.saved = saved; r.spanish = spanish; r.changeCatalog = changing; return r
                                    }
                                    let a = seed(), b = seed()
                                    let expected = PublicHost(a).collection(visible)
                                    let actual = OwnedHost(b).collection(visible)
                                    precondition(expected == actual && a.events == b.events,
                                                 "Collection differs: \(a.events) / \(b.events)")
                                    collectionCases += 1; collectionEvents += b.events.count
                                }
                            }
                        }
                    }
                }
            }
        }
        print("PASS: \(collectionCases) assembly/search/category cases; \(collectionEvents) ordered events, duplicate/absent remote identity and lazy metadata reads")
        let state = Recorder(), host = OwnedHost(state)
        state.raw = 32; state.identifier = "island-32"
        host.restore(); precondition(state.raw == 9 && state.identifier == "island-9")
        state.raw = 34; state.identifier = "unknown"
        host.restore(); precondition(state.raw == 9 && state.identifier == "unknown")
        state.identifier = ""; state.flags = 1; state.mode = 36; state.liveID = "unloaded-live"
        host.restore(); precondition(state.identifier == "unloaded-live")
        state.catalog = [one, duplicate, live, still]; state.catalogReads = 0
        let assembled = host.collection(false)
        precondition(assembled.count == 5 && assembled.contains("36|singularity-live|First"))
        precondition(!assembled.contains("36|singularity-live|Second"))
        precondition(!assembled.contains { $0.hasPrefix("32|") || $0.hasPrefix("33|") || $0.hasPrefix("34|") })
        print("PASS: independent retired-style reset, preserved unknown selection, unloaded active remote ID and first-Singularity-only invariants")
    }
}
