import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
enum Flag {
    static let island: UInt32 = 1
    static let dock: UInt32 = 32
}

@MainActor enum LaraL10n {
    static var spanish = false
    static var events: [String] = []
    static func text(en: String, es: String) -> String {
        events.append("\(en)|\(es)")
        return spanish ? es : en
    }
}

@main struct OperationPlanChecks {
    @MainActor static func main() async {
        var operations = 0
        for mode in EagleAuraStudioMode.allCases {
            checkOperation(.apply(mode), .apply(mode))
            operations += 1
        }
        checkOperation(.remove, .remove)
        operations += 1

        let masks = Array(UInt32(0)...UInt32(255)) + [0x80000000, UInt32.max]
        var plans = 0
        var events = 0
        for mask in masks {
            let old = PublicPlan.steps(mask)
            let new = EagleAuraStudioOperation.steps(for: mask, islandFlag: Flag.island, dockFlag: Flag.dock)
            precondition(old.count == new.count)
            precondition(new.map(\.flag) == [Flag.island, Flag.dock].filter { mask & $0 != 0 })
            for spanish in [false, true] {
                LaraL10n.spanish = spanish
                LaraL10n.events = []
                let oldNames = old.map(\.localizedName)
                let oldEvents = LaraL10n.events
                LaraL10n.events = []
                let newNames = new.map { $0.localizedName(localizedText: { LaraL10n.text(en: $0, es: $1) }) }
                precondition(oldNames == newNames && oldEvents == LaraL10n.events)
                for (left, right) in zip(old, new) {
                    precondition(left.flag == right.flag)
                    precondition(left.englishName == right.englishName && left.spanishName == right.spanishName)
                }
                events += oldEvents.count
                plans += 1
            }
            let detached = await Task.detached {
                EagleAuraStudioOperation.steps(for: mask, islandFlag: Flag.island, dockFlag: Flag.dock)
            }.value
            precondition(detached.map(\.flag) == new.map(\.flag))
        }

        // Injected flags remain data, not an authorization mechanism. Check edge values
        // without implying that the screen permits these operation masks.
        var injectedPlans = 0
        for island: UInt32 in [0, 1, 32, 0x80000000, UInt32.max] {
            for dock: UInt32 in [0, 1, 32, 0x80000000, UInt32.max] {
                for mask in masks {
                    let result = EagleAuraStudioOperation.steps(for: mask, islandFlag: island, dockFlag: dock)
                    precondition(result.map(\.flag) == [island, dock].filter { mask & $0 != 0 })
                    injectedPlans += 1
                }
            }
        }
        let sample = EagleAuraStudioOperationStep(flag: 99, englishName: "Island 🌈", spanishName: "Isla 🌈")
        var calls: [String] = []
        let selected = sample.localizedName { en, es in
            calls.append(en); calls.append(es)
            return es
        }
        precondition(calls == ["Island 🌈", "Isla 🌈"] && selected == "Isla 🌈")
        let detachedOperation = await Task.detached { EagleAuraStudioOperation.apply(.photoTraffic) }.value
        precondition(detachedOperation.nativeMode == EagleAuraStudioMode.photoTraffic.rawValue)
        print("PASS: \(operations) operation mappings, \(plans) public/owned plans, \(events) localization events, \(masks.count) detached plans and \(injectedPlans) injected-mask cases; no native execution")
    }

    @MainActor static func checkOperation(_ old: PublicOperation, _ new: EagleAuraStudioOperation) {
        precondition(old.nativeMode == new.nativeMode)
        precondition(old.isRemoving == new.isRemoving)
        precondition(PublicPlan.requested(old) == new.requestedProfileMode)
    }
}
