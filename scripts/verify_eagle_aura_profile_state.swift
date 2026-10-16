import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum AuraStudioTarget { case island, dock }

@MainActor final class Context {
    var ints: [String: Int] = [:]
    var doubles: [String: Double] = [:]
    var events: [String] = []
    var modes: [AuraStudioMode] = [.glow]
    var modeReads = 0
    func readInt(_ key: String) -> Int { events.append(key); return ints[key]! }
    func readDouble(_ key: String) -> Double { events.append(key); return doubles[key]! }
    func readMode(_ target: AuraStudioTarget) -> AuraStudioMode {
        events.append(target == .island ? "modeIsland" : "modeDock")
        defer { modeReads += 1 }
        return modes[min(modeReads, modes.count - 1)]
    }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    func flag(for target: AuraStudioTarget) -> UInt32 {
        context.events.append(target == .island ? "flagIsland" : "flagDock")
        return target == .island ? 1 : 32
    }
    func mode(for target: AuraStudioTarget) -> AuraStudioMode { context.readMode(target) }
}

@main struct Check {
    @MainActor static func main() {
        let a = Context(), b = Context()
        let old = PublicHost(context: a), owned = OwnedHost(context: b)
        let flags = [Int.min, -1, 0, 1, 2, 32, 33, 64, 255, Int(UInt32.max), Int(UInt32.max) + 1, Int.max]
        let rawModes = [Int.min, -1, 0, 1, 2, 3, 4, 8, 9, 10, 11, 12, 13, 14, 15, 32, 36, Int.max]
        var scenarios = 0, actions = 0, events = 0
        func prepare(_ flags: Int, _ raw: Int, _ mode: AuraStudioMode, _ variant: Int) {
            a.ints = ["activeFlagsRaw": flags, "activeIslandModeRaw": raw, "activeDockModeRaw": raw]
            a.doubles = [:]
            // Matching defaults, then each RGB mismatch independently; rounding edges and
            // finite out-of-range values preserve the original, unclamped comparison.
            let r = variant == 4 ? (10.5 / 255).nextDown : variant == 5 ? 10.5 / 255 : variant == 6 ? -0.25 : 0.5
            let g = variant == 7 ? 1.25 : 0.25
            let values = [r, g, 1.0]
            for prefix in ["island", "dock"] {
                for (i, color) in ["Red", "Green", "Blue"].enumerated() {
                    a.doubles[prefix + color] = values[i]
                    let active = prefix == "island" ? "activeIsland" : "activeDock"
                    a.ints[active + color] = Int((values[i] * 255).rounded()) + (variant == i + 1 ? 1 : 0)
                }
            }
            a.modes = [mode]; b.ints = a.ints; b.doubles = a.doubles; b.modes = a.modes
        }
        func compare(_ op: Int, _ target: AuraStudioTarget) -> Int {
            a.events = []; b.events = []; a.modeReads = 0; b.modeReads = 0
            let result = old.act(op, target), next = owned.act(op, target)
            precondition(result == next && a.events == b.events)
            precondition(a.ints == b.ints && a.doubles == b.doubles)
            precondition(a.modeReads == b.modeReads)
            actions += 1; events += b.events.count
            return next
        }
        for mask in flags { for raw in rawModes { for mode in AuraStudioMode.allCases {
            for variant in 0...7 { for target: AuraStudioTarget in [.island, .dock] {
                prepare(mask, raw, mode, variant)
                let bit: UInt32 = target == .island ? 1 : 32
                let active = EagleStoredThemeValues.flags(mask) & bit != 0
                precondition(compare(0, target) == (active ? 1 : 0))
                precondition(b.events.count == 2 && b.events.first == "activeFlagsRaw")
                precondition(compare(1, target) == (AuraStudioMode(rawValue: raw)?.rawValue ?? -1))
                precondition(b.events.count == 1)
                let result = compare(2, target)
                let matchingMode = raw == mode.rawValue
                let matchingRGB = !(1...3).contains(variant)
                precondition(result == (active && matchingMode && (mode.usesFixedPalette || matchingRGB) ? 1 : 0))
                let expectedReads = !active ? 2 : !matchingMode ? 4 : mode.usesFixedPalette ? 5 : 11
                precondition(b.events.count == expectedReads)
                let wrongPrefix = target == .island ? "dock" : "island"
                let wrongActive = target == .island ? "activeDock" : "activeIsland"
                precondition(!b.events.contains { $0.hasPrefix(wrongPrefix) || $0.hasPrefix(wrongActive) })
                scenarios += 1
            } }
        } } }
        for mask in 0..<256 {
            prepare(mask, 1, .glow, 0)
            for target: AuraStudioTarget in [.island, .dock] { _ = compare(2, target) }
        }
        // Preserve the second mode read, rather than silently caching the first result.
        for first in AuraStudioMode.allCases { for second in AuraStudioMode.allCases {
            for target: AuraStudioTarget in [.island, .dock] {
                prepare(33, first.rawValue, first, 1)
                a.modes = [first, second]; b.modes = a.modes
                precondition(compare(2, target) == (second.usesFixedPalette ? 1 : 0))
                precondition(b.modeReads == 2)
            }
        } }
        // Different values on the other surface must not affect the selected profile.
        prepare(33, 1, .glow, 0)
        a.ints["activeDockModeRaw"] = 32; b.ints = a.ints
        precondition(compare(2, .island) == 1 && compare(2, .dock) == 0)
        print("PASS: \(scenarios) profile scenarios, \(actions) actions, \(events) exact read events; all 256 flag combinations and 242 changing-mode cases; no writes")
    }
}
