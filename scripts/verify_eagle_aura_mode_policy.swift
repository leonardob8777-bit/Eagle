import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
// Only unrelated UI localization / Scene type dependencies are stubbed.
enum LaraL10n { static func text(en: String, es: String) -> String { en } }
enum EagleSceneAuraMode { case glow, pulse, rainbow, tint }
enum EagleSceneAuraTarget { case island, dock }

@MainActor class Host {
    var channel = "stable"
    var reads: [String] = []
    var releaseChannel: EagleReleaseChannel {
        reads.append(channel)
        return EagleFeaturePolicy.channel(from: channel)
    }
    func test(_ raw: Int, _ target: AuraStudioTarget) -> Int { fatalError() }
    func eligible(_ mode: AuraStudioMode, _ target: AuraStudioTarget) -> Bool { fatalError() }
}

@main struct Main {
    @MainActor static func main() {
        let a = PublicHost(), b = OwnedHost()
        var count = 0
        var decisions = 0
        for channel in ["stable", "beta", "experimental", "", "unknown", "STABLE"] {
            a.channel = channel; b.channel = channel
            for target in AuraStudioTarget.allCases {
                for raw in [Int.min, Int.max] + Array(-100...1000) {
                    a.reads = []; b.reads = []
                    let old = a.test(raw, target), new = b.test(raw, target)
                    precondition(old == new && a.reads == b.reads)
                    let allowed = raw == 1 || (raw == 2 && ["beta", "experimental"].contains(channel)) ||
                        (raw == 4 && target == .island)
                    precondition(new == (allowed ? raw : 1))
                    let reads = raw == 2 || (raw == 4 && target == .island) ? [channel] : []
                    precondition(b.reads == reads)
                    count += 1
                }
                for mode in AuraStudioMode.allCases {
                    a.reads = []; b.reads = []
                    precondition(a.eligible(mode, target) == b.eligible(mode, target))
                    precondition(a.reads == b.reads)
                    decisions += 1
                }
            }
        }
        // Injected decisions prove lazy evaluation even if feature policy changes later.
        var injected = 0
        for mode in AuraStudioMode.allCases {
            for island in [false, true] {
                for pulse in [false, true] {
                    for rainbow in [false, true] {
                        var events: [String] = []
                        func target() -> Bool { events.append("target"); return island }
                        let result = EagleAuraStudioModePolicy.allows(mode, isIsland: target(),
                            pulseAllowed: { events.append("pulse"); return pulse },
                            rainbowAllowed: { events.append("rainbow"); return rainbow })
                        let expected = mode == .glow || (mode == .pulse && pulse) ||
                            (mode == .rainbow && island && rainbow)
                        precondition(result == expected)
                        precondition(events == (mode == .pulse ? ["pulse"] : mode == .rainbow ?
                            (island ? ["target", "rainbow"] : ["target"]) : []))
                        injected += 1
                    }
                }
            }
        }
        // The same instances observe channel changes; no caching of permissions.
        for channel in ["beta", "stable", "experimental", "corrupt", "beta"] {
            a.channel = channel; b.channel = channel
            let old = AuraStudioMode.allCases.filter { a.eligible($0, .island) }.map(\.rawValue)
            let new = AuraStudioMode.allCases.filter { b.eligible($0, .island) }.map(\.rawValue)
            precondition(old == new && new == (["beta", "experimental"].contains(channel) ? [1, 2, 4] : [1, 4]))
        }
        print("PASS: \(count) normalization cases, \(decisions) eligibility cases, \(injected) injected lazy-policy cases and 5 channel transitions")
    }
}
