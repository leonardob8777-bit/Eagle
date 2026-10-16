import Foundation

typealias RemoteDockGalleryTheme = EagleDockGalleryTheme

@MainActor protocol ApplyHost {
    func start(_ theme: EagleDockGalleryTheme)
}

enum FlowScenario: String, CaseIterable {
    case success, rejected, prepareFailure, cancellationError
    case alreadyBusy, downloading, bothBlocked, doubleTap
    case heldPrepare, heldApply, languageDuringFailure
    case reenterFeedback, reenterNotification, repeatAfterFinish, canceledCaller

    var blocked: Bool { self == .alreadyBusy || self == .downloading || self == .bothBlocked }
    var holdsPrepare: Bool { self == .heldPrepare || self == .languageDuringFailure }
}

@MainActor final class FlowContext {
    let scenario: FlowScenario
    let expectedTheme: EagleDockGalleryTheme
    let originalIntensity: Double
    let directory = URL(fileURLWithPath: "/fixture/Eagle Dock/á-theme")
    var intensity: Double
    var busy = false
    var downloading: String?
    var language = "en"
    var trace: [String] = []
    var finished = 0
    var prepared = 0
    var executed = 0
    var notified = 0
    var feedback = 0
    var prepareGate: CheckedContinuation<Void, Never>?
    var applyGate: CheckedContinuation<Void, Never>?
    var reenter: (() -> Void)?
    lazy var gallery = RecordingGallery(context: self)

    init(_ scenario: FlowScenario, theme: EagleDockGalleryTheme, intensity: Double) {
        self.scenario = scenario
        self.expectedTheme = theme
        self.originalIntensity = intensity
        self.intensity = intensity
        busy = scenario == .alreadyBusy || scenario == .bothBlocked
        downloading = scenario == .downloading || scenario == .bothBlocked ? "other" : nil
    }

    func event(_ value: String) { trace.append(value) }
    func readBusy() -> Bool { event("busy.read.\(busy)"); return busy }
    func writeBusy(_ value: Bool) {
        event("busy.write.\(value)")
        busy = value
        if !value { finished += 1 }
    }
    func readIntensity() -> Double { event("intensity.\(intensity.bitPattern)"); return intensity }
}

@MainActor enum FlowEnvironment {
    static var current: FlowContext!
}

@MainActor final class RecordingGallery {
    unowned let context: FlowContext
    init(context: FlowContext) { self.context = context }
    var downloadingID: String? {
        context.event("download.read.\(context.downloading ?? "nil")")
        return context.downloading
    }
    func prepare(_ theme: EagleDockGalleryTheme) async throws -> URL {
        precondition(theme == context.expectedTheme)
        context.prepared += 1
        context.event("prepare.begin.\(theme.id).cancelled.\(Task.isCancelled)")
        if context.scenario.holdsPrepare {
            await withCheckedContinuation { context.prepareGate = $0 }
        }
        context.event("prepare.end")
        switch context.scenario {
        case .prepareFailure, .languageDuringFailure: throw URLError(.cannotDecodeContentData)
        case .cancellationError: throw CancellationError()
        default: return context.directory
        }
    }
}

// Recording replacement only: production native executor is never compiled here.
@MainActor struct DockGalleryExecutor {
    static let shared = DockGalleryExecutor()
    func applyRemote(_ theme: EagleDockGalleryTheme, directory: URL, intensity: Double) async -> EagleDockGalleryOutcome {
        let context = FlowEnvironment.current!
        precondition(theme == context.expectedTheme && directory == context.directory)
        precondition(intensity.bitPattern == context.originalIntensity.bitPattern, "Tap-time intensity changed")
        context.executed += 1
        context.event("execute.begin.\(theme.id).\(intensity.bitPattern).cancelled.\(Task.isCancelled)")
        if context.scenario == .heldApply {
            await withCheckedContinuation { context.applyGate = $0 }
        }
        context.event("execute.end")
        return EagleDockGalleryOutcome(succeeded: context.scenario != .rejected, message: "executor result ✓")
    }
}

@MainActor struct CurrentDockGalleryPort: EagleDockGalleryPort {
    func applyRemote(_ request: EagleDockGalleryApplyRequest) async -> EagleDockGalleryOutcome {
        await DockGalleryExecutor.shared.applyRemote(request.theme, directory: request.directory, intensity: request.intensity)
    }
    func restore() async -> EagleDockGalleryOutcome { preconditionFailure("Remote Apply called Restore") }
}

@MainActor struct UINotificationFeedbackGenerator {
    enum FeedbackType { case success }
    func notificationOccurred(_ type: FeedbackType) {
        let context = FlowEnvironment.current!
        precondition(context.busy, "Feedback must happen before busy reset")
        context.feedback += 1
        context.event("feedback.success")
        if context.scenario == .reenterFeedback { context.reenter?() }
    }
}

@MainActor struct EagleNotifications {
    static let shared = EagleNotifications()
    func result(_ success: Bool, title: String, message: String) {
        let context = FlowEnvironment.current!
        precondition(context.busy, "Notification must happen before busy reset")
        precondition(title == "Dock Gallery")
        context.notified += 1
        context.event("notify.\(success).\(title).\(message)")
        if context.scenario == .reenterNotification { context.reenter?() }
    }
}

