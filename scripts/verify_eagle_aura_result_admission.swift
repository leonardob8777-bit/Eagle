import Foundation

@MainActor final class Context {
    var events: [String] = []
    var operationID: String? = "run"
    var applying = true
    var finished = false
    var livePID: Int32 = 101
    var healthy = true
    var timedOut = [false, false]
    var timeoutIndex = 0
    var state = [7, 3, 7, 9, 8, 7, 101]
    var consumed = 0
    var spanish = false
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
@MainActor enum AuraStudioDiagnostics {
    static func log(_ event: String, _ detail: String) {
        World.context.events.append("log.\(event).\(detail)")
    }
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        World.context.events.append("localized")
        return World.context.spanish ? es : en
    }
}
@MainActor final class Session {
    let context: Context
    init(_ context: Context) { self.context = context }
    var isHealthy: Bool {
        context.events.append("read.healthy"); return context.healthy
    }
    var lastCallTimedOut: Bool {
        context.events.append("read.timeout")
        let result = context.timedOut[min(context.timeoutIndex, context.timedOut.count - 1)]
        context.timeoutIndex += 1
        return result
    }
}
@MainActor struct Work {
    let name: String
    let context: Context
    func cancel() { context.events.append("cancel.\(name)") }
}
@MainActor struct Manager {
    let context: Context
    func endExclusiveRemoteCall(label: String) { context.events.append("end.\(label)") }
}
struct Step { let flag: UInt32; let englishName: String; let spanishName: String }
@MainActor protocol Host {
    var context: Context { get }
    func consume(process: Session, processError: String?, result: Int32, operationID: String,
                 operationSpringBoardPID: Int32, targetPID: Int32, springBoardPID: Int32, step: Step)
}
extension Host {
    var activeOperationID: String? {
        context.events.append("read.operationID"); return context.operationID
    }
    var isApplying: Bool {
        context.events.append("read.applying"); return context.applying
    }
    var nativeFinished: Bool {
        get { context.events.append("read.finished"); return context.finished }
        nonmutating set { context.events.append("write.finished.\(newValue)"); context.finished = newValue }
    }
    var mgr: Manager { Manager(context: context) }
    var softProgressWork: Work { Work(name: "soft", context: context) }
    var hardDeadlineWork: Work { Work(name: "hard", context: context) }
    func failAfterNativeCall(_ reason: String, result: Int32? = nil, userDetail: String? = nil) {
        context.events.append("fail.after.\(reason).\(result.map(String.init) ?? "nil").\(userDetail ?? "nil")")
    }
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
        func configure(_ action: (Context) -> Void) {
            for context in [old.context, owned.context] { action(context) }
        }
        func compare(error: String? = nil, result: Int32 = 2, operationPID: Int32 = 101,
                     targetPID: Int32 = 101, observedPID: Int32 = 101,
                     flag: UInt32 = 2, name: String = "Dock", spanishName: String = "Dock") -> [String] {
            var snapshots: [[String]] = [], states: [[Int]] = []
            for host in [old as any Host, owned as any Host] {
                let context = host.context
                context.events = []; context.timeoutIndex = 0
                World.context = context
                host.consume(process: Session(context), processError: error, result: result,
                             operationID: "run", operationSpringBoardPID: operationPID,
                             targetPID: targetPID, springBoardPID: observedPID,
                             step: Step(flag: flag, englishName: name, spanishName: spanishName))
                snapshots.append(context.events + ["finished.\(context.finished)", "consumed.\(context.consumed)"])
                states.append(context.state)
            }
            precondition(snapshots[0] == snapshots[1], "Result event mismatch \(count): \(snapshots)")
            precondition(states[0] == states[1], "Result state mismatch \(count)")
            count += 1; eventCount += old.context.events.count
            return old.context.events
        }
        // Golden anchors include lookup before staleness, exact cancellation order,
        // and the inherited late-response path (no new timer cancellation).
        precondition(compare() == [
            "lookup.SpringBoard", "read.operationID", "read.applying", "read.finished",
            "write.finished.true", "cancel.soft", "cancel.hard", "end.Aura Dock run",
            "read.healthy", "read.timeout", "consume.2"])
        let duplicate = compare()
        precondition(duplicate == [
            "lookup.SpringBoard", "read.operationID", "read.applying", "read.finished",
            "log.step.native.late.op=run module=Dock result=2", "end.Aura Dock run"])
        precondition(old.context.consumed == 1)
        configure { $0.operationID = nil; $0.livePID = 202 }
        _ = compare()
        precondition(old.context.state == [7, 3, 0, 0, 0, 0, 0])
        configure {
            $0.operationID = "run"; $0.livePID = 101; $0.finished = false
            $0.state = [7, 3, 7, 9, 8, 7, 101]; $0.healthy = false; $0.timedOut = [true]
        }
        let unhealthy = compare(error: "")
        precondition(!unhealthy.contains("read.timeout"), "Empty explicit error must avoid fallback timeout read")
        precondition(old.context.state[0] == 5)
        let errors: [String?] = [nil, "", "transport failed", " "]
        let results: [Int32] = [-26, -17, -16, -15, -12, -1, 0, 1, 2, 3, .max]
        for active in [nil, "stale", "run"] as [String?] {
            for applying in [false, true] {
                for finished in [false, true] {
                    for current: Int32 in [-1, 101, 202] {
                        for observed: Int32 in [-1, 101, 202] {
                            for operationPID: Int32 in [101, 202] {
                                for target: Int32 in [101, 202] {
                                    for healthy in [false, true] {
                                        for timeouts in [[false, true], [true, false]] {
                                            for error in errors {
                                                for result in results {
                                                    configure {
                                                        $0.operationID = active; $0.applying = applying
                                                        $0.finished = finished; $0.livePID = current; $0.healthy = healthy
                                                        $0.timedOut = timeouts; $0.consumed = 0
                                                        $0.spanish = result % 2 == 0; $0.state = [7, 3, 7, 9, 8, 7, 101]
                                                    }
                                                    _ = compare(error: error, result: result, operationPID: operationPID,
                                                                targetPID: target, observedPID: observed,
                                                                flag: result % 2 == 0 ? 2 : 1,
                                                                name: result % 2 == 0 ? "Dock" : "Island",
                                                                spanishName: result % 2 == 0 ? "Dock" : "Isla")
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
        }
        // A result is accepted once only, across repeat deliveries and a process replacement.
        for mask in [0, 1, 2, 3, 7] {
            configure {
                $0.operationID = "run"; $0.applying = true; $0.finished = false
                $0.livePID = 101; $0.healthy = true; $0.timedOut = [false]; $0.consumed = 0
                $0.state = [mask, 3, 7, 9, 8, 7, 101]
            }
            _ = compare()
            _ = compare()
            configure { $0.livePID = 202 }
            _ = compare()
            precondition(old.context.consumed == 1)
            precondition(old.context.state == [mask, 3, 0, 0, 0, 0, 0])
        }
        print("PASS: \(count) result scenarios, \(eventCount) ordered reads/effects; duplicate/PID/health rejection preserved")
    }
}

