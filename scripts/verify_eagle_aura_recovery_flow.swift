import Foundation

struct AuraStudioNotice { let message: String }
struct AuraStudioOperationStep {
    let flag: UInt32
    let englishName: String
}
struct Input {
    let previous: UInt32
    let applied: UInt32
    let pid: Int32
    let target: String
}
@MainActor final class Context {
    var events: [String] = []
    var retained: UInt32 = 0
    var flags = 33
    var pid = 999
    var islandMode = 4
    var dockMode = 2
    var report: URL?
    var notice: AuraStudioNotice?
    var busy = true
    var gateHeld = true
    var spanish = false
    var nilReport = false
    var mutateDuringReset = false
    var phase = "initial"
    var state: String {
        "\(retained)|\(flags)|\(pid)|\(islandMode)|\(dockMode)|\(report?.absoluteString ?? "nil")|\(notice?.message ?? "nil")|\(busy)|\(gateHeld)|\(phase)"
    }
    func createReport(_ summary: String) -> URL? {
        events.append("report:\(summary)")
        return nilReport ? nil : URL(string: "https://fixture.invalid/report")
    }
    func reset() {
        events.append("reset"); busy = false; phase = "reset"
        if mutateDuringReset { islandMode = 14; dockMode = 8 }
    }
}
@MainActor enum Runtime { static var context: Context! }
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String) { Runtime.context.events.append("log:\(stage):\(detail)") }
}
@MainActor enum AuraStudioApplyGate {
    static func end() { Runtime.context.events.append("gate.end"); Runtime.context.gateHeld = false }
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Runtime.context.events.append("text:\(en)|\(es)")
        return Runtime.context.spanish ? es : en
    }
}
@MainActor struct Target {
    let name: String
    var title: String {
        let c = Runtime.context!
        c.events.append("target.title:\(c.phase)")
        return c.mutateDuringReset ? "\(name)-\(c.phase)" : name
    }
}
@MainActor protocol Host { var context: Context { get }; var input: Input { get } }
extension Host {
    var operationID: String { "operation-test" }
    var operationTarget: Target { Target(name: input.target) }
    var previouslyVerified: UInt32 { input.previous }
    var newlyApplied: UInt32 { input.applied }
    var operationSpringBoardPID: Int32 { input.pid }
    var retainedVerified: UInt32 {
        get { context.events.append("read.retained"); return context.retained }
        nonmutating set { context.retained = newValue; context.events.append("write.retained:\(newValue)") }
    }
    var activeFlagsRaw: Int {
        get { context.flags }
        nonmutating set { context.flags = newValue; context.events.append("write.flags:\(newValue)") }
    }
    var activeSpringBoardPID: Int {
        get { context.pid }
        nonmutating set { context.pid = newValue; context.events.append("write.pid:\(newValue)") }
    }
    var diagnosticsURL: URL? {
        get { context.report }
        nonmutating set {
            context.report = newValue; context.events.append("write.report:\(newValue?.absoluteString ?? "nil")")
        }
    }
    var notice: AuraStudioNotice? {
        get { context.notice }
        nonmutating set {
            precondition(!context.busy && !context.gateHeld, "Notice before cleanup/gate release")
            context.notice = newValue; context.events.append("notice:\(newValue?.message ?? "nil")")
        }
    }
    func makeDiagnosticsReport(summary: String) -> URL? { context.createReport(summary) }
    func resetOperationUI() { context.reset() }
    func message(for result: Int32) -> String {
        context.events.append("error.message:\(result)"); return "error-\(result)"
    }
}

