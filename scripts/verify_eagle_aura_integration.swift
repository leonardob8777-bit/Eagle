import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum AuraStudioTarget: Int { case island = 1, dock = 2 }
enum Availability { case supported, unsupported, unknown }
enum Flag {
    static let island: UInt32 = 1
    static let dock: UInt32 = 32
    static let supported: UInt32 = 33
}
@MainActor final class Context {
    var ints: [String: Int] = [:]
    var doubles: [String: Double] = [:]
    var bools: [String: Bool] = [:]
    var availability = Availability.supported
    var channel = 0
    var spanish = false
    var locked = false
    var currentPID: Int32 = 100
    var events: [String] = []
    func readInt(_ key: String) -> Int { events.append("read:\(key)"); return ints[key]! }
    func readDouble(_ key: String) -> Double { events.append("read:\(key)"); return doubles[key]! }
    func readBool(_ key: String) -> Bool { events.append("read:\(key)"); return bools[key]! }
    func writeInt(_ key: String, _ v: Int) { ints[key] = v; events.append("write:\(key):\(v)") }
    func writeDouble(_ key: String, _ v: Double) { doubles[key] = v; events.append("write:\(key):\(v.bitPattern)") }
    func writeBool(_ key: String, _ v: Bool) { bools[key] = v; events.append("write:\(key):\(v)") }
}
@MainActor enum Runtime { static var context: Context? }
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        let c = Runtime.context!; c.events.append("text:\(en)|\(es)"); return c.spanish ? es : en
    }
}
extension EagleAuraStudioMode {
    @MainActor var title: String { title(localizedText: { LaraL10n.text(en: $0, es: $1) }) }
}
@MainActor enum EagleFeaturePolicy {
    enum Feature { case auraPulse, auraRainbow }
    static func allows(_ feature: Feature, channel: Int) -> Bool {
        Runtime.context!.events.append("policy:\(feature):\(channel)")
        return channel == 1
    }
}
@MainActor struct Compatibility {
    let context: Context
    var availability: Availability { context.events.append("availability"); return context.availability }
    var diagnosticsToken: String { context.events.append("token"); return "integrated-fixture" }
}
@MainActor struct Manager {
    let context: Context
    var rcSafetyLocked: Bool { context.events.append("safety"); return context.locked }
}
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    precondition(String(cString: name) == "SpringBoard")
    let c = Runtime.context!; c.events.append("lookup"); return c.currentPID
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ event: String, _ detail: String) { Runtime.context!.events.append("log:\(event):\(detail)") }
}
@MainActor enum AuraStudioNativeContract {
    static var invariantsHold: Bool { Runtime.context!.events.append("contract"); return true }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    var islandCompatibility: Compatibility { Compatibility(context: context) }
    var releaseChannel: Int { context.events.append("channel"); return context.channel }
    var mgr: Manager { Manager(context: context) }
    var auraEngineBuild: String { "fixture-engine" }
}

@main struct Check {
    @MainActor static func main() {
        let a = Context(), b = Context()
        let old = PublicHost(context: a), owned = OwnedHost(context: b)
        var scenarios = 0, actions = 0, events = 0
        let sequence = [0, 1, 9, 2, 3, 4, 5, 6, 4, 7, 1, 0, 10, 4, 7, 1, 8, 4, 0, 9]
        for legacy in [-1, 1, 2, 3, 4, 8, 35] { for availability: Availability in [.supported, .unsupported, .unknown] {
            for channel in [0, 1] { for migrated in [false, true] { for mask in [0, 1, 32, 33] {
                for spanish in [false, true] {
                    a.ints = ["legacySelectedModeRaw": legacy, "islandModeRaw": 4, "dockModeRaw": 2,
                              "selectedTargetRaw": 1, "activeFlagsRaw": mask, "activeModeRaw": 4,
                              "activeIslandModeRaw": 0, "activeDockModeRaw": 0,
                              "activeDockGalleryStyleRaw": 35, "activeSpringBoardPID": 100,
                              "activeIslandRed": 26, "activeIslandGreen": 199, "activeIslandBlue": 255,
                              "activeDockRed": 158, "activeDockGreen": 64, "activeDockBlue": 255]
                    a.doubles = ["islandRed": 0.1, "islandGreen": 0.78, "islandBlue": 1,
                                 "dockRed": 0.62, "dockGreen": 0.25, "dockBlue": 1]
                    a.bools = ["independentProfilesMigrated": migrated, "applySafetyBlocked": false, "isApplying": false]
                    b.ints = a.ints; b.doubles = a.doubles; b.bools = a.bools
                    for c in [a, b] {
                        c.availability = availability; c.channel = channel; c.spanish = spanish
                        c.locked = false; c.currentPID = 100
                    }
                    for (index, op) in sequence.enumerated() {
                        if index == 9 { for c in [a, b] { c.bools["isApplying"] = true; c.channel = 1 - channel } }
                        if index == 11 { for c in [a, b] { c.bools["isApplying"] = false } }
                        if index == 14 { for c in [a, b] { c.channel = 0; c.spanish.toggle() } }
                        if index == 16 { for c in [a, b] { c.currentPID = 101; c.locked = true } }
                        a.events = []; b.events = []
                        let beforeInts = b.ints, beforeDoubles = b.doubles, beforeBools = b.bools
                        Runtime.context = a; let publicResult = old.act(op)
                        Runtime.context = b; let ownedResult = owned.act(op)
                        precondition(publicResult == ownedResult && a.events == b.events)
                        precondition(a.ints == b.ints && a.doubles == b.doubles && a.bools == b.bools)
                        if [1, 4, 9].contains(op) {
                            precondition(b.ints == beforeInts && b.doubles == beforeDoubles && b.bools == beforeBools)
                        }
                        if op == 6 {
                            for key in ["islandRed", "islandGreen", "islandBlue"] { precondition(b.doubles[key] == beforeDoubles[key]) }
                        }
                        if index == 9 { precondition(b.events == ["read:isApplying"]) }
                        if op == 8 { precondition(b.ints["activeFlagsRaw"] == 0 && !b.events.contains("lookup")) }
                        if index == 18 { precondition(b.bools["applySafetyBlocked"] == true) }
                        actions += 1; events += b.events.count
                    }
                    scenarios += 1
                }
            } } }
        } }
        Runtime.context = nil
        print("PASS: \(scenarios) integrated Aura journeys, \(actions) actions, \(events) exact events; entry/edit/palette/status/channel/reopen/session expiry; no native calls")
    }
}
