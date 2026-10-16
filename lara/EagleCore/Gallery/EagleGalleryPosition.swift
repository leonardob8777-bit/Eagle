import Foundation

/// Shared quarter-point position value. Persistence and controls live outside Core.
nonisolated struct EagleGalleryPosition: Equatable, Sendable {
    let x: Double
    let y: Double

    static func component(_ value: Double) -> Double {
        value.isFinite ? (min(12, max(-12, value)) * 4).rounded() / 4 : 0
    }

    init(x: Double, y: Double) {
        self.x = Self.component(x)
        self.y = Self.component(y)
    }
}
