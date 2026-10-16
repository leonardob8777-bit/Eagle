import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
struct Operation { let isRemoving: Bool }
struct AuraStudioOperationStep { let flag: UInt32; let englishName: String; let spanishName: String }
struct AuraStudioNotice { let message: String }
enum EagleNoticeKind: String { case information, error, success }
enum Flag {
    static let island: UInt32 = 1, screen: UInt32 = 2, battery: UInt32 = 4, dock: UInt32 = 32, lock: UInt32 = 64
}
@MainActor final class Context {
    var activeFlagsRaw = 33, activeModeRaw = 4, activeIslandModeRaw = 4, activeDockModeRaw = 2, activeSpringBoardPID = 123
    var operationStepIndex = 0, operationStepCount = 0
    var applySafetyBlocked = false, isApplying = false, operationIsRemoval = false
    var applyStage = ""
    var activeOperationID: String?
    var retainedVerified: UInt32 = 33
    var newlyApplied: UInt32 = 1, removedFlags: UInt32 = 0, previouslyVerified: UInt32 = 33
    var requestedFlags: UInt32 = 1
    var removing = false, degraded = false, deadline = false, spanish = false
    var firstUnavailableResult: Int32?, verifiedFallbackResult: Int32?
    var mode = 1
    var pid: Int32 = 123
    var events: [String] = []
    var queue: [@MainActor @Sendable () -> Void] = []
    var gateHeld = true, gateLocked = false, quarantined = false
    var notice: AuraStudioNotice?
    var url: URL?
    var notification = ""
    var reportIndex = 0
    var state: String {
        "\(activeFlagsRaw)|\(activeModeRaw)|\(activeIslandModeRaw)|\(activeDockModeRaw)|\(activeSpringBoardPID)|\(operationStepIndex)|\(operationStepCount)|\(applySafetyBlocked)|\(isApplying)|\(operationIsRemoval)|\(applyStage)|\(activeOperationID ?? "nil")|\(retainedVerified)|\(gateHeld)|\(gateLocked)|\(quarantined)|\(notice?.message ?? "nil")|\(url?.absoluteString ?? "nil")|\(notification)|\(queue.count)"
    }
    func drain() { let pending = queue; queue = []; for action in pending { action() } }
}
@MainActor enum Runtime { static var context: Context! }
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Runtime.context.events.append("text:\(en)|\(es)")
        return Runtime.context.spanish ? es : en
    }
}
extension EagleAuraStudioMode {
    @MainActor var title: String { title(localizedText: { LaraL10n.text(en: $0, es: $1) }) }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String) { Runtime.context.events.append("log:\(stage):\(detail)") }
}
@MainActor enum AuraStudioApplyGate {
    static func end() { Runtime.context.events.append("gate.end"); Runtime.context.gateHeld = false }
    static func lock() { Runtime.context.events.append("gate.lock"); Runtime.context.gateHeld = false; Runtime.context.gateLocked = true }
}
@MainActor struct Manager {
    func quarantineRemoteCall(reason: String) {
        Runtime.context.events.append("quarantine:\(reason)"); Runtime.context.quarantined = true
    }
}
@MainActor struct Target {
    var title: String { Runtime.context.requestedFlags == 1 ? "Dynamic Island" : "Dock" }
}
@MainActor struct Scheduler {
    func async(execute action: @escaping @MainActor @Sendable () -> Void) {
        Runtime.context.events.append("enqueue"); Runtime.context.queue.append(action)
    }
}
@MainActor enum DispatchQueue { static let main = Scheduler() }
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    precondition(String(cString: name) == "SpringBoard")
    Runtime.context.events.append("pid.read"); return Runtime.context.pid
}
@MainActor final class EagleNotifications {
    static let shared = EagleNotifications()
    func show(title: String, message: String, kind: EagleNoticeKind) {
        let c = Runtime.context!
        precondition(!c.isApplying)
        c.notification = "\(title)|\(kind.rawValue)|\(message)"
        c.events.append("notification:\(c.notification)")
    }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    var operationID: String { "integrated-operation" }
    var operation: Operation { Operation(isRemoving: context.removing) }
    var operationTarget: Target { Target() }
    var operationSpringBoardPID: Int32 { context.pid }
    var newlyApplied: UInt32 { context.newlyApplied }
    var removedFlags: UInt32 { context.removedFlags }
    var previouslyVerified: UInt32 { context.previouslyVerified }
    var requestedFlags: UInt32 { context.requestedFlags }
    var firstUnavailableResult: Int32? { context.firstUnavailableResult }
    var verifiedFallbackResult: Int32? { context.verifiedFallbackResult }
    var motionDegraded: Bool { context.degraded }
    var mode: Int { context.mode }
    var mgr: Manager { Manager() }
    var steps: [AuraStudioOperationStep] {
        [AuraStudioOperationStep(flag: requestedFlags, englishName: operationTarget.title, spanishName: operationTarget.title)]
    }
    var diagnosticsURL: URL? {
        get { context.url }
        nonmutating set { context.url = newValue; context.events.append("report.write:\(newValue?.absoluteString ?? "nil")") }
    }
    var notice: AuraStudioNotice? {
        get { context.notice }
        nonmutating set {
            precondition(!context.isApplying)
            context.notice = newValue; context.events.append("notice:\(newValue?.message ?? "nil")")
        }
    }
    func makeDiagnosticsReport(summary: String) -> URL? {
        context.events.append("report.create:\(summary)"); context.reportIndex += 1
        return context.reportIndex % 2 == 0 ? nil : URL(string: "https://fixture.invalid/report")
    }
}

