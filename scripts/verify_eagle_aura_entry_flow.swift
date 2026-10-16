import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum AuraStudioTarget: Int { case island = 1, dock = 2 }
@MainActor final class Context {
    // legacy, Island draft, Dock draft, selected target
    var ints = [1, 4, 2, 1]
    // migrated, available, safety locked, blocked, applying, contract valid
    var bools = [false, true, false, false, false, true]
    var events: [String] = []
    var hook = 0
    var pulseAllowed = true
    func readInt(_ i: Int) -> Int { events.append("int:\(i):\(ints[i])"); return ints[i] }
    func writeInt(_ i: Int, _ v: Int) {
        ints[i] = v; events.append("writeInt:\(i):\(v)")
        if hook == 3 && i == 1 { ints[0] = 3 }
    }
    func readBool(_ i: Int) -> Bool { events.append("bool:\(i):\(bools[i])"); return bools[i] }
    func writeBool(_ i: Int, _ v: Bool) { bools[i] = v; events.append("writeBool:\(i):\(v)") }
}
@MainActor enum Runtime { static var context: Context? }
@MainActor struct Manager {
    let context: Context
    var rcSafetyLocked: Bool { context.readBool(2) }
}
@MainActor enum AuraStudioNativeContract {
    static var invariantsHold: Bool { Runtime.context!.readBool(5) }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ event: String, _ detail: String) { Runtime.context!.events.append("log:\(event):\(detail)") }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    var independentProfilesMigrated: Bool { get { context.readBool(0) } nonmutating set { context.writeBool(0, newValue) } }
    var legacySelectedModeRaw: Int { context.readInt(0) }
    var islandModeRaw: Int { get { context.readInt(1) } nonmutating set { context.writeInt(1, newValue) } }
    var dockModeRaw: Int { get { context.readInt(2) } nonmutating set { context.writeInt(2, newValue) } }
    var selectedTargetRaw: Int { get { context.readInt(3) } nonmutating set { context.writeInt(3, newValue) } }
    var islandProfileAvailable: Bool { context.readBool(1) }
    var applySafetyBlocked: Bool { get { context.readBool(3) } nonmutating set { context.writeBool(3, newValue) } }
    var isApplying: Bool { context.readBool(4) }
    var mgr: Manager { Manager(context: context) }
    var auraEngineBuild: String { context.events.append("engineBuild"); return "fixture-engine" }
    func normalizeDraftModesForPolicy() {
        context.events.append("normalize")
        func normalized(_ raw: Int, _ island: Bool) -> AuraStudioMode {
            EagleAuraStudioModePolicy.normalizedMode(rawValue: raw, allows: {
                $0 == .glow || ($0 == .pulse && context.pulseAllowed) || ($0 == .rainbow && island)
            })
        }
        let island = normalized(islandModeRaw, true)
        let dock = normalized(dockModeRaw, false)
        if islandModeRaw != island.rawValue { islandModeRaw = island.rawValue }
        if dockModeRaw != dock.rawValue { dockModeRaw = dock.rawValue }
        if context.hook == 1 { context.bools[1] = false }
    }
    func reconcilePersistedActiveState() {
        context.events.append("reconcile")
        if context.hook == 2 { context.bools[2] = true }
    }
}

@main struct Check {
    @MainActor static func main() {
        let a = Context(), b = Context()
        let old = PublicHost(context: a), owned = OwnedHost(context: b)
        var scenarios = 0, actions = 0, events = 0
        let legacyModes = [Int.min, -1, 0, 1, 2, 3, 4, 8, 14, 15, 35, Int.max]
        for legacy in legacyModes { for migrated in [false, true] {
            for selected in [Int.min, 0, 1, 2, Int.max] { for available in [false, true] {
                for locked in [false, true] { for busy in [false, true] {
                    for contract in [false, true] { for hook in 0...3 {
                        a.ints = [legacy, 4, 2, selected]; b.ints = a.ints
                        a.bools = [migrated, available, locked, false, busy, contract]; b.bools = a.bools
                        a.hook = hook; b.hook = hook; a.pulseAllowed = true; b.pulseAllowed = true
                        for op in 0..<4 {
                            if op == 2 { a.pulseAllowed = false; b.pulseAllowed = false }
                            let beforeInts = b.ints, beforeBools = b.bools
                            a.events = []; b.events = []
                            Runtime.context = a
                            if op % 2 == 0 { old.appear() } else { old.channel() }
                            Runtime.context = b
                            if op % 2 == 0 { owned.appear() } else { owned.channel() }
                            precondition(a.events == b.events && a.ints == b.ints && a.bools == b.bools)
                            let trace = b.events
                            if op % 2 == 0 {
                                precondition(b.bools[0])
                                precondition(trace.filter { $0 == "normalize" }.count == 1)
                                precondition(trace.filter { $0 == "reconcile" }.count == 1)
                                precondition(trace.firstIndex(of: "normalize")! < trace.firstIndex(of: "reconcile")!)
                                let reconcile = trace.firstIndex(of: "reconcile")!
                                precondition(trace[reconcile + 1].hasPrefix("bool:2:"))
                                if b.bools[2] { precondition(b.bools[3]) }
                                if !beforeBools[0] {
                                    let parsed = AuraStudioMode(rawValue: beforeInts[0]) ?? .glow
                                    precondition(trace[2] == "writeInt:1:\(parsed.rawValue)")
                                    precondition(trace[3] == "writeInt:2:\(parsed == .tint ? 1 : parsed.rawValue)")
                                    precondition(trace[4] == "writeBool:0:true")
                                } else {
                                    precondition(!trace.contains("writeBool:0:true"))
                                    precondition(!trace.contains { $0.hasPrefix("int:0:") })
                                }
                                if !b.bools[1] && beforeInts[3] == 1 { precondition(b.ints[3] == 2) }
                                if b.bools[1] { precondition(!trace.contains { $0.hasPrefix("int:3:") }) }
#if DEBUG
                                precondition(trace.contains("bool:5:\(contract)"))
                                precondition(trace.contains("log:contract.self-test:result=failed engine=fixture-engine") == !contract)
#else
                                precondition(!trace.contains { $0.hasPrefix("bool:5:") || $0.hasPrefix("log:") })
#endif
                            } else if busy {
                                precondition(trace == ["bool:4:true"])
                                precondition(b.ints == beforeInts && b.bools == beforeBools)
                            } else {
                                precondition(trace.first == "bool:4:false" && trace[1] == "normalize")
                                precondition(!trace.contains("reconcile"))
                                precondition(!trace.contains { $0.hasPrefix("bool:2:") })
                            }
                            actions += 1; events += trace.count
                        }
                        scenarios += 1
                    } }
                } }
            } }
        } }
        Runtime.context = nil
#if DEBUG
        let configuration = "DEBUG (with original contract check)"
#else
        let configuration = "Release (no debug contract check)"
#endif
        print("PASS: \(scenarios) entry/channel sequences, \(actions) actions, \(events) exact events; migration/fallback/safety/busy guards; \(configuration)")
    }
}
