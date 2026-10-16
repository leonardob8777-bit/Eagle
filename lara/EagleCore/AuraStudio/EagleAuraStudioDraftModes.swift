import Foundation

/// Coordinates draft modes only. Existing storage, target resolution and policy stay injected.
@MainActor
struct EagleAuraStudioDraftModes<Target: Equatable> {
    let islandTarget: Target
    let dockTarget: Target
    let readTarget: () -> Target
    let readIsland: () -> Int
    let writeIsland: (Int) -> Void
    let readDock: () -> Int
    let writeDock: (Int) -> Void
    let normalize: (Int, Target) -> EagleAuraStudioMode
    let allows: (EagleAuraStudioMode, Target) -> Bool

    func normalizeDraftModesForPolicy() {
        let island = normalize(readIsland(), islandTarget)
        let dock = normalize(readDock(), dockTarget)
        if readIsland() != island.rawValue { writeIsland(island.rawValue) }
        if readDock() != dock.rawValue { writeDock(dock.rawValue) }
    }

    var selectedMode: EagleAuraStudioMode {
        get {
            let rawValue = readTarget() == islandTarget
                ? readIsland()
                : readDock()
            return normalize(rawValue, readTarget())
        }
        nonmutating set {
            guard allows(newValue, readTarget()) else { return }
            if readTarget() == islandTarget {
                writeIsland(newValue.rawValue)
            } else {
                writeDock(newValue.rawValue)
            }
        }
    }

    var availableModes: [EagleAuraStudioMode] {
        EagleAuraStudioMode.allCases.filter { allows($0, readTarget()) }
    }

    func mode(for target: Target) -> EagleAuraStudioMode {
        let rawValue = target == islandTarget ? readIsland() : readDock()
        return normalize(rawValue, target)
    }
}