@main struct Check {
    @MainActor static func main() {
        var journeys = 0, actions = 0, events = 0
        let modes = [0, 1, 2, 3, 4, 8, 14, 999]
        for target: UInt32 in [1, 32] { for spanish in [false, true] {
            for removing in [false, true] { for mode in modes { for variant in 0..<16 {
                let a = Context(), b = Context()
                for c in [a, b] {
                    c.requestedFlags = target; c.spanish = spanish; c.removing = removing; c.mode = mode
                    c.degraded = variant & 1 != 0; c.deadline = variant & 2 != 0
                    c.firstUnavailableResult = variant & 4 != 0 ? -20 : nil
                    c.verifiedFallbackResult = variant & 8 != 0 ? -16 : nil
                }
                let old = PublicHost(context: a), owned = OwnedHost(context: b)
                // Six endings run through the real owned UI reset/result modules,
                // each with a fresh simulated session, retaining preference state.
                for ending in 0..<6 {
                    for c in [a, b] {
                        c.events = []; c.gateHeld = true; c.gateLocked = false; c.quarantined = false; c.applySafetyBlocked = false
                        c.retainedVerified = ending % 2 == 0 ? 33 & ~target : 0
                        c.newlyApplied = (ending % 2 == 0 && !removing) ? target : 0
                        c.removedFlags = removing ? target : 0
                    }
                    func check() {
                        precondition(a.events == b.events, "Events differ at journey \(journeys), ending \(ending)")
                        precondition(a.state == b.state, "State differs")
                        events += a.events.count; actions += 1
                        a.events = []; b.events = []
                    }
                    Runtime.context = a; old.begin()
                    Runtime.context = b; owned.begin()
                    check(); precondition(b.isApplying && b.operationStepCount == 1)
                    for (c, isPublic) in [(a, true), (b, false)] {
                        Runtime.context = c
                        switch ending {
                        case 0, 1:
                            if isPublic { old.completeSuccess(deadlineWarning: c.deadline) }
                            else { owned.completeSuccess(deadlineWarning: c.deadline) }
                        case 2:
                            if isPublic { old.failBeforeNativeCall("unavailable") }
                            else { owned.failBeforeNativeCall("unavailable") }
                        case 3:
                            let step = AuraStudioOperationStep(flag: target, englishName: c.requestedFlags == 1 ? "Dynamic Island" : "Dock", spanishName: "unused")
                            if isPublic { old.finishVerifiedRollback(-12, step: step, reason: "verified") }
                            else { owned.finishVerifiedRollback(-12, step: step, reason: "verified") }
                        case 4:
                            if isPublic { old.failAfterNativeCall("unverified", result: -24, userDetail: "Detail") }
                            else { owned.failAfterNativeCall("unverified", result: -24, userDetail: "Detail") }
                        default:
                            if isPublic { old.finishError("early error") }
                            else { owned.finishError("early error") }
                        }
                    }
                    check()
                    if ending == 5 { precondition(b.isApplying && b.queue.count == 1) }
                    Runtime.context = a; a.drain()
                    Runtime.context = b; b.drain()
                    check(); precondition(!b.isApplying && b.activeOperationID == nil && b.operationStepCount == 0)
                    if ending == 4 { precondition(b.gateLocked && b.quarantined && b.applySafetyBlocked) }
                    else if ending < 2 && b.deadline { precondition(b.gateHeld) }
                    else { precondition(!b.gateHeld) }
                }
                journeys += 1
            }}}
        }}
        print("PASS: \(journeys) integrated Aura operation journeys, \(actions) actions, \(events) exact events; six endings, real owned lifecycle/messages, both profiles/languages")
    }
}
