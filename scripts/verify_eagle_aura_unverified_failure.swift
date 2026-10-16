import Foundation

struct AuraStudioNotice { let message: String }
enum Flag { static let island: UInt32 = 1; static let dock: UInt32 = 32 }
struct Input { let retained: UInt32; let applied: UInt32; let removed: UInt32; let target: String }
@MainActor final class Context {
    var events: [String] = []
    var fields = ["activeModeRaw": 4, "activeIslandModeRaw": 4, "activeDockModeRaw": 2, "activeSpringBoardPID": 999]
    var flags = 33
    var overrides: [Int] = []
    var flagReads = 0
    var pid: Int32 = 123
    var safetyBlocked = false
    var quarantined = false
    var gateLocked = false
    var busy = true
    var spanish = false
    var url: URL?
    var notice: AuraStudioNotice?
    var phase = "initial"
    var state: String {
        "\(flags)|\(fields.sorted { $0.key < $1.key })|\(safetyBlocked)|\(quarantined)|\(gateLocked)|\(busy)|\(url?.absoluteString ?? "nil")|\(notice?.message ?? "nil")"
    }
    func report(_ reason: String) -> URL? {
        events.append("report:\(reason)")
        precondition(quarantined && gateLocked && safetyBlocked)
        return reason.isEmpty ? nil : URL(string: "https://fixture.invalid/report")
    }
}
@MainActor enum Runtime { static var context: Context! }
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String) { Runtime.context.events.append("log:\(stage):\(detail)") }
}
@MainActor enum AuraStudioApplyGate {
    static func lock() { Runtime.context.events.append("gate.lock"); Runtime.context.gateLocked = true }
}
@MainActor struct Manager {
    func quarantineRemoteCall(reason: String) {
        Runtime.context.events.append("quarantine:\(reason)"); Runtime.context.quarantined = true
    }
}
@MainActor struct Target {
    let name: String
    var title: String {
        Runtime.context.events.append("target.title:\(Runtime.context.phase)")
        return "\(name)-\(Runtime.context.phase)"
    }
}
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    precondition(String(cString: name) == "SpringBoard")
    Runtime.context.events.append("pid.read"); return Runtime.context.pid
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Runtime.context.events.append("text:\(en)|\(es)")
        return Runtime.context.spanish ? es : en
    }
}
@MainActor protocol Host { var context: Context { get }; var input: Input { get } }
extension Host {
    var operationID: String { "test-unverified" }
    var retainedVerified: UInt32 { input.retained }
    var newlyApplied: UInt32 { input.applied }
    var removedFlags: UInt32 { input.removed }
    var operationTarget: Target { Target(name: input.target) }
    var mgr: Manager { Manager() }
    var activeFlagsRaw: Int {
        get {
            let c = context, n = c.flagReads; c.flagReads += 1
            let value = n < c.overrides.count ? c.overrides[n] : c.flags
            c.events.append("read.flags:\(value)"); return value
        }
        nonmutating set { context.flags = newValue; context.events.append("write.flags:\(newValue)") }
    }
    var applySafetyBlocked: Bool {
        get { context.safetyBlocked }
        nonmutating set { context.safetyBlocked = newValue; context.events.append("write.safety:\(newValue)") }
    }
    var diagnosticsURL: URL? {
        get { context.url }
        nonmutating set { context.url = newValue; context.events.append("write.report:\(newValue?.absoluteString ?? "nil")") }
    }
    var notice: AuraStudioNotice? {
        get { context.notice }
        nonmutating set {
            precondition(!context.busy && context.safetyBlocked && context.quarantined && context.gateLocked)
            context.notice = newValue; context.events.append("notice:\(newValue?.message ?? "nil")")
        }
    }
    func makeDiagnosticsReport(summary: String) -> URL? { context.report(summary) }
    func resetOperationUI() { context.busy = false; context.phase = "reset"; context.events.append("reset") }
}
@main struct Check {
    @MainActor static func main() {
        var cases = 0, actions = 0, events = 0
        let masks: [UInt32] = [0, 1, 32, 33, 8, UInt32.max]
        let scripts: [[Int]] = [[], [0, 0, 0], [1, 32, 33], [0, 32, 0]]
        for retained in masks { for applied in masks { for spanish in [false, true] {
            for pid: Int32 in [0, 123, -1] { for result: Int32? in [nil, -12, Int32.min] {
                for detail: String? in [nil, "", "Detalle\nsecond line 🦅"] { for target in ["Dynamic Island", "Dock"] {
                    for reads in scripts {
                        let a = Context(), b = Context()
                        for c in [a, b] { c.pid = pid; c.spanish = spanish; c.overrides = reads }
                        let input = Input(retained: retained, applied: applied, removed: cases % 2 == 0 ? 1 : 32, target: target)
                        for attempt in 0..<2 {
                            let reason = attempt == 0 ? "Unverified session" : ""
                            for c in [a, b] { c.events = []; c.flagReads = 0; c.busy = true; c.phase = "initial" }
                            Runtime.context = a
                            PublicHost(context: a, input: input).failAfterNativeCall(reason, result: result, userDetail: detail)
                            Runtime.context = b
                            OwnedHost(context: b, input: input).failAfterNativeCall(reason, result: result, userDetail: detail)
                            precondition(a.events == b.events && a.state == b.state, "Public/owned mismatch at \(cases):\(attempt)")
                            precondition(b.flagReads == 3 && b.flags == Int(retained | applied))
                            let actualReads = reads.isEmpty ? Array(repeating: Int(retained | applied), count: 3) : reads
                            if actualReads[0] & 1 == 0 { precondition(b.fields["activeModeRaw"] == 0 && b.fields["activeIslandModeRaw"] == 0) }
                            else { precondition(b.fields["activeModeRaw"] == 4 && b.fields["activeIslandModeRaw"] == 4) }
                            precondition(b.fields["activeDockModeRaw"] == (actualReads[1] & 32 == 0 ? 0 : 2))
                            precondition(b.fields["activeSpringBoardPID"] == (actualReads[2] == 0 ? 0 : Int(pid)))
                            precondition(b.events.filter { $0 == "pid.read" }.count == (actualReads[2] == 0 ? 0 : 1))
                            precondition(b.events.firstIndex(of: "quarantine:\(reason)")! < b.events.firstIndex(of: "write.safety:true")!)
                            precondition(b.events.firstIndex(of: "write.safety:true")! < b.events.firstIndex(of: "gate.lock")!)
                            precondition(b.events.firstIndex(of: "gate.lock")! < b.events.firstIndex(of: "report:\(reason)")!)
                            precondition(b.events.filter { $0 == "target.title:reset" }.count == 2)
                            if let detail { precondition(b.notice!.message.hasSuffix("\n\n" + detail)) }
                            precondition(b.events.last?.hasPrefix("notice:") == true)
                            actions += 1; events += b.events.count
                        }
                        cases += 1
                    }
                }}
            }}
        }}}
        print("PASS: \(cases) unverified-failure scenarios, \(actions) repeated actions, \(events) ordered events; public parity, lazy PID, preserved reads and fail-closed order")
    }
}
