import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum AuraStudioTarget { case island, dock }
enum Availability { case unknown, unavailable }
struct Compatibility { let availability: Availability }

@MainActor enum Trace {
    static var events: [String] = []
    static var spanish = false
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Trace.events.append("text:\(en)|\(es)")
        return Trace.spanish ? es : en
    }
}
extension EagleAuraStudioMode {
    @MainActor var title: String {
        Trace.events.append("title:\(rawValue)")
        return title(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
}
@MainActor final class Context {
    var available = true
    var unknown = false
    var activity = [true]
    var rawModes = [1]
    var applied: AuraStudioMode? = .glow
    var matches = true
    var activityReads = 0
    var rawReads = 0
    func reset() { activityReads = 0; rawReads = 0; Trace.events = [] }
    func raw(_ target: AuraStudioTarget) -> Int {
        Trace.events.append(target == .island ? "rawIsland" : "rawDock")
        defer { rawReads += 1 }
        return rawModes[min(rawReads, rawModes.count - 1)]
    }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    var islandProfileAvailable: Bool { Trace.events.append("available"); return context.available }
    var islandCompatibility: Compatibility {
        Trace.events.append("compatibility")
        return Compatibility(availability: context.unknown ? .unknown : .unavailable)
    }
    var activeIslandModeRaw: Int { context.raw(.island) }
    var activeDockModeRaw: Int { context.raw(.dock) }
    func isTargetActive(_ target: AuraStudioTarget) -> Bool {
        Trace.events.append(target == .island ? "activeIsland" : "activeDock")
        defer { context.activityReads += 1 }
        return context.activity[min(context.activityReads, context.activity.count - 1)]
    }
    func activeMode(for target: AuraStudioTarget) -> AuraStudioMode? {
        Trace.events.append(target == .island ? "modeIsland" : "modeDock"); return context.applied
    }
    func draftMatchesActive(_ target: AuraStudioTarget) -> Bool {
        Trace.events.append(target == .island ? "matchesIsland" : "matchesDock"); return context.matches
    }
}

@main struct Check {
    @MainActor static func main() {
        let context = Context()
        let old = PublicHost(context: context), owned = OwnedHost(context: context)
        var scenarios = 0, events = 0, branches = Array(repeating: 0, count: 7)
        let raws = [Int.min, -1] + Array(0...37) + [Int.max]
        func compare(_ target: AuraStudioTarget) -> (String, [String]) {
            context.reset(); let first = old.status(target), originalEvents = Trace.events
            let activityReads = context.activityReads, rawReads = context.rawReads
            context.reset(); let second = owned.status(target), ownedEvents = Trace.events
            precondition(first == second && originalEvents == ownedEvents)
            precondition(activityReads == context.activityReads && rawReads == context.rawReads)
            precondition(ownedEvents.last?.hasPrefix("text:") == true)
            events += ownedEvents.count; scenarios += 1
            return (second, ownedEvents)
        }
        for target: AuraStudioTarget in [.island, .dock] {
            for available in [false, true] { for unknown in [false, true] {
                for active in [false, true] { for raw in raws { for matches in [false, true] {
                    for spanish in [false, true] {
                        context.available = available; context.unknown = unknown
                        context.activity = [active]; context.rawModes = [raw]
                        context.applied = AuraStudioMode(rawValue: raw); context.matches = matches
                        Trace.spanish = spanish
                        let (actual, trace) = compare(target)
                        let expected: String
                        let branch: Int
                        if target == .island && !available {
                            branch = unknown ? 0 : 1
                            expected = unknown
                                ? (spanish ? "Modelo desconocido · Island desactivada de forma segura" : "Unknown model · Island disabled safely")
                                : (spanish ? "Este iPhone no tiene Dynamic Island" : "This iPhone has no Dynamic Island")
                            precondition(trace.count == 3 && trace[0] == "available" && trace[1] == "compatibility")
                        } else if active && target == .dock && ((15...31).contains(raw) || raw == 35) {
                            branch = 2
                            expected = spanish ? "Arte de Galería Dock activo" : "Dock Gallery artwork active"
                            precondition(!trace.contains("modeDock") && !trace.contains("matchesDock"))
                        } else if active && target == .island && ((32...34).contains(raw) || raw == 36) {
                            branch = 3
                            expected = spanish ? "Arte de Galería Island activo" : "Island Gallery artwork active"
                            precondition(!trace.contains("modeIsland") && !trace.contains("matchesIsland"))
                        } else if let applied = context.applied, active {
                            let title = applied.title(localizedText: { spanish ? $1 : $0 })
                            branch = matches ? 5 : 6
                            expected = matches ? (spanish ? "Aplicado · \(title)" : "Applied · \(title)")
                                : (spanish ? "Activo: \(title) · cambios seleccionados sin aplicar" : "Active: \(title) · selected changes not applied")
                            precondition(trace.filter { $0.hasPrefix("title:") }.count == 2)
                        } else {
                            branch = 4
                            expected = spanish ? "No activo" : "Not active"
                            precondition(!trace.contains { $0.hasPrefix("matches") || $0.hasPrefix("title:") })
                        }
                        precondition(actual == expected)
                        if target == .dock { precondition(!trace.contains("available") && !trace.contains("compatibility")) }
                        branches[branch] += 1
                    }
                } } }
            } }
        }
        precondition(branches.allSatisfy { $0 > 0 })
        let stableScenarios = scenarios
        // Repeat-read behavior is observable: OR checks read raw state twice when
        // the range misses, and the final guard rechecks activity after the mode.
        context.available = true
        for target: AuraStudioTarget in [.island, .dock] {
            for activity in [[true, false], [false, true], [true, true]] {
                for raw in [[0, 35], [0, 36], [15, 0], [32, 0], [0, 0]] {
                    for applied in [AuraStudioMode?.none, .some(.glow), .some(.rainbow)] {
                        context.activity = activity; context.rawModes = raw; context.applied = applied
                        for matches in [false, true] {
                            context.matches = matches
                            _ = compare(target)
                        }
                    }
                }
            }
        }
        print("PASS: \(stableScenarios) status/language scenarios, \(scenarios - stableScenarios) changing-state cases, \(events) exact events; all seven status branches and no writes")
    }
}
