import Foundation

typealias DockGalleryStyle = EagleDockGalleryBuiltInTheme

@MainActor protocol ApplyHost {
    func start(_ style: DockGalleryStyle)
}

enum FlowScenario: String, CaseIterable {
    case success, rejected, alreadyBusy, doubleTap, changedBeforeTask, heldApply
    case reenterReset, reenterFeedback, reenterNotification, reenterRejectedNotification
    case repeatAfterFinish, mixedResults, canceledCaller

    var reentrant: Bool {
        self == .reenterReset || self == .reenterFeedback || self == .reenterNotification || self == .reenterRejectedNotification
    }
    var repeated: Bool { self == .repeatAfterFinish || self == .mixedResults }
}

@MainActor final class FlowContext {
    let scenario: FlowScenario
    let firstStyle: DockGalleryStyle
    let secondStyle: DockGalleryStyle
    let originalIntensity: Double
    var intensity: Double
    var busy = false
    var selectedRaw = -1
    var trace: [String] = []
    var finished = 0
    var executed = 0
    var notified = 0
    var feedback = 0
    var reentered = false
    var applyGate: CheckedContinuation<Void, Never>?
    var reenter: (() -> Void)?

    init(_ scenario: FlowScenario, style: DockGalleryStyle, intensity: Double) {
        self.scenario = scenario
        self.firstStyle = style
        let index = DockGalleryStyle.allCases.firstIndex(of: style)!
        self.secondStyle = DockGalleryStyle.allCases[(index + 1) % DockGalleryStyle.allCases.count]
        self.originalIntensity = intensity
        self.intensity = intensity
        busy = scenario == .alreadyBusy
    }

    func event(_ value: String) { trace.append(value) }
    func readBusy() -> Bool { event("busy.read.\(busy)"); return busy }
    func writeSelection(_ value: Int) { event("selection.write.\(value)"); selectedRaw = value }
    func writeBusy(_ value: Bool) {
        event("busy.write.\(value)")
        busy = value
        if !value {
            finished += 1
            if scenario == .reenterReset { tryReentry() }
        }
    }
    func readIntensity() -> Double { event("intensity.\(intensity.bitPattern)"); return intensity }
    func tryReentry() {
        guard !reentered else { return }
        precondition(!busy, "Built-in Apply must clear busy before completion callbacks")
        reentered = true
        event("fixture.reenter")
        reenter?()
    }
    func succeeds(_ operation: Int) -> Bool {
        scenario != .rejected && scenario != .reenterRejectedNotification && !(scenario == .mixedResults && operation == 2)
    }
    func message(_ operation: Int) -> String { "executor result \(operation) ✓\nunchanged message" }
}

@MainActor enum FlowEnvironment {
    static var current: FlowContext!
}

// Exact native-result shape, but only a recording executor; no protected code is compiled.
struct DockGalleryApplyResult {
    let succeeded: Bool
    let message: String
}

@MainActor struct DockGalleryExecutor {
    static let shared = DockGalleryExecutor()
    func apply(_ style: DockGalleryStyle, intensity: Double) async -> DockGalleryApplyResult {
        let context = FlowEnvironment.current!
        context.executed += 1
        let operation = context.executed
        precondition(style == (operation == 1 ? context.firstStyle : context.secondStyle), "Tapped style changed")
        let expectedIntensity = context.scenario == .changedBeforeTask ? 0.375 : context.originalIntensity
        precondition(intensity.bitPattern == expectedIntensity.bitPattern, "Task-time intensity changed")
        context.event("execute.begin.\(operation).\(style.rawValue).\(intensity.bitPattern).cancelled.\(Task.isCancelled)")
        if context.scenario == .heldApply {
            await withCheckedContinuation { context.applyGate = $0 }
        }
        context.event("execute.end.\(operation)")
        return DockGalleryApplyResult(succeeded: context.succeeds(operation), message: context.message(operation))
    }
}

@MainActor struct UINotificationFeedbackGenerator {
    enum FeedbackType { case success }
    func notificationOccurred(_ type: FeedbackType) {
        let context = FlowEnvironment.current!
        context.feedback += 1
        precondition(context.finished == context.executed, "Feedback came before busy reset")
        context.event("feedback.success")
        if context.scenario == .reenterFeedback { context.tryReentry() }
    }
}

