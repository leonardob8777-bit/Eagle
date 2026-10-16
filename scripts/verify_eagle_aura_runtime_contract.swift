import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
typealias AuraStudioTarget = EagleAuraStudioTarget

nonisolated func verifyContract() -> Int {
    let flags: [UInt32] = [0, 1, 2, 16, 32, 33, 64, 127, 1 << 30, 1 << 31, .max]
    let results = [Int32.min, Int32.max] + (-64...96).map(Int32.init)
    var comparisons = 0
    for island in flags {
        for dock in flags {
            for requested in flags {
                precondition(PublicContract.target(for: requested, islandFlag: island, dockFlag: dock) ==
                    EagleAuraStudioNativeContract.target(for: requested, islandFlag: island, dockFlag: dock))
                comparisons += 1
            }
        }
    }
    for result in results {
        for target in AuraStudioTarget.allCases {
            for mode in AuraStudioMode.allCases {
                for removing in [false, true] {
                    precondition(PublicContract.isScopedUnavailable(result: result, target: target, mode: mode, isRemoval: removing) ==
                        EagleAuraStudioNativeContract.isScopedUnavailable(result: result, target: target, mode: mode, isRemoval: removing))
                    precondition(PublicContract.isScopedVerifiedRollback(result: result, target: target, isRemoval: removing) ==
                        EagleAuraStudioNativeContract.isScopedVerifiedRollback(result: result, target: target, isRemoval: removing))
                    comparisons += 2
                }
                precondition(PublicContract.verifiedFallbackMode(result: result, target: target, requestedMode: mode) ==
                    EagleAuraStudioNativeContract.verifiedFallbackMode(result: result, target: target, requestedMode: mode))
                comparisons += 1
            }
        }
        for requested in flags {
            for supported in flags {
                precondition(PublicContract.hasExactAppliedSurface(result: result, requestedFlag: requested, supportedFlags: supported) ==
                    EagleAuraStudioNativeContract.hasExactAppliedSurface(result: result, requestedFlag: requested, supportedFlags: supported))
                comparisons += 1
            }
        }
    }
    precondition(!EagleAuraStudioNativeContract.hasExactAppliedSurface(result: 33, requestedFlag: 1, supportedFlags: 33))
    precondition(!EagleAuraStudioNativeContract.isScopedUnavailable(result: -20, target: .dock, mode: .glow, isRemoval: true))
    precondition(EagleAuraStudioNativeContract.verifiedFallbackMode(result: -16, target: .dock, requestedMode: .tint) == nil)
#if DEBUG
    precondition(PublicContract.invariantsHold && EagleAuraStudioNativeContract.invariantsHold)
#endif
    return comparisons
}

@main struct Runner {
    @MainActor static func main() async {
        let direct = verifyContract()
        let detached = await Task.detached { verifyContract() }.value
        var gateChecks = 0
        for _ in 0..<128 {
            precondition(PublicGate.begin() && EagleAuraStudioApplyGate.begin())
            precondition(!PublicGate.begin() && !EagleAuraStudioApplyGate.begin())
            PublicGate.end(); EagleAuraStudioApplyGate.end()
            PublicGate.end(); EagleAuraStudioApplyGate.end()
            gateChecks += 4
        }
        for _ in 0..<16 {
            let admitted = await withTaskGroup(of: (Bool, Bool).self) { group in
                for _ in 0..<64 {
                    group.addTask {
                        await MainActor.run { (PublicGate.begin(), EagleAuraStudioApplyGate.begin()) }
                    }
                }
                var oldCount = 0, newCount = 0
                for await (old, new) in group {
                    precondition(old == new)
                    oldCount += old ? 1 : 0; newCount += new ? 1 : 0
                }
                return (oldCount, newCount)
            }
            precondition(admitted == (1, 1))
            PublicGate.end(); EagleAuraStudioApplyGate.end()
            gateChecks += 64
        }
        precondition(PublicGate.begin() && EagleAuraStudioApplyGate.begin())
        PublicGate.lock(); EagleAuraStudioApplyGate.lock()
        for _ in 0..<128 {
            precondition(!PublicGate.begin() && !EagleAuraStudioApplyGate.begin())
            PublicGate.end(); EagleAuraStudioApplyGate.end()
            precondition(!PublicGate.begin() && !EagleAuraStudioApplyGate.begin())
            PublicGate.lock(); EagleAuraStudioApplyGate.lock()
            gateChecks += 4
        }
        print("PASS: \(direct) contract comparisons + \(detached) detached; \(gateChecks) admission checks, 1,024 concurrent requests; lock survives end/repeated calls")
    }
}
