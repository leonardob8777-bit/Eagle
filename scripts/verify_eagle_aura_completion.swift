import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum EagleNoticeKind: String { case information, error, success }
struct Operation { let isRemoving: Bool }
struct Input {
    let retained: UInt32
    let applied: UInt32
    let removed: UInt32
    let requested: UInt32
    let removing: Bool
    let pid: Int32
    let mode: Int
    let degraded: Bool
    let unavailable: Int32?
    let fallback: Int32?
}
@MainActor final class Context {
    var fields = ["activeFlagsRaw": 33, "activeModeRaw": 1, "activeIslandModeRaw": 4,
                  "activeDockModeRaw": 2, "activeSpringBoardPID": 999]
    var events: [String] = []
    var url: URL?
    var spanish = false
    var busy = true
    var gateHeld = true
    var mutateDuringReport = false
    func read(_ key: String) -> Int {
        events.append("read:\(key)"); return fields[key]!
    }
    func write(_ key: String, _ value: Int) {
        fields[key] = value; events.append("write:\(key)=\(value)")
    }
    func report(_ summary: String) -> URL? {
        events.append("report:\(summary)")
        if mutateDuringReport { fields["activeIslandModeRaw"] = 14 }
        return summary.hasPrefix("No mutation") ? nil : URL(string: "https://fixture.invalid/report")
    }
    func reset() { events.append("reset"); busy = false }
}
@MainActor enum Runtime { static var context: Context! }
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Runtime.context.events.append("text:\(en)|\(es)")
        return Runtime.context.spanish ? es : en
    }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String) {
        Runtime.context.events.append("log:\(stage):\(detail)")
    }
}
@MainActor enum AuraStudioApplyGate {
    static func end() { Runtime.context.events.append("gate.end"); Runtime.context.gateHeld = false }
}
@MainActor final class EagleNotifications {
    static let shared = EagleNotifications()
    func show(title: String, message: String, kind: EagleNoticeKind) {
        let c = Runtime.context!
        precondition(!c.busy, "Notice before UI cleanup")
        c.events.append("notice:\(title):\(kind.rawValue):\(message)")
    }
}
@MainActor protocol Host { var context: Context { get }; var input: Input { get } }
extension Host {
    var retainedVerified: UInt32 { input.retained }
    var newlyApplied: UInt32 { input.applied }
    var removedFlags: UInt32 { input.removed }
    var requestedFlags: UInt32 { input.requested }
    var operation: Operation { Operation(isRemoving: input.removing) }
    var operationSpringBoardPID: Int32 { input.pid }
    var operationID: String { "test-operation" }
    var mode: Int { input.mode }
    var motionDegraded: Bool { input.degraded }
    var firstUnavailableResult: Int32? { input.unavailable }
    var verifiedFallbackResult: Int32? { input.fallback }
    func makeDiagnosticsReport(summary: String) -> URL? { context.report(summary) }
    func resetOperationUI() { context.reset() }
    func message(for result: Int32) -> String {
        context.events.append("error.message:\(result)"); return "error-\(result)"
    }
    func successMessage(appliedFlags: UInt32, requestedFlags: UInt32, restoring: Bool,
                        motionDegraded: Bool, appliedMode: AuraStudioMode?) -> String {
        let value = "\(appliedFlags)|\(requestedFlags)|\(restoring)|\(motionDegraded)|\(appliedMode?.rawValue ?? -1)"
        context.events.append("success.message:\(value)"); return value
    }
}

@main struct Check {
    @MainActor static func main() {
        var scenarios = 0, events = 0
        let masks: [UInt32] = [0, 1, 32, 33, 8, UInt32.max]
        let results: [Int32?] = [nil, -2, -15]
        for retained in masks { for applied in masks {
            for removing in [false, true] { for degraded in [false, true] {
                for unavailable in results { for fallback in results {
                    for deadline in [false, true] { for spanish in [false, true] {
                        for mode in [0, 1, 4, 14, 999] {
                            let input = Input(retained: retained, applied: applied,
                                              removed: removing ? 33 : 0, requested: 33,
                                              removing: removing, pid: scenarios % 2 == 0 ? 123 : 0,
                                              mode: mode, degraded: degraded,
                                              unavailable: unavailable, fallback: fallback)
                            let a = Context(), b = Context()
                            for c in [a, b] { c.spanish = spanish; c.mutateDuringReport = scenarios % 2 == 0 }
                            Runtime.context = a
                            PublicHost(context: a, input: input).completeSuccess(deadlineWarning: deadline)
                            Runtime.context = b
                            OwnedHost(context: b, input: input).completeSuccess(deadlineWarning: deadline)
                            precondition(a.events == b.events, "Event mismatch at \(scenarios)")
                            precondition(a.fields == b.fields && a.url == b.url && a.busy == b.busy && a.gateHeld == b.gateHeld)
                            precondition(b.fields["activeFlagsRaw"] == Int(retained | applied))
                            precondition(b.gateHeld == deadline, "Deadline must not release gate")
                            precondition(b.events.filter { $0 == "reset" }.count == 1)
                            precondition(b.events.last?.hasPrefix("notice:Aura Studio:") == true)
                            let kind = deadline || degraded || fallback != nil ? "information" :
                                (!removing && applied == 0 && unavailable != nil ? "error" : "success")
                            precondition(b.events.last?.hasPrefix("notice:Aura Studio:\(kind):") == true)
                            if let fallback {
                                precondition(b.events.contains("error.message:\(fallback)"))
                            } else if !removing && applied == 0, let unavailable {
                                precondition(b.events.contains("error.message:\(unavailable)"))
                            } else {
                                precondition(b.events.filter { $0.hasPrefix("success.message:") }.count == 1)
                            }
                            scenarios += 1; events += a.events.count
                        }
                    }}
                }}
            }}
        }}
        print("PASS: Aura completion \(scenarios) public/owned cases and \(events) ordered events; state/report/reset/gate/message/notice parity")
    }
}
