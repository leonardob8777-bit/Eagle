import Foundation

struct StoredSelectionState: Equatable {
    var selected = 15
    var active = 0
    var mode = 0
    var flags = 32
    var remote = ""

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selected == rhs.selected && lhs.active == rhs.active && lhs.mode == rhs.mode &&
        lhs.flags == rhs.flags && Array(lhs.remote.utf8) == Array(rhs.remote.utf8)
    }
}

struct StoredSelectionEvent: Equatable {
    let name: String
    let state: StoredSelectionState
}

@MainActor
class StoredSelectionStorage {
    typealias DockGalleryStyle = EagleDockGalleryBuiltInTheme
    var stored = StoredSelectionState()
    var events: [StoredSelectionEvent] = []
    var onEvent: ((String) -> Void)?
    @MainActor init() {}

    func record(_ name: String) {
        events.append(.init(name: name, state: stored))
        onEvent?(name)
    }
    var selectedRaw: Int {
        get { record("selected-read"); return stored.selected }
        set { stored.selected = newValue; record("selected-write") }
    }
    var activeRaw: Int {
        get { record("active-read"); return stored.active }
        set { stored.active = newValue; record("active-write") }
    }
    var activeDockModeRaw: Int {
        get { record("mode-read"); return stored.mode }
        set { stored.mode = newValue; record("mode-write") }
    }
    var activeRemoteID: String {
        get { record("remote-read"); return stored.remote }
        set { stored.remote = newValue; record("remote-write") }
    }
    var hasVerifiedDock: Bool {
        record("verified-read")
        return EagleStoredThemeValues.flags(stored.flags) & (1 << 5) != 0
    }
    func reconcile() { preconditionFailure("Fixture override required") }
    class func mapped(_ mode: Int) -> String? { preconditionFailure("Fixture override required") }
}

@main
@MainActor
private enum StoredSelectionChecks {
    static let valid: Set<Int> = [15, 16, 17, 28, 29, 30]
    static let ids = ["bubblegum", "springfield", "bikini-bottom", "neon-chase", "neon-drift", "glitch-orbit",
                      "pop-glasses", "inferno-wings", "cool-cat", "cyber-love", "padded-room", "noir-vision",
                      "thirsty-cat", "duck-mood", "blue-screen", "walking-flame", "prism-blur"]