@MainActor struct EagleNotifications {
    static let shared = EagleNotifications()
    func result(_ success: Bool, title: String, message: String) {
        let context = FlowEnvironment.current!
        context.notified += 1
        let operation = context.notified
        precondition(context.finished == operation, "Notification came before busy reset")
        precondition(title == "Dock Gallery" && message == context.message(operation))
        precondition(success == context.succeeds(operation), "Executor outcome was reinterpreted")
        context.event("notify.\(success).\(title).\(message)")
        if context.scenario == .reenterNotification || context.scenario == .reenterRejectedNotification {
            context.tryReentry()
        }
    }
}

@main private enum BuiltInApplyFlowChecks {
    static func wait(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() {
            precondition(Date() < deadline, "Timed out waiting for built-in Apply fixture")
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    static func run(owned: Bool, scenario: FlowScenario, style: DockGalleryStyle, intensity: Double) async -> [String] {
        let context = FlowContext(scenario, style: style, intensity: intensity)
        FlowEnvironment.current = context
        let host: any ApplyHost = owned ? OwnedApplyHost(context: context) : PublicApplyHost(context: context)
        context.reenter = { host.start(context.secondStyle) }
        defer { context.reenter = nil; FlowEnvironment.current = nil }

        if scenario == .canceledCaller {
            let caller = Task { @MainActor in
                precondition(Task.isCancelled)
                host.start(style)
            }
            caller.cancel()
            await caller.value
        } else {
            host.start(style)
            precondition(context.executed == 0 && context.notified == 0, "Apply no longer defers execution")
            if scenario != .alreadyBusy {
                precondition(context.trace == ["busy.read.false", "selection.write.\(style.rawValue)", "busy.write.true"],
                             "Synchronous guard/selection/busy changed or intensity read too early")
            }
        }
        if scenario == .alreadyBusy {
            await Task.yield()
            precondition(context.executed == 0 && context.finished == 0 && context.notified == 0)
            precondition(context.trace == ["busy.read.true"] && context.selectedRaw == -1)
            return context.trace
        }
        if scenario == .doubleTap { host.start(context.secondStyle) }
        if scenario == .changedBeforeTask {
            context.intensity = 0.375
            context.selectedRaw = context.secondStyle.rawValue
            context.event("fixture.changed.intensity.and.selection.before.task")
        }
        if scenario == .heldApply {
            await wait { context.applyGate != nil }
            precondition(context.busy && context.finished == 0 && context.notified == 0)
            context.intensity = 0.125
            context.event("fixture.changed.intensity.during.execute")
            host.start(context.secondStyle)
            context.applyGate?.resume()
            context.applyGate = nil
        }
        let operations = scenario.reentrant || scenario.repeated ? 2 : 1
        if scenario.repeated {
            await wait { context.notified == 1 }
            precondition(!context.busy)
            host.start(context.secondStyle)
        }
        await wait { context.notified == operations }
        precondition(!context.busy && context.executed == operations && context.finished == operations)
        precondition(context.feedback == (1...operations).filter { context.succeeds($0) }.count)
        precondition(context.reentered == scenario.reentrant)
        let finalStyle = operations == 2 || scenario == .changedBeforeTask ? context.secondStyle : style
        precondition(context.selectedRaw == finalStyle.rawValue, "Selection write/order changed")
        precondition(context.trace.filter { $0.hasPrefix("intensity.") }.count == operations)
        precondition(context.trace.last!.hasPrefix("notify."), "Built-in Apply completion order changed")
        precondition(!context.trace.contains { $0.contains("cancelled.true") }, "Caller cancellation leaked into unstructured Task")
        return context.trace
    }

    static func main() async {
        var cases = 0
        var events = 0
        for style in DockGalleryStyle.allCases {
            for intensity in [-0.25, 0, 0.72, 1.25, Double.nan, Double.infinity] {
                for scenario in FlowScenario.allCases {
                    let reference = await run(owned: false, scenario: scenario, style: style, intensity: intensity)
                    let actual = await run(owned: true, scenario: scenario, style: style, intensity: intensity)
                    precondition(reference == actual, "Built-in public/owned event mismatch: \(scenario)")
                    cases += 1
                    events += actual.count
                }
            }
        }
        print("PASS: \(cases) public/owned built-in Apply scenarios / \(events) ordered events; all six styles and exact intensity bits")
        print("PASS: synchronous selection/busy, deferred intensity, repeated taps, held execution and task-time updates")
        print("PASS: reset-before-feedback/notification, accepted reentry, exact outcomes, reuse and canceled caller")
    }
}
