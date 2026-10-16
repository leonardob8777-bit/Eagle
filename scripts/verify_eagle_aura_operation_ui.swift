import Foundation

struct AuraStudioNotice { let message: String }
struct Operation { let isRemoving: Bool }
@MainActor final class Context {
    var isApplying = false
    var operationIsRemoval = false
    var operationStepIndex = 0
    var operationStepCount = 0
    var activeOperationID: String?
    var applyStage = ""
    var notice: AuraStudioNotice?
    var gateHeld = true
    var spanish = false
    var events: [String] = []
    var queue: [@MainActor @Sendable () -> Void] = []
    var state: String {
        "\(isApplying)|\(operationIsRemoval)|\(operationStepIndex)|\(operationStepCount)|\(activeOperationID ?? "nil")|\(applyStage)|\(notice?.message ?? "nil")|\(gateHeld)"
    }
    func record(_ field: String) { events.append("write:\(field):\(state)") }
}
@MainActor enum Runtime { static var context: Context? }
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Runtime.context!.events.append("text:\(en)|\(es)")
        return Runtime.context!.spanish ? es : en
    }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String) { Runtime.context!.events.append("log:\(stage):\(detail)") }
}
@MainActor enum AuraStudioApplyGate {
    static func end() {
        let c = Runtime.context!; c.events.append("gate.end"); c.gateHeld = false
    }
}
@MainActor struct Scheduler {
    func async(execute action: @escaping @MainActor @Sendable () -> Void) {
        let c = Runtime.context!; c.events.append("enqueue"); c.queue.append(action)
    }
}
@MainActor enum DispatchQueue { static let main = Scheduler() }
@MainActor protocol Host { var context: Context { get } }

@main struct Check {
    @MainActor static func main() {
        let a = Context(), b = Context()
        let old = PublicHost(context: a), owned = OwnedHost(context: b)
        var sequences = 0, actions = 0, events = 0
        // Exhaustive short interaction traces include queued finishes, repeated
        // resets and new starts before draining pending main-queue callbacks.
        for encoded in 0..<3125 { for spanish in [false, true] {
            for c in [a, b] {
                c.isApplying = false; c.operationIsRemoval = false; c.operationStepIndex = 3
                c.operationStepCount = 7; c.activeOperationID = "previous"; c.applyStage = "prior"
                c.notice = AuraStudioNotice(message: "old notice"); c.gateHeld = true
                c.queue = []; c.events = []; c.spanish = spanish
            }
            var digits = encoded
            for index in 0..<6 {
                let op = index == 5 ? 4 : digits % 5
                digits /= 5
                a.events = []; b.events = []
                let before = b.state, oldNotice = b.notice?.message, oldGate = b.gateHeld
                let queued = b.queue.count
                for (c, isOld) in [(a, true), (b, false)] {
                    Runtime.context = c
                    switch op {
                    case 0:
                        if isOld { old.begin(Operation(isRemoving: false), [1], "apply-\(index)") }
                        else { owned.begin(Operation(isRemoving: false), [1], "apply-\(index)") }
                    case 1:
                        if isOld { old.begin(Operation(isRemoving: true), [1, 32], "remove-\(index)") }
                        else { owned.begin(Operation(isRemoving: true), [1, 32], "remove-\(index)") }
                    case 2:
                        if isOld { old.reset() } else { owned.reset() }
                    case 3:
                        if isOld { old.end("failure-\(index)") } else { owned.end("failure-\(index)") }
                    default:
                        while !c.queue.isEmpty { c.queue.removeFirst()() }
                    }
                }
                precondition(a.state == b.state && a.events == b.events && a.queue.count == b.queue.count)
                let trace = b.events
                if op < 2 {
                    precondition(b.isApplying && b.operationIsRemoval == (op == 1))
                    precondition(b.operationStepIndex == 0 && b.operationStepCount == (op == 0 ? 1 : 2))
                    precondition(b.applyStage == (spanish ? "Preparando una sesión nueva de SpringBoard…" : "Preparing a fresh SpringBoard session…"))
                    precondition(b.notice?.message == oldNotice && b.gateHeld == oldGate && b.queue.count == queued)
                    precondition(trace.count == 7 && trace[0].hasPrefix("write:isApplying:"))
                } else if op == 2 {
                    precondition(!b.isApplying && !b.operationIsRemoval && b.activeOperationID == nil)
                    precondition(b.operationStepIndex == 0 && b.operationStepCount == 0 && b.applyStage.isEmpty)
                    precondition(b.notice?.message == oldNotice && b.gateHeld == oldGate && b.queue.count == queued)
                    precondition(trace.count == 6 && trace[5].hasPrefix("write:activeOperationID:"))
                } else if op == 3 {
                    precondition(b.state == before && b.queue.count == queued + 1)
                    precondition(trace == ["log:finish:error=true", "enqueue"])
                } else {
                    precondition(b.queue.isEmpty && trace.count == queued * 8)
                    if queued > 0 {
                        precondition(!b.gateHeld && !b.isApplying && b.activeOperationID == nil)
                        for start in stride(from: 0, to: trace.count, by: 8) {
                            precondition(trace[start] == "gate.end")
                            precondition(trace[start + 1].hasPrefix("write:activeOperationID:"))
                            precondition(trace[start + 7].hasPrefix("write:notice:"))
                        }
                    }
                }
                actions += 1; events += trace.count
            }
            sequences += 1
        } }
        Runtime.context = nil
        print("PASS: \(sequences) queued lifecycle sequences, \(actions) actions, \(events) ordered state/log/queue events; no early finish writes or new gate release")
    }
}
