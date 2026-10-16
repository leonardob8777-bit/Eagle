import Foundation

typealias DockGalleryStyle = EagleDockGalleryBuiltInTheme
typealias RemoteDockGalleryTheme = EagleDockGalleryTheme

enum Operation: String, CaseIterable { case restore, builtin, remote }
enum Scenario: String, CaseIterable {
    case normal, alreadyBusy, doubleTap, held, reenterReset, reenterFeedback
    case reenterNotification, repeatAfterFinish, canceledCaller
}

@MainActor protocol FlowHost {
    func start(_ operation: Operation)
}

@MainActor final class FlowContext {
    let scenario: Scenario
    let first: Operation
    let second: Operation
    let succeeds: Bool
    let message: String
    var busy = false
    var selectedRaw = -1
    var trace: [String] = []
    var executed: [Operation] = []
    var finished = 0
    var notified = 0
    var feedback = 0
    var prepared = 0
    var reentryAttempted = false
    var gate: CheckedContinuation<Void, Never>?
    var reenter: (() -> Void)?
    lazy var gallery = RecordingGallery(context: self)
    let directory = URL(fileURLWithPath: "/fixture/Dock/theme")
    let theme = EagleDockGalleryTheme(
        id: "live-fixture", version: 7, title: "Theme", titleES: "Tema",
        subtitle: "Fixture", subtitleES: "Prueba", accent: "#20C0F0",
        previewURL: URL(string: "https://example.invalid/preview.png")!, animatedPreviewURL: nil,
        packageURL: URL(string: "https://example.invalid/theme.zip")!,
        sha256: String(repeating: "a", count: 64), byteCount: 4096,
        frameCount: 17, fps: 6, width: 1146, height: 318
    )

    init(_ scenario: Scenario, first: Operation, second: Operation, succeeds: Bool, message: String) {
        self.scenario = scenario
        self.first = first
        self.second = second
        self.succeeds = succeeds
        self.message = message
        self.busy = scenario == .alreadyBusy
    }
    func event(_ value: String) { trace.append(value) }
    func readBusy() -> Bool { event("busy.read.\(busy)"); return busy }
    func writeBusy(_ value: Bool) {
        event("busy.write.\(value)")
        busy = value
        if !value {
            finished += 1
            if scenario == .reenterReset { tryReentry() }
        }
    }
    func writeSelection(_ value: Int) { event("selection.write.\(value)"); selectedRaw = value }
    func readIntensity() -> Double { event("intensity.read"); return 0.72 }
    func tryReentry() {
        guard !reentryAttempted else { return }
        reentryAttempted = true
        event("fixture.reenter.\(second.rawValue)")
        reenter?()
    }
    func execute(_ operation: Operation) async -> DockGalleryApplyResult {
        precondition(busy)
        executed.append(operation)
        precondition(operation == (executed.count == 1 ? first : second))
        event("execute.begin.\(operation.rawValue).cancelled.\(Task.isCancelled)")
        if scenario == .held { await withCheckedContinuation { gate = $0 } }
        event("execute.end.\(operation.rawValue)")
        return DockGalleryApplyResult(succeeded: succeeds, message: message)
    }
}

@MainActor enum FlowEnvironment { static var current: FlowContext! }

// Recording executor/result only; the production port is compiled unchanged.
struct DockGalleryApplyResult { let succeeded: Bool; let message: String }
@MainActor struct DockGalleryExecutor {
    static let shared = DockGalleryExecutor()
    func restore() async -> DockGalleryApplyResult {
        await FlowEnvironment.current.execute(.restore)
    }
    func apply(_ style: DockGalleryStyle, intensity: Double) async -> DockGalleryApplyResult {
        precondition(style == .bubblegum && intensity == 0.72)
        return await FlowEnvironment.current.execute(.builtin)
    }
    func applyRemote(_ theme: EagleDockGalleryTheme, directory: URL, intensity: Double) async -> DockGalleryApplyResult {
        let context = FlowEnvironment.current!
        precondition(theme == context.theme && directory == context.directory && intensity == 0.72)
        return await context.execute(.remote)
    }
}

@MainActor final class RecordingGallery {
    unowned let context: FlowContext
    init(context: FlowContext) { self.context = context }
    var downloadingID: String? { context.event("download.read.nil"); return nil }
    func prepare(_ theme: EagleDockGalleryTheme) async throws -> URL {
        precondition(theme == context.theme)
        context.prepared += 1
        context.event("prepare.remote")
        return context.directory
    }
}

@MainActor struct UINotificationFeedbackGenerator {
    enum FeedbackType { case success }
    func notificationOccurred(_ type: FeedbackType) {
        let context = FlowEnvironment.current!
        precondition(context.succeeds)
        context.feedback += 1
        context.event("feedback.success")
        if context.scenario == .reenterFeedback { context.tryReentry() }
    }
}

@MainActor struct EagleNotifications {
    static let shared = EagleNotifications()
    func result(_ success: Bool, title: String, message: String) {
        let context = FlowEnvironment.current!
        precondition(success == context.succeeds && title == "Dock Gallery" && message == context.message)
        context.notified += 1
        let resetAfterNotice = context.executed.last == .remote
        precondition(context.finished == context.notified - (resetAfterNotice ? 1 : 0), "Completion order changed")
        context.event("notify.\(success).\(title).\(message)")
        if context.scenario == .reenterNotification { context.tryReentry() }
    }
}

