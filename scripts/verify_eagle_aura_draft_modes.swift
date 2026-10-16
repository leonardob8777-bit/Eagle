import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum AuraStudioTarget: String { case island, dock }

@MainActor final class Context {
    var island: Int
    var dock: Int
    var target: AuraStudioTarget
    var pulse: Bool
    var rainbow: Bool
    let behavior: Int
    var events: [String] = []
    init(_ island: Int, _ dock: Int, _ target: AuraStudioTarget, _ bits: Int, _ behavior: Int) {
        self.island = island; self.dock = dock; self.target = target
        pulse = bits & 1 != 0; rainbow = bits & 2 != 0; self.behavior = behavior
    }
    var snapshot: String { "\(island)|\(dock)|\(target)" }
}

@MainActor protocol Host {
    var context: Context { get }
    func act(_ operation: Int) -> [Int]
}

extension Host {
    var selectedTarget: AuraStudioTarget {
        let value = context.target
        context.events.append("target:\(value)")
        if context.behavior & 1 != 0 { context.target = value == .island ? .dock : .island }
        return value
    }
    var islandModeRaw: Int {
        get { context.events.append("islandRead:\(context.island)"); return context.island }
        nonmutating set { context.events.append("islandWrite:\(newValue)"); context.island = newValue }
    }
    var dockModeRaw: Int {
        get { context.events.append("dockRead:\(context.dock)"); return context.dock }
        nonmutating set { context.events.append("dockWrite:\(newValue)"); context.dock = newValue }
    }
    func policyAllows(_ mode: AuraStudioMode, for target: AuraStudioTarget) -> Bool {
        context.events.append("allow:\(mode.rawValue):\(target)")
        return EagleAuraStudioModePolicy.allows(mode, isIsland: target == .island,
            pulseAllowed: { context.events.append("pulse"); return context.pulse },
            rainbowAllowed: { context.events.append("rainbow"); return context.rainbow })
    }
    func normalizedMode(rawValue: Int, for target: AuraStudioTarget) -> AuraStudioMode {
        context.events.append("normalize:\(rawValue):\(target)")
        let mode = EagleAuraStudioModePolicy.normalizedMode(rawValue: rawValue,
            allows: { policyAllows($0, for: target) })
        // Deliberately adversarial callback side effects reveal snapshot/read-order changes.
        if context.behavior & 2 != 0 {
            context.island = target == .island ? mode.rawValue : -1
            context.dock = target == .dock ? mode.rawValue : -1
        }
        return mode
    }
}

@main struct Main {
    @MainActor static func main() {
        let values = [Int.min, -1, 0, 1, 2, 3, 4, 8, 14, 36, Int.max]
        var scenarios = 0, actions = 0, events = 0
        for island in values {
            for dock in values {
                for target in [AuraStudioTarget.island, .dock] {
                    for bits in 0..<4 {
                        for behavior in 0..<4 {
                            let a = PublicHost(context: Context(island, dock, target, bits, behavior))
                            let b = OwnedHost(context: Context(island, dock, target, bits, behavior))
                            // Read, enumerate, normalize both, read again, set every style,
                            // then normalize twice with a feature-policy change in between.
                            for operation in [0, 1, 2, 3, 4, 0, 1] + Array(5..<16) + [4, 4, 0, 1] {
                                a.context.events = []; b.context.events = []
                                let beforeIsland = b.context.island, beforeDock = b.context.dock
                                let beforeTarget = b.context.target
                                let old = a.act(operation), new = b.act(operation)
                                precondition(old == new && a.context.snapshot == b.context.snapshot)
                                precondition(a.context.events == b.context.events)
                                if behavior == 0 {
                                    let writes = b.context.events.filter { $0.contains("Write:") }
                                    if operation < 4 {
                                        precondition(writes.isEmpty)
                                        precondition(b.context.island == beforeIsland && b.context.dock == beforeDock)
                                    } else if operation >= 5 {
                                        let mode = AuraStudioMode.allCases[operation - 5]
                                        let allowed = mode == .glow || (mode == .pulse && b.context.pulse) ||
                                            (mode == .rainbow && beforeTarget == .island && b.context.rainbow)
                                        precondition(writes.count == (allowed ? 1 : 0))
                                        precondition(beforeTarget == .island ? b.context.dock == beforeDock : b.context.island == beforeIsland)
                                    } else {
                                        precondition(!writes.contains("islandWrite:\(beforeIsland)"))
                                        precondition(!writes.contains("dockWrite:\(beforeDock)"))
                                    }
                                }
                                if operation == 15 {
                                    a.context.pulse.toggle(); b.context.pulse.toggle()
                                    a.context.rainbow.toggle(); b.context.rainbow.toggle()
                                }
                                actions += 1; events += b.context.events.count
                            }
                            scenarios += 1
                        }
                    }
                }
            }
        }
        print("PASS: \(scenarios) public/owned draft sequences, \(actions) actions, \(events) exact ordered events; independent profile/no-write/guard checks")
    }
}
