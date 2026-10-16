import Foundation

@MainActor final class Context {
    var events: [String] = []
    var activeID: String? = "run"
    var applying = true
    var finished = false
    var deadline = false
    var safetyBlocked = false
    var gateLocked = false
    var stage = ""
    var stepIndex = 0
    var livePID: Int32 = 101
    var healthy = true
    var timedOut = false
    var spanish = false
    var state = [7, 3, 7, 9, 8, 7, 101]
    var consumed = 0
    var nextSteps: [Int] = []
    var completions: [Bool] = []
    var now = 0
    var jobs: [(Int, DispatchWorkItem)] = []
    var workCount = 0
    var soft: DispatchWorkItem?
    var hard: DispatchWorkItem?
    var progressSchedule: EagleAuraStudioProgressSchedule<DispatchWorkItem>?
    var schedulingDelay = 0
    func readState(_ index: Int) -> Int {
        events.append("read.state.\(index)"); return state[index]
    }
    func writeState(_ index: Int, _ value: Int) {
        events.append("write.state.\(index)=\(value)"); state[index] = value
    }
    func advanceClock(to target: Int) {
        precondition(target >= now)
        while let index = jobs.indices.filter({ jobs[$0].0 <= target }).min(by: { jobs[$0].0 < jobs[$1].0 }) {
            let (time, work) = jobs.remove(at: index)
            now = time
            events.append("clock.\(time)")
            work.perform()
        }
        now = target
    }
    var snapshot: [String] {
        events + [String(describing: state), stage, "step.\(stepIndex)", "finished.\(finished)",
                  "deadline.\(deadline)", "blocked.\(safetyBlocked)", "gate.\(gateLocked)",
                  "consumed.\(consumed)", "next.\(nextSteps)", "complete.\(completions)"]
    }
}
@MainActor enum World { static var context = Context() }
@MainActor struct ClockInstant {
    let value: Int
    static func now() -> Self { Self(value: World.context.now) }
    static func + (lhs: Self, rhs: Int) -> Self { Self(value: lhs.value + rhs) }
    static func + (lhs: Self, rhs: Double) -> Self {
        precondition(rhs == Double(Int(rhs)))
        return Self(value: lhs.value + Int(rhs))
    }
}
@MainActor final class DispatchWorkItem {
    let block: () -> Void
    let context: Context
    let id: Int
    var cancelled = false
    init(block: @escaping () -> Void) {
        self.block = block; context = World.context
        id = context.workCount; context.workCount += 1
        context.events.append("work.created.\(id)")
    }
    func cancel() { cancelled = true; context.events.append("cancel.\(id)") }
    func perform() {
        if cancelled { context.events.append("skip.\(id)") }
        else { context.events.append("fire.\(id)"); block() }
    }
}
@MainActor struct DispatchQueue {
    static var main: Self { Self() }
    func asyncAfter(deadline: ClockInstant, execute: DispatchWorkItem) {
        let context = World.context
        context.events.append("schedule.\(execute.id).\(deadline.value)")
        context.jobs.append((deadline.value, execute))
        if execute.id == 0 { context.now += context.schedulingDelay }
    }
}
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    let context = World.context
    context.events.append("lookup.\(String(cString: name))"); return context.livePID
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        World.context.events.append("localized")
        return World.context.spanish ? es : en
    }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ name: String, _ value: String) {
        World.context.events.append("log.\(name).\(value)")
    }
}
@MainActor enum AuraStudioApplyGate {
    static func lock() { World.context.events.append("gate.lock"); World.context.gateLocked = true }
}
@MainActor struct Manager {
    let context: Context
    func quarantineRemoteCall(reason: String) { context.events.append("quarantine.\(reason)") }
    func endExclusiveRemoteCall(label: String) { context.events.append("end.\(label)") }
}
@MainActor final class Session {
    let context: Context
    init(_ context: Context) { self.context = context }
    var isHealthy: Bool { context.events.append("read.healthy"); return context.healthy }
    var lastCallTimedOut: Bool { context.events.append("read.timeout"); return context.timedOut }
}
@MainActor protocol Host {
    var context: Context { get }
    func begin(index: Int, steps: [EagleAuraStudioOperationStep], operationID: String)
    func start(operationID: String, step: EagleAuraStudioOperationStep, operation: EagleAuraStudioOperation, targetPID: Int32)
    func advance(index: Int)
    func receive(process: Session, processError: String?, result: Int32, operationID: String,
                 operationSpringBoardPID: Int32, targetPID: Int32, springBoardPID: Int32, step: EagleAuraStudioOperationStep)
}
extension Host {
    var activeOperationID: String? { context.events.append("read.operationID"); return context.activeID }
    var isApplying: Bool { context.events.append("read.applying"); return context.applying }
    var nativeFinished: Bool {
        get { context.events.append("read.finished"); return context.finished }
        nonmutating set { context.events.append("write.finished.\(newValue)"); context.finished = newValue }
    }
    var hardDeadlineExceeded: Bool {
        get { context.events.append("read.deadline"); return context.deadline }
        nonmutating set { context.events.append("write.deadline.\(newValue)"); context.deadline = newValue }
    }
    var applySafetyBlocked: Bool {
        get { context.safetyBlocked }
        nonmutating set { context.events.append("write.safety.\(newValue)"); context.safetyBlocked = newValue }
    }
    var applyStage: String {
        get { context.stage }
        nonmutating set { context.events.append("stage.\(newValue)"); context.stage = newValue }
    }
    var operationStepIndex: Int {
        get { context.stepIndex }
        nonmutating set { context.events.append("stepIndex.\(newValue)"); context.stepIndex = newValue }
    }
    var mgr: Manager { Manager(context: context) }
    var softProgressWork: DispatchWorkItem { context.soft! }
    var hardDeadlineWork: DispatchWorkItem { context.hard! }
    var progressSchedule: EagleAuraStudioProgressSchedule<DispatchWorkItem> { context.progressSchedule! }
    func completeSuccess(deadlineWarning: Bool = false) {
        context.events.append("complete.\(deadlineWarning)"); context.completions.append(deadlineWarning)
    }
    func runStep(_ index: Int) { context.events.append("next.\(index)"); context.nextSteps.append(index) }
    func failAfterNativeCall(_ reason: String, result: Int32? = nil, userDetail: String? = nil) {
        context.events.append("failure.\(reason).\(result.map(String.init) ?? "nil").\(userDetail ?? "nil")")
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
enum Action { case time(Int), result, stale, stopped, finished, respring, unhealthy, timeout, queuedCallbacks }
@main struct Runner {
    @MainActor static func main() {
        let steps = [
            EagleAuraStudioOperationStep(flag: 1, englishName: "Dynamic Island", spanishName: "Dynamic Island"),
            EagleAuraStudioOperationStep(flag: 32, englishName: "Dock", spanishName: "Dock")]
        var entryCases = 0, timelineCases = 0
        for active in [nil, "old", "run"] as [String?] {
            for applying in [false, true] {
                for count in 0...2 {
                    for index in 0...count + 1 {
                        for spanish in [false, true] {
                            var snapshots: [[String]] = []
                            for owned in [false, true] {
                                let c = Context(); c.activeID = active; c.applying = applying; c.spanish = spanish
                                World.context = c
                                let host: any Host = owned ? OwnedHost(context: c) : PublicHost(context: c)
                                host.begin(index: index, steps: Array(steps.prefix(count)), operationID: "run")
                                if active != "run" { precondition(c.events == ["read.operationID"]) }
                                else if !applying { precondition(c.events == ["read.operationID", "read.applying"]) }
                                else if index >= count { precondition(c.completions == [false] && c.stepIndex == 0) }
                                else { precondition(c.stepIndex == index + 1 && c.completions.isEmpty) }
                                snapshots.append(c.snapshot)
                            }
                            precondition(snapshots[0] == snapshots[1]); entryCases += 1
                        }
                    }
                }
            }
        }
        let timelines: [[Action]] = [
            [.time(9), .result, .time(61)],
            [.time(10), .result, .time(61)],
            [.time(59), .result, .time(61)],
            [.time(60), .result, .time(61)],
            [.time(61), .result],
            [.result, .result, .time(61)],
            [.time(10), .result, .result, .time(61)],
            [.time(60), .result, .result],
            [.stale, .time(61), .result],
            [.time(10), .stale, .time(61), .result],
            [.stopped, .time(61), .result],
            [.finished, .time(61), .result],
            [.time(10), .respring, .result, .time(61)],
            [.time(60), .respring, .result],
            [.unhealthy, .time(10), .result, .time(61)],
            [.timeout, .time(60), .result],
            [.time(60), .stale, .result],
            [.time(9), .stopped, .time(61)],
            [.result, .queuedCallbacks, .time(61)],
            [.time(10), .result, .queuedCallbacks, .result, .time(61)],
            [.time(60), .result, .queuedCallbacks, .result],
            [.stale, .queuedCallbacks, .time(61), .result],
        ]
        for spanish in [false, true] {
            for operation in [EagleAuraStudioOperation.remove, .apply(.glow), .apply(.rainbow)] {
                for step in steps {
                    for (timelineIndex, actions) in timelines.enumerated() {
                        var snapshots: [[[String]]] = []
                        for owned in [false, true] {
                            let c = Context(); c.spanish = spanish
                            World.context = c
                            let host: any Host = owned ? OwnedHost(context: c) : PublicHost(context: c)
                            host.start(operationID: "run", step: step, operation: operation, targetPID: 101)
                            precondition(c.jobs.map { $0.0 } == [10, 60])
                            var history = [c.snapshot]
                            for action in actions {
                                switch action {
                                case .time(let value): c.advanceClock(to: value)
                                case .stale: c.activeID = "next"
                                case .stopped: c.applying = false
                                case .finished: c.finished = true
                                case .respring: c.livePID = 202
                                case .unhealthy: c.healthy = false
                                case .timeout: c.timedOut = true
                                case .queuedCallbacks:
                                    // Model a callback already dequeued when cancellation occurs.
                                    c.soft!.block(); c.hard!.block()
                                case .result:
                                    host.receive(process: Session(c), processError: nil,
                                                 result: operation.isRemoving ? 0 : Int32(step.flag),
                                                 operationID: "run", operationSpringBoardPID: 101,
                                                 targetPID: 101, springBoardPID: 101, step: step)
                                }
                                history.append(c.snapshot)
                            }
                            if [0, 1, 2, 5, 6, 18, 19].contains(timelineIndex) {
                                precondition(c.consumed == 1 && c.nextSteps == [1] && c.completions.isEmpty)
                                precondition(!c.deadline && !c.gateLocked && !c.safetyBlocked)
                            }
                            if [3, 4, 7, 20].contains(timelineIndex) {
                                precondition(c.consumed == 1 && c.nextSteps.isEmpty && c.completions == [true])
                                precondition(c.deadline && c.gateLocked && c.safetyBlocked)
                                let deadlineIndex = c.events.firstIndex(of: "write.deadline.true")!
                                let quarantineIndex = c.events.firstIndex { $0.hasPrefix("quarantine.") }!
                                let safetyIndex = c.events.firstIndex(of: "write.safety.true")!
                                let lockIndex = c.events.firstIndex(of: "gate.lock")!
                                precondition(deadlineIndex < quarantineIndex && quarantineIndex < safetyIndex && safetyIndex < lockIndex)
                            }
                            if [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 21].contains(timelineIndex) {
                                precondition(c.consumed == 0 && c.nextSteps.isEmpty && c.completions.isEmpty)
                            }
                            if [8, 10, 11].contains(timelineIndex) {
                                precondition(!c.events.contains { $0.hasPrefix("log.step.native.progress") })
                                precondition(!c.deadline)
                            }
                            snapshots.append(history)
                        }
                        precondition(snapshots[0] == snapshots[1], "Timeline diverged: \(timelineIndex)")
                        timelineCases += 1
                    }
                }
            }
        }
        // Each deadline is relative to the clock at its own scheduling point.
        // Collapsing them onto one captured instant would change the public sequence.
        var driftHistories: [[[String]]] = []
        for owned in [false, true] {
            let c = Context(); c.schedulingDelay = 3
            World.context = c
            let host: any Host = owned ? OwnedHost(context: c) : PublicHost(context: c)
            host.start(operationID: "run", step: steps[0], operation: .apply(.glow), targetPID: 101)
            precondition(c.jobs.map { $0.0 } == [10, 63])
            c.advanceClock(to: 60)
            precondition(!c.deadline)
            var history = [c.snapshot]
            c.advanceClock(to: 63)
            precondition(c.deadline)
            history.append(c.snapshot)
            host.receive(process: Session(c), processError: nil, result: 1, operationID: "run",
                         operationSpringBoardPID: 101, targetPID: 101, springBoardPID: 101, step: steps[0])
            precondition(c.completions == [true] && c.nextSteps.isEmpty)
            history.append(c.snapshot)
            driftHistories.append(history)
        }
        precondition(driftHistories[0] == driftHistories[1])
        timelineCases += 1
        print("PASS: \(entryCases) step-entry cases and \(timelineCases) clock/result journeys; 10s/60s timing, cancellation, staleness, duplicate results and deadline continuation")
    }
}