@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        preconditionFailure("Unexpected package error during mixed-flow fixture")
    }
}

@main private enum RestoreFlowChecks {
    static func wait(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() {
            precondition(Date() < deadline, "Timed out waiting for Dock flow fixture")
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    static func run(owned: Bool, scenario: Scenario, first: Operation, second: Operation,
                    succeeds: Bool, message: String) async -> [String] {
        let context = FlowContext(scenario, first: first, second: second, succeeds: succeeds, message: message)
        FlowEnvironment.current = context
        let host: any FlowHost = owned ? OwnedFlowHost(context: context) : PublicFlowHost(context: context)
        context.reenter = { host.start(second) }
        defer { context.reenter = nil; FlowEnvironment.current = nil }
        if scenario == .canceledCaller {
            let caller = Task { @MainActor in
                precondition(Task.isCancelled)
                host.start(first)
            }
            caller.cancel()
            await caller.value
        } else {
            host.start(first)
            precondition(context.executed.isEmpty && context.notified == 0 && context.prepared == 0)
            if scenario != .alreadyBusy && first == .restore {
                precondition(context.trace == ["busy.read.false", "busy.write.true"], "Restore synchronous effects changed")
            }
        }
        if scenario == .alreadyBusy {
            await Task.yield()
            precondition(context.trace == ["busy.read.true"] && context.selectedRaw == -1)
            precondition(context.executed.isEmpty && context.notified == 0 && context.finished == 0)
            return context.trace
        }
        if scenario == .doubleTap { host.start(second) }
        if scenario == .held {
            await wait { context.gate != nil }
            precondition(context.busy && context.finished == 0 && context.notified == 0)
            let before = context.trace
            host.start(second)
            precondition(context.trace == before + ["busy.read.true"], "In-flight action failed to block another operation")
            context.gate?.resume()
            context.gate = nil
        }
        let callbackReentry = scenario == .reenterReset || scenario == .reenterNotification || (scenario == .reenterFeedback && succeeds)
        let acceptedReentry = callbackReentry && (scenario == .reenterReset || first != .remote)
        let operations = acceptedReentry || scenario == .repeatAfterFinish ? 2 : 1
        if scenario == .repeatAfterFinish {
            await wait { context.finished == 1 && context.notified == 1 }
            precondition(!context.busy)
            host.start(second)
        }
        await wait { context.finished == operations && context.notified == operations }
        precondition(!context.busy && context.executed == (operations == 2 ? [first, second] : [first]))
        precondition(context.feedback == (succeeds ? operations : 0))
        precondition(context.reentryAttempted == callbackReentry)
        let builtinCount = context.executed.filter { $0 == .builtin }.count
        let remoteCount = context.executed.filter { $0 == .remote }.count
        precondition(context.selectedRaw == (builtinCount == 0 ? -1 : DockGalleryStyle.bubblegum.rawValue))
        precondition(context.prepared == remoteCount)
        precondition(context.trace.filter { $0 == "intensity.read" }.count == builtinCount + remoteCount)
        precondition(context.trace.filter { $0.hasPrefix("selection.write.") }.count == builtinCount)
        precondition(!context.trace.contains { $0.contains("cancelled.true") })
        precondition(context.executed.last == .remote ? context.trace.last == "busy.write.false" : context.trace.last!.hasPrefix("notify."))
        return context.trace
    }

    static func compare(scenario: Scenario, first: Operation, second: Operation, succeeds: Bool, message: String) async -> Int {
        let reference = await run(owned: false, scenario: scenario, first: first, second: second, succeeds: succeeds, message: message)
        let actual = await run(owned: true, scenario: scenario, first: first, second: second, succeeds: succeeds, message: message)
        precondition(reference == actual, "Public/owned mismatch: \(scenario) \(first) → \(second)")
        return actual.count
    }

    static func main() async {
        var restoreCases = 0
        var restoreEvents = 0
        for succeeds in [false, true] {
            for message in ["", "Restored", "No se pudo restaurar.\nNothing changed ✓", String(repeating: "á🌈", count: 128)] {
                for scenario in Scenario.allCases {
                    restoreEvents += await compare(scenario: scenario, first: .restore, second: .restore, succeeds: succeeds, message: message)
                    restoreCases += 1
                }
            }
        }
        var mixedCases = 0
        var mixedEvents = 0
        for first in Operation.allCases {
            for second in Operation.allCases where second != first {
                for succeeds in [false, true] {
                    for scenario in [Scenario.doubleTap, .held, .reenterReset, .reenterFeedback, .reenterNotification, .repeatAfterFinish] {
                        mixedEvents += await compare(scenario: scenario, first: first, second: second, succeeds: succeeds, message: "Original outcome ✓")
                        mixedCases += 1
                    }
                }
            }
        }
        print("PASS: \(restoreCases) public/owned Restore scenarios / \(restoreEvents) ordered events; success/failure and exact message forwarding")
        print("PASS: \(mixedCases) mixed Apply/Restore scenarios / \(mixedEvents) ordered events across all directed operation pairs")
        print("PASS: synchronous guard/busy, one deferred request, duplicate/held operations, callback ordering/reentry, reuse and cancellation")
        print("PASS: Restore does not touch selection, intensity or package preparation; original remote/built-in differences retained")
    }
}
