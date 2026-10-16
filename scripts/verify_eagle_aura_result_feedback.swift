import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum Flag {
    static let island: UInt32 = 1
    static let screen: UInt32 = 2
    static let battery: UInt32 = 4
    static let dock: UInt32 = 32
    static let lock: UInt32 = 64
}
@MainActor enum Runtime {
    static var spanish = false
    static var events: [String] = []
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        Runtime.events.append("text:\(en)|\(es)")
        return Runtime.spanish ? es : en
    }
}
extension EagleAuraStudioMode {
    @MainActor var title: String {
        Runtime.events.append("title:\(rawValue)")
        return "style-\(rawValue)"
    }
}

@main struct Check {
    @MainActor static func main() {
        let old = PublicHost(), owned = OwnedHost()
        var comparisons = 0, events = 0
        func compare<T: Equatable>(_ a: () -> T, _ b: () -> T) {
            Runtime.events = []
            let expected = a(), expectedEvents = Runtime.events
            Runtime.events = []
            let actual = b()
            precondition(actual == expected, "Result mismatch at \(comparisons)")
            precondition(Runtime.events == expectedEvents, "Callback order mismatch at \(comparisons)")
            comparisons += 1; events += expectedEvents.count
        }
        let known: [UInt32] = [1, 2, 4, 32, 64]
        var masks = (0..<32).map { bits in
            known.enumerated().reduce(UInt32(0)) { $0 | (bits & (1 << $1.offset) == 0 ? 0 : $1.element) }
        }
        masks += [8, 16, 24, 128, 0x80000000, UInt32.max]
        let modes: [AuraStudioMode?] = [nil] + AuraStudioMode.allCases.map { Optional($0) }
        for spanish in [false, true] {
            Runtime.spanish = spanish
            for flags in Array(UInt32(0)...UInt32(255)) + [0x80000000, UInt32.max] {
                compare({ old.names(for: flags) }, { owned.names(for: flags) })
                let expected = known.enumerated().compactMap { index, mask -> String? in
                    guard flags & mask != 0 else { return nil }
                    return (spanish ? ["Isla", "Pantalla", "Halo de batería", "Dock", "Bloqueo"]
                                    : ["Island", "Screen", "Battery Halo", "Dock", "Lock"])[index]
                }
                precondition(owned.names(for: flags) == expected)
            }
            for code in Array(Int32(-128)...Int32(128)) + [Int32.min, Int32.max] {
                compare({ old.message(for: code) }, { owned.message(for: code) })
            }
            for applied in masks { for requested in masks {
                for restoring in [false, true] { for degraded in [false, true] {
                    for mode in modes {
                        compare({ old.successMessage(appliedFlags: applied, requestedFlags: requested,
                                                     restoring: restoring, motionDegraded: degraded, appliedMode: mode) },
                                { owned.successMessage(appliedFlags: applied, requestedFlags: requested,
                                                       restoring: restoring, motionDegraded: degraded, appliedMode: mode) })
                        // The public method tests named missing surfaces, not unknown flag bits.
                        let needsTitle = !restoring && !degraded && ((requested & ~applied) & 103) == 0 && applied != 0 && mode != nil
                        precondition(Runtime.events.filter { $0.hasPrefix("title:") }.count == (needsTitle ? 1 : 0))
                    }
                }}
            }}
        }
        print("PASS: Aura feedback \(comparisons) public/owned results; \(events) ordered localization/title events; both languages, flags, partial/restored/degraded and error paths")
    }
}
