import Foundation

typealias AuraStudioMode = EagleAuraStudioMode

@MainActor enum Trace {
    static var events: [String] = []
    static var spanish = false
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Trace.events.append("text")
        return Trace.spanish ? es : en
    }
}
enum AuraStudioTarget: CaseIterable {
    case island, dock
    @MainActor var title: String {
        Trace.events.append("title.\(self)")
        return self == .island ? "Dynamic Island" : "Dock"
    }
}

struct Configuration {
    var local = false
    var remote = false
    var ready = true
    var busy = false
    var flags: UInt32 = 1
    var targets: [AuraStudioTarget] = [.island]
    var modes: [AuraStudioMode] = [.glow]
}

@MainActor final class Context {
    var config: Configuration
    var targetReads = 0
    var modeReads = 0
    init(_ config: Configuration) { self.config = config }
}

@MainActor struct Manager {
    let context: Context
    var rcSafetyLocked: Bool { Trace.events.append("remote"); return context.config.remote }
    var dsready: Bool { Trace.events.append("ready"); return context.config.ready }
}

@MainActor protocol CapabilityHost {
    var context: Context { get }
    var selectedCapabilityTitle: String { get }
    var selectedCapabilityDescription: String { get }
    var isApplyButtonDisabled: Bool { get }
}
extension CapabilityHost {
    var applySafetyBlocked: Bool { Trace.events.append("local"); return context.config.local }
    var mgr: Manager { Trace.events.append("manager"); return Manager(context: context) }
    var isApplying: Bool { Trace.events.append("busy"); return context.config.busy }
    var selectedFlags: UInt32 { Trace.events.append("flags"); return context.config.flags }
    var selectedTarget: AuraStudioTarget {
        Trace.events.append("target")
        defer { context.targetReads += 1 }
        return context.config.targets[min(context.targetReads, context.config.targets.count - 1)]
    }
    var selectedMode: AuraStudioMode {
        Trace.events.append("mode")
        defer { context.modeReads += 1 }
        return context.config.modes[min(context.modeReads, context.config.modes.count - 1)]
    }
    func evaluate(_ action: Int) -> String {
        switch action {
        case 0: return selectedCapabilityTitle
        case 1: return selectedCapabilityDescription
        default: return String(isApplyButtonDisabled)
        }
    }
}

