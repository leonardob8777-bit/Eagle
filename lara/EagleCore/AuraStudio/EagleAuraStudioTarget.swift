import Foundation

/// Profile identity and stored-selection rules; storage and hardware availability remain with the caller.
nonisolated enum EagleAuraStudioTarget: Int, CaseIterable, Identifiable, Sendable {
    case island = 1
    case dock = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .island: return "Dynamic Island"
        case .dock: return "Dock"
        }
    }

    static func storedSelection(
        rawValue: Int,
        islandProfileAvailable: () -> Bool
    ) -> EagleAuraStudioTarget {
        let stored = EagleAuraStudioTarget(rawValue: rawValue) ?? .dock
        // A persisted Island selection from another device must never
        // hide or block Dock on hardware without a verified Island.
        return stored == .island && !islandProfileAvailable() ? .dock : stored
    }

    func flag(
        islandFlag: @autoclosure () -> UInt32,
        dockFlag: @autoclosure () -> UInt32
    ) -> UInt32 {
        self == .island ? islandFlag() : dockFlag()
    }
}
