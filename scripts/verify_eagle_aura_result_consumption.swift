import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
typealias AuraStudioTarget = EagleAuraStudioTarget
enum Flag {
    static let island: UInt32 = 1
    static let dock: UInt32 = 1 << 5
    static let supported = island | dock
    static let motionDegraded: UInt32 = 1 << 30
}
@MainActor final class Context {
    var events: [String] = []
    var retained: UInt32 = 33
    var newly: UInt32 = 0
    var removed: UInt32 = 0
    var unavailable: Int32?
    var fallback: Int32?
    var degraded = false
    var deadline = false
    var spanish = false
    var observedWrites = false
    var stored = [33, 4, 4, 2, 77, 101, 11, 22, 33, 44, 55, 66]
    var outcome = ""
    func read(_ index: Int) -> Int {
        events.append("read.stored.\(index)"); return stored[index]
    }
    func write(_ index: Int, _ value: Int) {
        events.append("write.stored.\(index)=\(value)"); stored[index] = value
        // Simulate synchronous preference observers; later reads must not be snapshotted.
        if observedWrites && index == 0 { stored[0] = 0 }
    }
    var snapshot: [String] {
        events + ["stored=\(stored)", "retained=\(retained)", "newly=\(newly)", "removed=\(removed)",
                  "unavailable=\(String(describing: unavailable))", "fallback=\(String(describing: fallback))",
                  "degraded=\(degraded)", "deadline=\(deadline)", "outcome=\(outcome)"]
    }
}
@MainActor enum World { static var context = Context() }
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        World.context.events.append("localized")
        return World.context.spanish ? es : en
    }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ key: String, _ detail: String) {
        World.context.events.append("log.\(key).\(detail)")
    }
}
@MainActor protocol Host {
    var context: Context { get }
    func consume(result: Int32, operation: EagleAuraStudioOperation, operationID: String,
                 operationTarget: EagleAuraStudioTarget, requestedProfileMode: EagleAuraStudioMode,
                 step: EagleAuraStudioOperationStep, index: Int, previouslyVerified: UInt32,
                 springBoardPID: Int32, mode: Int, redValue: Int32, greenValue: Int32, blueValue: Int32)
}
extension Host {
    func completeSuccess(deadlineWarning: Bool = false) {
        context.events.append("complete.\(deadlineWarning)"); context.outcome = "complete.\(deadlineWarning)"
    }
    func runStep(_ index: Int) { context.events.append("next.\(index)"); context.outcome = "next.\(index)" }
    func message(for result: Int32) -> String { context.events.append("message.\(result)"); return "message.\(result)" }
    func failAfterNativeCall(_ reason: String, result: Int32? = nil, userDetail: String? = nil) {
        context.events.append("failure.\(reason).\(String(describing: result)).\(userDetail ?? "nil")")
        context.outcome = "failure"
    }
    func finishVerifiedRollback(_ result: Int32, step: EagleAuraStudioOperationStep, reason: String) {
        context.events.append("rollback.\(result).\(step.flag).\(reason)"); context.outcome = "rollback"
    }
    var activeFlagsRaw: Int {
        get { context.read(0) }
        nonmutating set { context.write(0, newValue) }
    }
    var activeModeRaw: Int {
        get { context.read(1) }
        nonmutating set { context.write(1, newValue) }
    }
    var activeIslandModeRaw: Int {
        get { context.read(2) }
        nonmutating set { context.write(2, newValue) }
    }
    var activeDockModeRaw: Int {
        get { context.read(3) }
        nonmutating set { context.write(3, newValue) }
    }
    var activeDockGalleryStyleRaw: Int {
        get { context.read(4) }
        nonmutating set { context.write(4, newValue) }
    }
    var activeSpringBoardPID: Int {
        get { context.read(5) }
        nonmutating set { context.write(5, newValue) }
    }
    var activeIslandRed: Int {
        get { context.read(6) }
        nonmutating set { context.write(6, newValue) }
    }
    var activeIslandGreen: Int {
        get { context.read(7) }
        nonmutating set { context.write(7, newValue) }
    }
    var activeIslandBlue: Int {
        get { context.read(8) }
        nonmutating set { context.write(8, newValue) }
    }
    var activeDockRed: Int {
        get { context.read(9) }
        nonmutating set { context.write(9, newValue) }
    }
    var activeDockGreen: Int {
        get { context.read(10) }
        nonmutating set { context.write(10, newValue) }
    }
    var activeDockBlue: Int {
        get { context.read(11) }
        nonmutating set { context.write(11, newValue) }
    }
    var retainedVerified: UInt32 {
        get { context.events.append("read.retained"); return context.retained }
        nonmutating set { context.events.append("write.retained=\(String(describing: newValue))"); context.retained = newValue }
    }
    var newlyApplied: UInt32 {
        get { context.events.append("read.newly"); return context.newly }
        nonmutating set { context.events.append("write.newly=\(String(describing: newValue))"); context.newly = newValue }
    }
    var removedFlags: UInt32 {
        get { context.events.append("read.removed"); return context.removed }
        nonmutating set { context.events.append("write.removed=\(String(describing: newValue))"); context.removed = newValue }
    }
    var firstUnavailableResult: Int32? {
        get { context.events.append("read.unavailable"); return context.unavailable }
        nonmutating set { context.events.append("write.unavailable=\(String(describing: newValue))"); context.unavailable = newValue }
    }
    var verifiedFallbackResult: Int32? {
        get { context.events.append("read.fallback"); return context.fallback }
        nonmutating set { context.events.append("write.fallback=\(String(describing: newValue))"); context.fallback = newValue }
    }
    var motionDegraded: Bool {
        get { context.events.append("read.degraded"); return context.degraded }
        nonmutating set { context.events.append("write.degraded=\(String(describing: newValue))"); context.degraded = newValue }
    }
    var hardDeadlineExceeded: Bool {
        get { context.events.append("read.deadline"); return context.deadline }
        nonmutating set { context.events.append("write.deadline=\(String(describing: newValue))"); context.deadline = newValue }
    }
}
@main struct Runner {
    @MainActor static func main() {
        var count = 0, effectCount = 0
        func compare(_ result: Int32, target: EagleAuraStudioTarget = .dock,
                     mode: EagleAuraStudioMode = .glow, remove: Bool = false,
                     deadline: Bool = false, state: Int = 0, spanish: Bool = false,
                     observe: Bool = false) -> Context {
            let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
            let step = EagleAuraStudioOperationStep(flag: target == .island ? Flag.island : Flag.dock,
                                                   englishName: target == .island ? "Dynamic Island" : "Dock",
                                                   spanishName: target == .island ? "Isla" : "Dock")
            let previous: UInt32 = state == 4 ? 1 : 33
            for host in [old as any Host, owned as any Host] {
                let c = host.context
                c.deadline = deadline; c.spanish = spanish; c.observedWrites = observe
                switch state {
                case 1: c.retained = 1; c.stored[0] = 1
                case 2: c.retained = 32; c.stored[0] = 32
                case 3: c.retained = 0; c.stored[0] = 0
                case 4: c.newly = 1; c.retained = 32
                case 5: c.unavailable = -77; c.fallback = -88
                case 6: c.removed = 1; c.degraded = true
                case 7: c.retained = .max; c.newly = 32; c.removed = 32
                default: break
                }
                World.context = c
                host.consume(result: result, operation: remove ? .remove : .apply(mode), operationID: "run",
                             operationTarget: target, requestedProfileMode: remove ? .glow : mode, step: step,
                             index: 2, previouslyVerified: previous, springBoardPID: 202,
                             mode: remove ? 0 : mode.rawValue, redValue: 123, greenValue: 45, blueValue: 210)
            }
            precondition(old.context.snapshot == owned.context.snapshot,
                         "Consumption mismatch: \(result) \(target) \(mode) \(remove) \(deadline) \(state)\n\(old.context.snapshot)\n\(owned.context.snapshot)")
            count += 1; effectCount += old.context.events.count
            return owned.context
        }
        // Independent profile invariants for success/removal/fallback and failure.
        let dock = compare(32)
        precondition(dock.stored == [33, 4, 4, 1, 0, 202, 11, 22, 33, 123, 45, 210])
        precondition(dock.retained == 1 && dock.newly == 32 && dock.outcome == "next.3")
        let island = compare(1, target: .island, mode: .rainbow)
        precondition(island.stored == [33, 4, 4, 2, 77, 202, 123, 45, 210, 44, 55, 66])
        precondition(island.retained == 32 && island.newly == 1)
        let removal = compare(0, remove: true)
        precondition(removal.stored == [1, 4, 4, 0, 0, 202, 11, 22, 33, 44, 55, 66])
        precondition(removal.removed == 32 && removal.newly == 0)
        let lastRemoval = compare(0, remove: true, state: 2)
        precondition(lastRemoval.stored[0] == 0 && lastRemoval.stored[5] == 0)
        let fallback = compare(-15, target: .island, mode: .rainbow)
        precondition(fallback.fallback == -15 && fallback.stored[1] == 1 && fallback.stored[2] == 1)
        precondition(Array(fallback.stored[9...11]) == [44, 55, 66])
        let unavailable = compare(-20, state: 5)
        precondition(unavailable.unavailable == -77 && unavailable.fallback == -88)
        precondition(unavailable.outcome == "next.3" && unavailable.stored[4] == 77)
        let wrongSurface = compare(33)
        precondition(wrongSurface.outcome == "failure" && wrongSurface.retained == 1 && wrongSurface.newly == 0)
        precondition(wrongSurface.stored == [33, 4, 4, 2, 77, 101, 11, 22, 33, 44, 55, 66])
        let rollback = compare(-12, target: .island)
        precondition(rollback.outcome == "rollback" && rollback.retained == 33)
        precondition(compare(-12, target: .island, deadline: true).outcome == "failure")
        precondition(compare(32, deadline: true).outcome == "complete.true")
        precondition(compare(Int32(Flag.motionDegraded | Flag.dock)).degraded)
        // The preference read following a flags write must observe synchronous effects.
        precondition(compare(0, remove: true, observe: true).stored[5] == 0)
        let results: [Int32] = [-100, -26, -20, -17, -16, -15, -12, -2, -1, 0, 1, 2, 16, 32, 33, 34,
                               Int32(Flag.motionDegraded), Int32(Flag.motionDegraded | 1),
                               Int32(Flag.motionDegraded | 32), Int32(Flag.motionDegraded | 33), .max]
        for target in [EagleAuraStudioTarget.island, .dock] {
            for mode in EagleAuraStudioMode.allCases {
                for remove in [false, true] {
                    for result in results {
                        for deadline in [false, true] {
                            for state in 0..<8 {
                                for spanish in [false, true] {
                                    _ = compare(result, target: target, mode: mode, remove: remove,
                                                deadline: deadline, state: state, spanish: spanish, observe: state == 7)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Repeated operations share the same saved profile, including interleaved surfaces.
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        let sequence: [(EagleAuraStudioTarget, EagleAuraStudioMode, Bool, Int32)] = [
            (.dock, .glow, false, 32), (.island, .rainbow, false, -15),
            (.dock, .glow, true, 0), (.island, .glow, true, 0),
            (.dock, .pulse, false, 32), (.island, .tint, false, -16),
            (.dock, .glow, false, -20), (.island, .glow, false, -12)]
        for _ in 0..<16 {
            for (target, mode, remove, result) in sequence {
                for host in [old as any Host, owned as any Host] {
                    let c = host.context
                    c.events = []; c.outcome = ""; c.retained = UInt32(c.stored[0]); c.newly = 0
                    c.removed = 0; c.unavailable = nil; c.fallback = nil; c.degraded = false
                    World.context = c
                    let flag = target == .island ? Flag.island : Flag.dock
                    host.consume(result: result, operation: remove ? .remove : .apply(mode), operationID: "sequence",
                                 operationTarget: target, requestedProfileMode: remove ? .glow : mode,
                                 step: .init(flag: flag, englishName: target == .island ? "Island" : "Dock", spanishName: "perfil"),
                                 index: 0, previouslyVerified: c.retained, springBoardPID: 202, mode: mode.rawValue,
                                 redValue: 17, greenValue: 128, blueValue: 249)
                }
                precondition(old.context.snapshot == owned.context.snapshot)
                count += 1; effectCount += old.context.events.count
            }
        }
        print("PASS: \(count) result/profile cases, \(effectCount) ordered reads/effects; separate surfaces, repeated operations, fallback, rollback, deadlines and storage observers")
    }
}