    static func expectedID(_ mode: Int) -> String? {
        (15...31).contains(mode) ? ids[mode - 15] : nil
    }
    static func expected(_ input: StoredSelectionState) -> StoredSelectionState {
        var state = input
        let verified = input.flags >= 0 && input.flags <= Int(UInt32.max) && input.flags & 32 != 0
        if !valid.contains(state.selected) { state.selected = 15 }
        if verified && valid.contains(state.active) && state.mode == 1 {
            state.mode = state.active
        } else if !verified || !valid.contains(state.mode) {
            state.active = 0
        }
        if verified && state.remote.isEmpty, let id = expectedID(state.mode) { state.remote = id }
        return state
    }
    static func fixtures(_ initial: StoredSelectionState) -> [StoredSelectionStorage] {
        let pair: [StoredSelectionStorage] = [PublicStoredSelectionFixture(), OwnedStoredSelectionFixture()]
        pair.forEach { $0.stored = initial }
        return pair
    }
    static func assertParity(_ pair: [StoredSelectionStorage]) {
        precondition(pair[0].events == pair[1].events, "Read/write order or observed state changed")
        precondition(pair[0].stored == pair[1].stored, "Saved value changed")
    }
    static func main() async {
        let values = [Int.min, -1, 0, 1, 15, 16, 17, 18, 27, 28, 29, 30, 31, 35, Int.max]
        let flags = [Int.min, -1, 0, 1, 32, 33, Int(UInt32.max), Int(UInt32.max) + 1, Int.max]
        let remotes = ["", " ", "custom", "e\u{301}", "é"]
        var cases = 0
        for selected in values {
            for active in values {
                for mode in values {
                    for flag in flags {
                        for remote in remotes {
                            let initial = StoredSelectionState(selected: selected, active: active, mode: mode, flags: flag, remote: remote)
                            let pair = fixtures(initial)
                            for fixture in pair {
                                fixture.reconcile()
                                precondition(fixture.stored == expected(initial), "Unexpected normalization")
                                let once = fixture.stored
                                fixture.reconcile()
                                precondition(fixture.stored == expected(once), "Repeated reconciliation changed semantics")
                                precondition(fixture.stored.flags == initial.flags, "Flags must not be written")
                            }
                            assertParity(pair)
                            cases += 1
                        }
                    }
                }
            }
        }
        var mappingCases = 0
        for mode in [Int.min, Int.max] + Array(-10...50) {
            precondition(PublicStoredSelectionFixture.mapped(mode) == expectedID(mode))
            precondition(OwnedStoredSelectionFixture.mapped(mode) == expectedID(mode))
            precondition(EagleDockGalleryStoredSelection.remoteID(forLegacyMode: mode) == expectedID(mode))
            mappingCases += 1
        }
        let mutationCases = checkMutations()
        checkExplicitOrder()
        let detached = await Task.detached {
            (15...31).map { EagleDockGalleryStoredSelection.remoteID(forLegacyMode: $0) }
        }.value
        precondition(detached == ids.map(Optional.some))
        print("PASS: \(cases) saved-selection cases / \(cases * 4) original-and-owned calls including repeats; complete read/write snapshots, raw flags, invalid integers and exact UTF-8 preservation")
        print("PASS: \(mappingCases) legacy mappings across original/owned/screen helpers, 17 detached mappings, \(mutationCases) read/setter-mutation scenarios and explicit guard/write sequences")
    }

    static func checkExplicitOrder() {
        let pair = fixtures(.init(selected: -1, active: 16, mode: 1))
        for fixture in pair {
            fixture.reconcile()
            precondition(fixture.events.map(\.name) == [
                "selected-read", "selected-write", "verified-read", "active-read", "mode-read", "active-read", "mode-write",
                "verified-read", "remote-read", "mode-read", "remote-write",
            ])
            precondition(fixture.stored == .init(selected: 15, active: 16, mode: 16, remote: "springfield"))
        }
        assertParity(pair)
        let unverified = fixtures(.init(active: 0, mode: 16, flags: 0, remote: "custom"))
        for fixture in unverified {
            fixture.reconcile()
            precondition(fixture.events.map(\.name) == ["selected-read", "verified-read", "verified-read", "active-write", "verified-read"])
        }
        assertParity(unverified)
    }

    static func checkMutations() -> Int {
        // Mutation on a property event mimics storage changing between reads.
        // Both historical and extracted bodies must observe the same new state.
        let events = ["selected-read", "selected-write", "verified-read", "active-read", "mode-read", "mode-write", "active-write", "remote-read"]
        let replacements = [
            StoredSelectionState(selected: 17, active: 30, mode: 1, flags: 32, remote: ""),
            .init(selected: -1, active: 16, mode: 18, flags: 32, remote: ""),
            .init(selected: 15, active: 28, mode: 28, flags: 0, remote: ""),
            .init(selected: 15, active: 29, mode: 35, flags: 32, remote: " "),
        ]
        var cases = 0
        for initial in [StoredSelectionState(selected: -1, active: 16, mode: 1), .init(selected: 15, active: 18, mode: 18)] {
            for event in events {
                for replacement in replacements {
                    let pair = fixtures(initial)
                    for fixture in pair {
                        var fired = false
                        fixture.onEvent = { [unowned fixture] name in
                            guard name == event, !fired else { return }
                            fired = true
                            fixture.stored = replacement
                        }
                        fixture.reconcile()
                        fixture.onEvent = nil
                    }
                    assertParity(pair)
                    cases += 1
                }
            }
        }
        return cases
    }
}