@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        let context = FlowEnvironment.current!
        context.event("language.\(context.language)")
        return context.language == "es" ? es : en
    }
}

@main private enum ApplyFlowChecks {
    static func wait(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() {
            precondition(Date() < deadline, "Timed out waiting for Apply fixture")
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    static func run(owned: Bool, scenario: FlowScenario, theme: EagleDockGalleryTheme, intensity: Double) async -> [String] {
        let context = FlowContext(scenario, theme: theme, intensity: intensity)
        FlowEnvironment.current = context
        let host: any ApplyHost = owned ? OwnedApplyHost(context: context) : PublicApplyHost(context: context)
        context.reenter = { host.start(theme) }
        defer { context.reenter = nil; FlowEnvironment.current = nil }
        if scenario == .canceledCaller {
            let caller = Task { @MainActor in
                precondition(Task.isCancelled)
                host.start(theme)
            }
            caller.cancel()
            await caller.value
        } else {
            host.start(theme)
            // No task has run before returning from the synchronous tap handler.
            precondition(context.prepared == 0 && context.executed == 0 && context.notified == 0)
        }
        if scenario.blocked {
            await Task.yield()
            precondition(context.prepared == 0 && context.executed == 0 && context.finished == 0)
            let expected = scenario == .downloading
                ? ["busy.read.false", "download.read.other"] : ["busy.read.true"]
            precondition(context.trace == expected, "Guard reads or early-return effects changed")
            return context.trace
        }
        if scenario == .doubleTap { host.start(theme) }
        if scenario.holdsPrepare {
            await wait { context.prepareGate != nil }
            precondition(context.busy && context.finished == 0 && context.notified == 0 && context.executed == 0)
            context.intensity = 0.125
            context.language = "es"
            context.event("fixture.changed.intensity.and.language")
            host.start(theme)
            context.prepareGate?.resume()
            context.prepareGate = nil
        }
        if scenario == .heldApply {
            await wait { context.applyGate != nil }
            precondition(context.busy && context.finished == 0 && context.notified == 0)
            host.start(theme)
            context.applyGate?.resume()
            context.applyGate = nil
        }
        await wait { context.finished == 1 }
        if scenario == .repeatAfterFinish {
            host.start(theme)
            await wait { context.finished == 2 }
        }
        let operations = scenario == .repeatAfterFinish ? 2 : 1
        let failedPreparation = scenario == .prepareFailure || scenario == .cancellationError || scenario == .languageDuringFailure
        precondition(!context.busy && context.finished == operations && context.prepared == operations)
        precondition(context.executed == (failedPreparation ? 0 : operations))
        precondition(context.notified == operations)
        precondition(context.feedback == (failedPreparation || scenario == .rejected ? 0 : operations))
        precondition(context.trace.last == "busy.write.false", "Completion order changed")
        if failedPreparation {
            let language = scenario == .languageDuringFailure ? "es" : "en"
            precondition(context.trace.contains("language.\(language)"))
            let message = language == "es"
                ? "No se pudo descargar o verificar el paquete original. Nada cambió."
                : "The original theme package could not be downloaded or verified. Nothing changed."
            precondition(context.trace.contains("notify.false.Dock Gallery.\(message)"))
        } else {
            precondition(!context.trace.contains(where: { $0.hasPrefix("language.") }))
        }
        precondition(!context.trace.contains(where: { $0.contains("cancelled.true") }), "Unstructured task inherited caller cancellation")
        return context.trace
    }

    static func theme(live: Bool) -> EagleDockGalleryTheme {
        EagleDockGalleryTheme(
            id: live ? "live-✓" : "static-✓", version: 7, title: "Theme", titleES: "Tema",
            subtitle: "Test", subtitleES: "Prueba", accent: "#20C0F0",
            previewURL: URL(string: "https://example.invalid/preview.png")!, animatedPreviewURL: nil,
            packageURL: URL(string: "https://example.invalid/theme.zip")!,
            sha256: String(repeating: "a", count: 64), byteCount: 4096,
            frameCount: live ? 17 : 1, fps: live ? 6 : 1, width: 1146, height: 318
        )
    }

    static func main() async {
        var cases = 0
        var events = 0
        for live in [false, true] {
            for intensity in [-0.25, 0, 0.72, 1.25, Double.nan, Double.infinity] {
                for scenario in FlowScenario.allCases {
                    let reference = await run(owned: false, scenario: scenario, theme: theme(live: live), intensity: intensity)
                    let actual = await run(owned: true, scenario: scenario, theme: theme(live: live), intensity: intensity)
                    precondition(reference == actual, "Public/owned event mismatch: \(scenario)")
                    cases += 1
                    events += actual.count
                }
            }
        }
        print("PASS: \(cases) public/owned Apply scenarios / \(events) ordered events, Static/Live and exact intensity bits")
        print("PASS: guarded reads, synchronous busy state, deferred work, double taps, held phases, late language, reentrancy and reuse")
        print("PASS: success/failure/cancellation policy, callback/result order and unchanged native request forwarding via recording ports")
    }
}