@main struct CapabilityChecks {
    @MainActor static func main() {
        var scenarios = 0
        var actions = 0
        var events = 0
        var changingActions = 0

        func compare(_ old: PublicHost, _ new: OwnedHost, action: Int) -> (String, [String]) {
            Trace.events = []
            let first = old.evaluate(action)
            let firstEvents = Trace.events
            Trace.events = []
            let second = new.evaluate(action)
            let secondEvents = Trace.events
            precondition(first == second && firstEvents == secondEvents,
                         "action=\(action) old=\(firstEvents) new=\(secondEvents) textEqual=\(first == second)")
            precondition(old.context.targetReads == new.context.targetReads)
            precondition(old.context.modeReads == new.context.modeReads)
            events += secondEvents.count
            actions += 1
            return (second, secondEvents)
        }

        for local in [false, true] { for remote in [false, true] {
            for ready in [false, true] { for busy in [false, true] {
                for flags: UInt32 in [0, 1, 32, 33, UInt32.max] {
                    for target in AuraStudioTarget.allCases { for mode in AuraStudioMode.allCases {
                        for spanish in [false, true] {
                            Trace.spanish = spanish
                            let config = Configuration(local: local, remote: remote, ready: ready, busy: busy,
                                                       flags: flags, targets: [target], modes: [mode])
                            let old = PublicHost(context: Context(config))
                            let new = OwnedHost(context: Context(config))
                            let (title, titleEvents) = compare(old, new, action: 0)
                            let expectedTitle: String
                            if local || remote {
                                expectedTitle = spanish ? "Bloqueo de seguridad activo" : "Safety lock active"
                            } else if !ready {
                                expectedTitle = spanish ? "Se requiere acceso al sistema" : "System access required"
                            } else {
                                let name = target == .island ? "Dynamic Island" : "Dock"
                                expectedTitle = spanish ? "\(name) listo para verificación en vivo" : "\(name) ready for live verification"
                            }
                            precondition(title == expectedTitle)
                            precondition(titleEvents.filter { $0 == "target" }.count == ((!local && !remote && ready) ? 2 : 0))
                            precondition(!titleEvents.contains("mode") && !titleEvents.contains("busy"))
                            let (description, descriptionEvents) = compare(old, new, action: 1)
                            let modeExpected = !local && !remote && ready && target == .island
                            precondition(descriptionEvents.contains("mode") == modeExpected)
                            if local { precondition(!descriptionEvents.contains("manager")) }
                            if local || remote {
                                precondition(description.hasPrefix(spanish ? "Comparte el informe" : "Share the report"))
                            } else if !ready {
                                precondition(description.hasPrefix(spanish ? "Prepara el acceso" : "Prepare Eagle access"))
                            } else if target == .dock {
                                precondition(description.hasPrefix(spanish ? "Pasa por la pantalla" : "Use the Home Screen"))
                            } else if mode == .tint {
                                precondition(description.contains("True Tint"))
                            } else {
                                precondition(description.hasPrefix(spanish ? "El hardware fue reconocido" : "Hardware is recognized"))
                            }
                            let (disabled, buttonEvents) = compare(old, new, action: 2)
                            precondition(disabled == String(busy || !ready || flags == 0 || local || remote))
                            var expectedEvents = ["busy"]
                            if !busy {
                                expectedEvents += ["manager", "ready"]
                                if ready {
                                    expectedEvents += ["flags"]
                                    if flags != 0 {
                                        expectedEvents += ["local"]
                                        if !local { expectedEvents += ["manager", "remote"] }
                                    }
                                }
                            }
                            precondition(buttonEvents == expectedEvents)
                            scenarios += 1
                        }
                    } }
                }
            } }
        } }

        // One live controller is reused while the injected UI state changes.
        // This catches snapshots introduced at construction or cached between reads.
        for spanish in [false, true] {
            Trace.spanish = spanish
            let initial = Configuration(targets: [.island, .dock, .island, .dock], modes: [.tint, .glow])
            let old = PublicHost(context: Context(initial))
            let new = OwnedHost(context: Context(initial))
            Trace.events = []
            let controller = new.capabilityPresentation
            precondition(Trace.events.isEmpty)
            for step in 0..<64 {
                var config = initial
                config.local = step % 11 == 0
                config.remote = step % 7 == 0
                config.ready = step % 5 != 0
                config.busy = step % 3 == 0
                config.flags = step % 2 == 0 ? 0 : 32
                old.context.config = config; new.context.config = config
                old.context.targetReads = 0; new.context.targetReads = 0
                old.context.modeReads = 0; new.context.modeReads = 0
                for action in [0, 1, 2, 0, 2, 1] {
                    Trace.events = []
                    let first = old.evaluate(action)
                    let firstEvents = Trace.events
                    Trace.events = []
                    let second: String
                    switch action {
                    case 0: second = controller.selectedCapabilityTitle
                    case 1: second = controller.selectedCapabilityDescription
                    default: second = String(controller.isApplyButtonDisabled)
                    }
                    precondition(first == second && firstEvents == Trace.events)
                    precondition(old.context.targetReads == new.context.targetReads)
                    precondition(old.context.modeReads == new.context.modeReads)
                    events += firstEvents.count
                    changingActions += 1
                }
            }
        }
        print("PASS: \(scenarios) capability scenarios, \(actions) presentation reads, \(changingActions) sustained changing-state reads, \(events) ordered events; lazy safety/access reads, both languages and no native calls")
    }
}
