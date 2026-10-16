import Foundation

@MainActor final class Context {
    var events: [String] = []
    var operationID: String? = "run"
    var applying = true
    var pid: Int32 = 101
    var livePID: Int32 = 101
    var isolated = [true, true]
    var isolatedIndex = 0
    var exclusive = true
    var state: [Int] = [7, 3, 7, 9, 8, 7, 101]
    var admitted: Session?
    var admittedPID: Int32?
    func reset() {
        events = []; isolatedIndex = 0; admitted = nil; admittedPID = nil
    }
    func readState(_ index: Int) -> Int {
        events.append("read.state.\(index)"); return state[index]
    }
    func writeState(_ index: Int, _ value: Int) {
        events.append("write.state.\(index)=\(value)"); state[index] = value
    }
}
@MainActor enum World { static var context = Context() }
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    let context = World.context
    context.events.append("lookup.\(String(cString: name))")
    return context.livePID
}
@MainActor final class Session {
    let context: Context
    let token: Int
    init(_ context: Context, token: Int = 42) { self.context = context; self.token = token }
    var pid: Int32 {
        context.events.append("session.pid.\(token)"); return context.pid
    }
    var creatingExtraThread: Bool {
        context.events.append("session.isolated.\(token)")
        let value = context.isolated[min(context.isolatedIndex, context.isolated.count - 1)]
        context.isolatedIndex += 1
        return value
    }
}
@MainActor final class Manager {
    let context: Context
    init(_ context: Context) { self.context = context }
    func beginExclusiveRemoteCall(label: String, expectedSession: Session) -> Bool {
        precondition(expectedSession.context === context)
        context.events.append("exclusive.\(label).\(expectedSession.token)")
        return context.exclusive
    }
}
struct Step { let flag: UInt32; let englishName: String }
@MainActor protocol Host {
    var context: Context { get }
    func consume(process: Session?, sessionError: String?, operationID: String, operationSpringBoardPID: Int32, step: Step)
}
extension Host {
    var activeOperationID: String? {
        context.events.append("read.operationID"); return context.operationID
    }
    var isApplying: Bool {
        context.events.append("read.applying"); return context.applying
    }
    var mgr: Manager { Manager(context) }
    func failBeforeNativeCall(_ reason: String) { context.events.append("fail.before.\(reason)") }
    func failAfterNativeCall(_ reason: String) { context.events.append("fail.after.\(reason)") }
    var retainedVerified: UInt32 {
        get { UInt32(context.readState(0)) }
        nonmutating set { context.writeState(0, Int(newValue)) }
    }
    var newlyApplied: UInt32 {
        get { UInt32(context.readState(1)) }
        nonmutating set { context.writeState(1, Int(newValue)) }
    }
    var activeFlagsRaw: Int {
        get { Int(context.readState(2)) }
        nonmutating set { context.writeState(2, Int(newValue)) }
    }
    var activeModeRaw: Int {
        get { Int(context.readState(3)) }
        nonmutating set { context.writeState(3, Int(newValue)) }
    }
    var activeIslandModeRaw: Int {
        get { Int(context.readState(4)) }
        nonmutating set { context.writeState(4, Int(newValue)) }
    }
    var activeDockModeRaw: Int {
        get { Int(context.readState(5)) }
        nonmutating set { context.writeState(5, Int(newValue)) }
    }
    var activeSpringBoardPID: Int {
        get { Int(context.readState(6)) }
        nonmutating set { context.writeState(6, Int(newValue)) }
    }
}
@main struct Runner {
    @MainActor static func main() {
        let old = PublicHost(Context()), owned = OwnedHost(Context())
        var count = 0, eventCount = 0
        func compare(present: Bool = true, error: String? = nil, operationPID: Int32 = 101,
                     flag: UInt32 = 2, name: String = "Dock") -> [String] {
            var snapshots: [[String]] = [], states: [[Int]] = []
            for host in [old as any Host, owned as any Host] {
                let context = host.context
                context.reset()
                World.context = context
                let session = Session(context)
                host.consume(process: present ? session : nil, sessionError: error,
                             operationID: "run", operationSpringBoardPID: operationPID,
                             step: Step(flag: flag, englishName: name))
                if let admitted = context.admitted { precondition(admitted === session, "Handle identity changed") }
                snapshots.append(context.events + ["result.\(context.admittedPID.map(String.init) ?? "nil")"])
                states.append(context.state)
            }
            precondition(snapshots[0] == snapshots[1], "Events mismatch \(count): \(snapshots)")
            precondition(states[0] == states[1], "State mismatch \(count)")
            count += 1; eventCount += old.context.events.count
            return old.context.events
        }
        func configure(_ action: (Context) -> Void) {
            for context in [old.context, owned.context] { action(context) }
        }
        // Independent anchors: stale responses do not read session/PID or change state.
        configure { $0.operationID = nil }
        precondition(compare() == ["read.operationID"])
        configure { $0.operationID = "run"; $0.applying = false }
        precondition(compare() == ["read.operationID", "read.applying"])
        configure { $0.applying = true }
        let accepted = compare()
        precondition(accepted == ["read.operationID", "read.applying", "session.pid.42",
                                 "lookup.SpringBoard", "session.isolated.42",
                                 "exclusive.Aura Dock run.42", "admitted.42.101"])
        precondition(old.context.admittedPID == 101)
        let before = compare(present: false, error: "ACCESS IS NOT READY")
        precondition(before == ["read.operationID", "read.applying", "fail.before.ACCESS IS NOT READY"])
        let transport = compare(present: false, error: "transport failed")
        precondition(transport == ["read.operationID", "read.applying", "read.state.0",
                                  "write.state.0=5", "fail.after.transport failed"])
        precondition(old.context.state[2...] == [7, 9, 8, 7, 101])
        configure { $0.state = [7, 3, 7, 9, 8, 7, 101]; $0.livePID = 202 }
        let replaced = compare()
        precondition(replaced.suffix(8).first == "write.state.0=0")
        precondition(old.context.state == [0, 0, 0, 0, 0, 0, 0])
        configure { $0.livePID = 101 }
        let errors: [String?] = [nil, "", "ACCESS IS NOT READY", "request still running",
                               "Safety Locked", "transport failed", "áccess is not ready"]
        for active in [nil, "stale", "run"] as [String?] {
            for applying in [false, true] {
                for pid: Int32 in [-1, 0, 101, 202] {
                    for current: Int32 in [-1, 101, 202] {
                        for operationPID: Int32 in [101, 202] {
                            for isolated in [[false, true], [true, false], [true, true]] {
                                for exclusive in [false, true] {
                                    for error in errors {
                                        for present in [false, true] {
                                            for mask in [0, 3, 7] {
                                                configure {
                                                    $0.operationID = active; $0.applying = applying
                                                    $0.pid = pid; $0.livePID = current; $0.isolated = isolated
                                                    $0.exclusive = exclusive; $0.state = [mask, 3, 7, 9, 8, 7, 101]
                                                }
                                                _ = compare(present: present, error: error, operationPID: operationPID,
                                                            flag: mask == 3 ? 1 : 2,
                                                            name: mask == 3 ? "Island" : "Dock")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Success, replacement and stale callback sequences share one host/context;
        // later stale callbacks must preserve whatever state the earlier rejection left.
        for _ in 0..<128 {
            configure {
                $0.operationID = "run"; $0.applying = true; $0.pid = 101; $0.livePID = 101
                $0.isolated = [true]; $0.exclusive = true; $0.state = [7, 3, 7, 9, 8, 7, 101]
            }
            _ = compare()
            configure { $0.livePID = 202 }
            _ = compare()
            configure { $0.operationID = "next" }
            precondition(compare() == ["read.operationID"])
            precondition(old.context.state == [0, 0, 0, 0, 0, 0, 0])
        }
        print("PASS: \(count) session scenarios, \(eventCount) ordered reads/effects; original handle identity preserved")
    }
}