@main struct Check {
    @MainActor static func main() {
        var preflights = 0, rollbacks = 0, traceActions = 0, events = 0
        func contexts(spanish: Bool, retained: UInt32, mutate: Bool, nilReport: Bool) -> (Context, Context) {
            let a = Context(), b = Context()
            for c in [a, b] {
                c.spanish = spanish; c.retained = retained; c.mutateDuringReset = mutate; c.nilReport = nilReport
                c.notice = AuraStudioNotice(message: "old notice")
                c.report = URL(string: "https://fixture.invalid/previous")
            }
            return (a, b)
        }
        func compare(_ a: Context, _ b: Context) {
            precondition(a.events == b.events, "Callback mismatch")
            precondition(a.state == b.state, "State mismatch")
            precondition(!b.busy && !b.gateHeld)
            precondition(b.events.last?.hasPrefix("notice:") == true)
            let reset = b.events.firstIndex(of: "reset")!, gate = b.events.firstIndex(of: "gate.end")!
            precondition(reset < gate && gate < b.events.count - 1)
            events += a.events.count
        }
        for target in ["Dynamic Island", "Dock"] { for spanish in [false, true] {
            for reason in ["", "Session unavailable", "Reason\nwith unicode: sesión 🦅"] {
                for nilReport in [false, true] { for mutate in [false, true] {
                    let (a, b) = contexts(spanish: spanish, retained: 33, mutate: mutate, nilReport: nilReport)
                    let input = Input(previous: 1, applied: 32, pid: 123, target: target)
                    Runtime.context = a; PublicHost(context: a, input: input).failBeforeNativeCall(reason)
                    Runtime.context = b; OwnedHost(context: b, input: input).failBeforeNativeCall(reason)
                    compare(a, b)
                    precondition(b.retained == 33 && b.flags == 33 && b.pid == 999)
                    precondition(b.events.filter { $0 == "target.title:reset" }.count == 2)
                    precondition(b.events.filter { $0.hasPrefix("write.flags:") || $0.hasPrefix("write.retained:") }.isEmpty)
                    preflights += 1
                }}
            }
        }}
        let masks: [UInt32] = [0, 1, 32, 33, 8, UInt32.max]
        for previous in masks { for retained in masks { for applied in masks {
            for stepFlag: UInt32 in [0, 1, 32, UInt32.max] { for pid: Int32 in [0, 123] {
                for spanish in [false, true] { for result: Int32 in [-12, -24, Int32.min] {
                    for mutate in [false, true] {
                        let (a, b) = contexts(spanish: spanish, retained: retained, mutate: mutate, nilReport: rollbacks % 2 == 0)
                        let input = Input(previous: previous, applied: applied, pid: pid, target: "Dynamic Island")
                        let step = AuraStudioOperationStep(flag: stepFlag, englishName: "Dynamic Island")
                        Runtime.context = a; PublicHost(context: a, input: input).finishVerifiedRollback(result, step: step, reason: "verified rollback")
                        Runtime.context = b; OwnedHost(context: b, input: input).finishVerifiedRollback(result, step: step, reason: "verified rollback")
                        compare(a, b)
                        let finalRetained = retained | (previous & stepFlag), finalFlags = finalRetained | applied
                        precondition(b.retained == finalRetained && b.flags == Int(finalFlags))
                        precondition(b.pid == (finalFlags == 0 ? 0 : Int(pid)))
                        precondition(b.events.filter { $0 == "read.retained" }.count == 2)
                        precondition(b.events.contains("error.message:\(result)"))
                        precondition(b.islandMode == (mutate ? 14 : 4) && b.dockMode == (mutate ? 8 : 2))
                        rollbacks += 1
                    }
                }}
            }}
        }}}
        // Reuse the same state across repeated preflight failures and verified
        // Island/Dock rollbacks; no native work or automatic retry is performed.
        for encoded in 0..<81 { for spanish in [false, true] { for mutate in [false, true] {
            let (a, b) = contexts(spanish: spanish, retained: 0, mutate: mutate, nilReport: encoded % 2 == 0)
            let input = Input(previous: 33, applied: 0, pid: 123, target: "Dock")
            var digits = encoded
            for _ in 0..<4 {
                let action = digits % 3; digits /= 3
                for c in [a, b] { c.events = []; c.busy = true; c.gateHeld = true; c.phase = "initial" }
                for (c, isPublic) in [(a, true), (b, false)] {
                    Runtime.context = c
                    if action == 0 {
                        if isPublic { PublicHost(context: c, input: input).failBeforeNativeCall("preflight") }
                        else { OwnedHost(context: c, input: input).failBeforeNativeCall("preflight") }
                    } else {
                        let step = AuraStudioOperationStep(flag: action == 1 ? 1 : 32, englishName: action == 1 ? "Dynamic Island" : "Dock")
                        if isPublic { PublicHost(context: c, input: input).finishVerifiedRollback(-12, step: step, reason: "rollback") }
                        else { OwnedHost(context: c, input: input).finishVerifiedRollback(-12, step: step, reason: "rollback") }
                    }
                }
                compare(a, b); traceActions += 1
            }
        }}}
        print("PASS: \(preflights) preflight cases, \(rollbacks) verified-rollback cases, \(traceActions) sustained actions; \(events) exact ordered events; public parity and independent state/order checks")
    }
}
