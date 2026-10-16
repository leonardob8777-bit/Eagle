import Foundation

typealias AuraStudioTarget = EagleAuraStudioTarget
@MainActor enum Trace {
    static var events: [String] = []
}
@MainActor enum Flag {
    static var island: UInt32 { Trace.events.append("flag.island"); return 1 }
    static var dock: UInt32 { Trace.events.append("flag.dock"); return 32 }
}
@MainActor final class Context {
    var raw: Int
    var availability: [Bool]
    var availabilityReads = 0
    init(raw: Int, availability: [Bool]) {
        self.raw = raw
        self.availability = availability
    }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    var selectedTargetRaw: Int {
        get { Trace.events.append("raw.read"); return context.raw }
        nonmutating set { Trace.events.append("raw.write:\(newValue)"); context.raw = newValue }
    }
    var islandProfileAvailable: Bool {
        Trace.events.append("available")
        defer { context.availabilityReads += 1 }
        return context.availability[min(context.availabilityReads, context.availability.count - 1)]
    }
}

@main struct TargetChecks {
    @MainActor static func main() async {
        let rawValues = [Int.min] + Array(-128...256) + [Int.max]
        precondition(EagleAuraStudioTarget.allCases.map(\.rawValue) == PublicTarget.allCases.map(\.rawValue))
        var scenarios = 0
        var reads = 0
        var events = 0
        for raw in rawValues {
            precondition(PublicTarget(rawValue: raw)?.id == EagleAuraStudioTarget(rawValue: raw)?.id)
            precondition(PublicTarget(rawValue: raw)?.title == EagleAuraStudioTarget(rawValue: raw)?.title)
            for availability in [[false], [true], [false, true, false, true], [true, false, true, false]] {
                let left = Context(raw: raw, availability: availability)
                let right = Context(raw: raw, availability: availability)
                let old = PublicHost(context: left)
                let new = OwnedHost(context: right)
                for action in 0..<12 {
                    let previousReads = left.availabilityReads
                    Trace.events = []
                    let expected: Int
                    if action % 2 == 0 { expected = old.selectedTarget.rawValue }
                    else { expected = Int(old.selectedFlags) }
                    let before = Trace.events
                    Trace.events = []
                    let actual: Int
                    if action % 2 == 0 { actual = new.selectedTarget.rawValue }
                    else { actual = Int(new.selectedFlags) }
                    precondition(expected == actual && before == Trace.events)
                    precondition(left.availabilityReads == right.availabilityReads)
                    precondition(left.raw == raw && right.raw == raw) // Fallback never rewrites preferences.
                    let isIsland = raw == 1 && availability[min(previousReads, availability.count - 1)]
                    precondition(actual == (action % 2 == 0 ? (isIsland ? 1 : 2) : (isIsland ? 1 : 32)))
                    var expectedTrace = ["raw.read"]
                    if raw == 1 { expectedTrace += ["available"] }
                    if action % 2 != 0 { expectedTrace += [isIsland ? "flag.island" : "flag.dock"] }
                    precondition(before == expectedTrace)
                    events += before.count
                    reads += 1
                }
                // Selecting a profile writes its original raw identifier, even if
                // unavailable; availability is checked lazily on the later read.
                for selected in [1, 2, 1, 2] {
                    Trace.events = []
                    old.selectedTarget = PublicTarget(rawValue: selected)!
                    let before = Trace.events
                    Trace.events = []
                    new.selectedTarget = EagleAuraStudioTarget(rawValue: selected)!
                    precondition(before == Trace.events && before == ["raw.write:\(selected)"])
                    precondition(left.raw == selected && right.raw == selected)
                    events += before.count
                }
                scenarios += 1
            }
        }
        for raw in [1, 2] {
            let old = PublicHost(context: Context(raw: -1, availability: [false]))
            let new = OwnedHost(context: Context(raw: -1, availability: [false]))
            Trace.events = []
            let expected = old.flag(for: PublicTarget(rawValue: raw)!)
            let before = Trace.events
            Trace.events = []
            let actual = new.flag(for: EagleAuraStudioTarget(rawValue: raw)!)
            precondition(expected == actual && before == Trace.events)
            precondition(before == [raw == 1 ? "flag.island" : "flag.dock"])
        }
        var injected = 0
        for island: UInt32 in [0, 1, 32, UInt32.max] {
            for dock: UInt32 in [0, 1, 32, UInt32.max] {
                for target in EagleAuraStudioTarget.allCases {
                    var calls: [String] = []
                    func readIsland() -> UInt32 { calls.append("island"); return island }
                    func readDock() -> UInt32 { calls.append("dock"); return dock }
                    let value = target.flag(islandFlag: readIsland(), dockFlag: readDock())
                    precondition(value == (target == .island ? island : dock))
                    precondition(calls == [target == .island ? "island" : "dock"])
                    injected += 1
                }
            }
        }
        let detached = await Task.detached {
            rawValues.map { raw in
                EagleAuraStudioTarget.storedSelection(rawValue: raw, islandProfileAvailable: { false })
            }
        }.value
        precondition(detached.allSatisfy { $0 == .dock })
        print("PASS: \(scenarios) selection scenarios, \(reads) repeated selection/flag reads, \(events) ordered events, \(injected) lazy flag cases and \(detached.count) detached fallbacks; raw IDs, no repair writes, unchanged setter")
    }
}
