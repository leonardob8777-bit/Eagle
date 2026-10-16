import Foundation

/// Operation values and ordered descriptors only; authorization and native execution stay in the caller.
nonisolated enum EagleAuraStudioOperation: Sendable {
    case apply(EagleAuraStudioMode)
    case remove

    var nativeMode: Int {
        switch self {
        case .apply(let mode): return mode.rawValue
        case .remove: return 0
        }
    }

    var isRemoving: Bool {
        if case .remove = self { return true }
        return false
    }

    var requestedProfileMode: EagleAuraStudioMode {
        switch self {
        case .apply(let profileMode):
            return profileMode
        case .remove:
            return .glow
        }
    }

    static func steps(
        for requestedFlags: UInt32,
        islandFlag: UInt32,
        dockFlag: UInt32
    ) -> [EagleAuraStudioOperationStep] {
        var steps: [EagleAuraStudioOperationStep] = []
        if requestedFlags & islandFlag != 0 {
            steps.append(EagleAuraStudioOperationStep(
                flag: islandFlag,
                englishName: "Dynamic Island",
                spanishName: "Dynamic Island"
            ))
        }
        if requestedFlags & dockFlag != 0 {
            steps.append(EagleAuraStudioOperationStep(
                flag: dockFlag,
                englishName: "Dock",
                spanishName: "Dock"
            ))
        }
        return steps
    }
}

nonisolated struct EagleAuraStudioOperationStep: Sendable {
    let flag: UInt32
    let englishName: String
    let spanishName: String

    func localizedName(localizedText: (String, String) -> String) -> String {
        localizedText(englishName, spanishName)
    }
}

