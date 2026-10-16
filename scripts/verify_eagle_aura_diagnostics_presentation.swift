import Foundation

struct EagleDynamicIslandCompatibility {
    enum Availability: CaseIterable { case supported, unsupported, unknown }
    let isSimulator: Bool
    let availability: Availability
}
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
// Recording decoder, not a replacement for the production stored-values check.
// Source reversal proves that production still calls EagleStoredThemeValues.flags.
@MainActor enum EagleStoredThemeValues {
    static func flags(_ raw: Int) -> UInt32 {
        Trace.events.append("decode:\(raw)")
        return UInt32(exactly: raw) ?? 0
    }
}
@MainActor final class Context {
    var compatibility = [EagleDynamicIslandCompatibility(isSimulator: false, availability: .supported)]
    var active = [0]
    var supported: [UInt32] = [33]
    var compatibilityReads = 0
    var activeReads = 0
    var supportedReads = 0
    func reset() { compatibilityReads = 0; activeReads = 0; supportedReads = 0; Trace.events = [] }
}
@MainActor protocol Host {
    var context: Context { get }
    var islandHardwareUnavailableMessage: String { get }
    var activeModuleCount: Int { get }
    var verifiedSurfaceSummary: String { get }
    func rgb255String(_ red: Double, _ green: Double, _ blue: Double) -> String
}
extension Host {
    var islandCompatibility: EagleDynamicIslandCompatibility {
        Trace.events.append("compatibility")
        defer { context.compatibilityReads += 1 }
        return context.compatibility[min(context.compatibilityReads, context.compatibility.count - 1)]
    }
    var activeFlagsRaw: Int {
        Trace.events.append("active")
        defer { context.activeReads += 1 }
        return context.active[min(context.activeReads, context.active.count - 1)]
    }
    var deviceSupportedFlags: UInt32 {
        Trace.events.append("supported")
        defer { context.supportedReads += 1 }
        return context.supported[min(context.supportedReads, context.supported.count - 1)]
    }
    func channel255(_ value: Double) -> Int {
        Trace.events.append("channel:\(value.bitPattern)")
        return EagleAuraStudioColors.channel255(value)
    }
}

@main struct DiagnosticsPresentationChecks {
    @MainActor static func main() {
        let context = Context()
        let old = PublicHost(context: context)
        let new = OwnedHost(context: context)
        var cases = 0
        var events = 0
        func compare(_ a: () -> String, _ b: () -> String) -> (String, [String]) {
            context.reset()
            let first = a(), originalEvents = Trace.events
            let counts = [context.compatibilityReads, context.activeReads, context.supportedReads]
            context.reset()
            let second = b()
            precondition(first == second && originalEvents == Trace.events)
            precondition(counts == [context.compatibilityReads, context.activeReads, context.supportedReads])
            cases += 1; events += Trace.events.count
            return (second, originalEvents)
        }
        for spanish in [false, true] {
            Trace.spanish = spanish
            for simulator in [false, true] {
                for first in EagleDynamicIslandCompatibility.Availability.allCases {
                    for second in EagleDynamicIslandCompatibility.Availability.allCases {
                        context.compatibility = [
                            .init(isSimulator: simulator, availability: first),
                            .init(isSimulator: !simulator, availability: second)
                        ]
                        let (text, trace) = compare({ old.islandHardwareUnavailableMessage }, { new.islandHardwareUnavailableMessage })
                        precondition(trace == (simulator ? ["compatibility", "text"] : ["compatibility", "compatibility", "text"]))
                        if simulator { precondition(text.hasPrefix(spanish ? "El simulador" : "Simulator")) }
                        else {
                            switch second {
                            case .supported: precondition(text.hasPrefix(spanish ? "El hardware" : "Dynamic Island hardware"))
                            case .unsupported: precondition(text.hasPrefix(spanish ? "Este modelo de iPhone no tiene" : "This iPhone model does not have"))
                            case .unknown: precondition(text.hasPrefix(spanish ? "Este modelo de iPhone no ha sido" : "This iPhone model has not been"))
                            }
                        }
                    }
                }
            }
            for raw in [Int.min, -1] + Array(0...255) + [Int(UInt32.max), Int.max] {
                for supported: UInt32 in [0, 1, 2, 32, 33, 255, UInt32.max] {
                    context.active = [raw]; context.supported = [supported]
                    let expected = ((UInt32(exactly: raw) ?? 0) & supported).nonzeroBitCount
                    let (count, trace) = compare({ String(old.activeModuleCount) }, { String(new.activeModuleCount) })
                    precondition(count == String(expected) && trace == ["active", "decode:\(raw)", "supported"])
                    let (text, summaryTrace) = compare({ old.verifiedSurfaceSummary }, { new.verifiedSurfaceSummary })
                    let reads = expected == 1 ? 1 : 3
                    precondition(summaryTrace == Array(repeating: trace, count: reads).flatMap { $0 } + ["text"])
                    let expectedText = expected == 1
                        ? (spanish ? "1 aura verificada activa en esta sesión de SpringBoard" : "1 verified aura active in this SpringBoard session")
                        : (spanish ? "\(expected) auras verificadas activas en esta sesión de SpringBoard" : "\(expected) verified auras active in this SpringBoard session")
                    precondition(text == expectedText)
                }
            }
            // A live state may change between the condition and two localized
            // interpolations. Do not silently introduce a snapshot or cache.
            for active in [[0, 1, 3], [3, 1, 32], [1, 0, 3], [33, 0, 1]] {
                for supported: [UInt32] in [[33], [0, 1, 33], [33, 0, 1]] {
                    context.active = active; context.supported = supported
                    _ = compare({ old.verifiedSurfaceSummary }, { new.verifiedSurfaceSummary })
                }
            }
        }
        let channels: [Double] = [-.infinity, -1, -0.0, 0, 0.1, 0.5, 0.999, 1, 2, .infinity, .nan]
        for r in channels { for g in channels { for b in channels {
            let (text, trace) = compare({ old.rgb255String(r, g, b) }, { new.rgb255String(r, g, b) })
            precondition(trace == [r, g, b].map { "channel:\($0.bitPattern)" })
            precondition(text == [r, g, b].map { String(EagleAuraStudioColors.channel255($0)) }.joined(separator: ","))
        } } }
        context.reset()
        let controller = new.diagnosticsPresentation
        precondition(Trace.events.isEmpty)
        for index in 0..<128 {
            context.active = [index]; context.supported = [33]
            _ = compare({ old.verifiedSurfaceSummary }, { controller.verifiedSurfaceSummary })
        }
        print("PASS: \(cases) diagnostic presentation cases, \(events) exact ordered events; both languages, changing compatibility/counts, lazy simulator path, real channel formatting and reused controller")
    }
}
