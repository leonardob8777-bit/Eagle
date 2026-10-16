import Foundation

enum Flag {
    static let island: UInt32 = 1
    static let dock: UInt32 = 32
    static let supported = island | dock
}
@MainActor final class Context {
    var values = [33, 4, 1, 2, 35, 100]
    var deviceFlags: UInt32 = 33
    var currentPID: Int32 = 100
    var events: [String] = []
    var hook = 0
    func read(_ field: Int) -> Int {
        events.append("read:\(field):\(values[field])")
        return values[field]
    }
    func write(_ field: Int, _ value: Int) {
        values[field] = value
        events.append("write:\(field):\(value):\(values)")
        if hook == 3 && field == 2 { values[1] = 9 }
    }
    func log(_ event: String, _ detail: String) {
        events.append("log:\(event):\(detail):\(values)")
        if hook == 2 { values[1] = 8; values[3] = 14 }
    }
}
@MainActor enum Runtime { static var context: Context? }
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    let c = Runtime.context!
    precondition(String(cString: name) == "SpringBoard")
    c.events.append("lookup")
    return c.currentPID
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ event: String, _ detail: String) { Runtime.context!.log(event, detail) }
}
@MainActor struct Compatibility {
    let context: Context
    var diagnosticsToken: String {
        context.events.append("token"); return "fixture-device"
    }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    var deviceSupportedFlags: UInt32 {
        context.events.append("deviceFlags")
        if context.hook == 1 { context.values[0] = 255 }
        return context.deviceFlags
    }
    var islandCompatibility: Compatibility {
        context.events.append("compatibility")
        return Compatibility(context: context)
    }
}

@main struct Check {
    @MainActor static func main() {
        let a = Context(), b = Context()
        let old = PublicHost(context: a), owned = OwnedHost(context: b)
        var runs = 0, events = 0, scenarios = 0
        let masks = [Int.min, -1, 0, 1, 2, 32, 33, 64, 255, Int(UInt32.max), Int(UInt32.max) + 1, Int.max]
        let savedPIDs = [-1, 0, 100, 101, Int(Int32.max)]
        let suppliedPIDs: [Int32?] = [nil, 0, 100, 101, Int32.max]
        func compare(_ pid: Int32?) {
            a.events = []; b.events = []
            Runtime.context = a; old.run(pid)
            Runtime.context = b; owned.run(pid)
            precondition(a.events == b.events && a.values == b.values)
            precondition(b.events.filter { $0 == "lookup" }.count == (pid == nil ? 1 : 0))
            precondition(b.events.first == (pid == nil ? "lookup" : a.events.first!))
            runs += 1; events += b.events.count
        }
        func configure(_ mask: Int, _ device: UInt32, _ savedPID: Int, _ legacy: Int, _ modes: (Int, Int), _ hook: Int = 0) {
            a.values = [mask, legacy, modes.0, modes.1, 35, savedPID]
            b.values = a.values; a.deviceFlags = device; b.deviceFlags = device
            a.hook = hook; b.hook = hook
        }
        for mask in masks { for device: UInt32 in [0, 1, 32, 33] {
            for savedPID in savedPIDs { for suppliedPID in suppliedPIDs {
                for legacy in [0, 4, 36] { for modes in [(0, 0), (1, 0), (0, 2), (4, 2)] {
                    configure(mask, device, savedPID, legacy, modes)
                    let initial = b.values
                    compare(suppliedPID)
                    let raw = EagleStoredThemeValues.flags(mask) & 33
                    let saved = raw & device
                    let valid = saved != 0 && savedPID > 0 && savedPID == Int(suppliedPID ?? 100)
                    if !valid {
                        precondition(b.values == [0, 0, 0, 0, 0, 0])
                        let writes = b.events.filter { $0.hasPrefix("write:") }.suffix(6)
                        precondition(Array(writes).enumerated().allSatisfy { $0.element.hasPrefix("write:\($0.offset):0:") })
                    } else {
                        precondition(b.values[5] == savedPID)
                        precondition(b.values[0] == (raw == saved ? initial[0] : Int(saved)))
                        if saved & 1 == 0 {
                            precondition(b.values[1] == 0 && b.values[2] == 0)
                        } else {
                            precondition(b.values[2] == (raw != saved || modes.0 == 0 ? legacy : modes.0))
                        }
                        if saved & 32 == 0 {
                            precondition(b.values[3] == 0 && b.values[4] == 0)
                        } else {
                            precondition(b.values[4] == 35)
                            precondition(b.values[3] == (modes.1 == 0 ? (saved & 1 == 0 ? 0 : legacy) : modes.1))
                        }
                    }
                    let pruned = b.events.contains { $0.hasPrefix("log:state.hardware-pruned:") }
                    let expired = b.events.contains { $0.hasPrefix("log:state.expired:") }
                    precondition(pruned == (raw != saved))
                    precondition(expired == (saved != 0 && !valid))
                    precondition(b.events.contains("compatibility") == pruned && b.events.contains("token") == pruned)
                    // Reopening repeats the same public reset/migration checks.
                    compare(suppliedPID)
                    scenarios += 1
                } }
            } }
        } }
        let matrixScenarios = scenarios
        for mask in 0..<256 {
            configure(mask, 33, 100, 4, (0, 0)); compare(100)
        }
        for hook in 1...3 { for mask in [0, 1, 32, 33, 255] {
            for device: UInt32 in [1, 32, 33] { for pid: Int32 in [100, 101] {
                configure(mask, device, 100, 4, (0, 0), hook)
                compare(pid); scenarios += 1
            } }
        } }
        Runtime.context = nil
        print("PASS: \(matrixScenarios) saved-state scenarios (each reopened), 256 mask cases, \(scenarios - matrixScenarios) changing-callback cases; \(runs) runs and \(events) exact read/write/log events")
    }
}
