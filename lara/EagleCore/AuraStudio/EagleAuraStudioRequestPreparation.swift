import Foundation

/// Immutable values captured before an Aura operation. This contains no access/session objects.
nonisolated struct EagleAuraStudioRequestParameters<Position: Sendable>: Sendable {
    let position: Position
    let positionSurface: Int32
    let red: Int32
    let green: Int32
    let blue: Int32
}

@MainActor
enum EagleAuraStudioRequestPreparation {
    static func prepare<Position: Sendable>(
        target: EagleAuraStudioTarget,
        isRemoving: Bool,
        readIslandRed: () -> Double,
        readIslandGreen: () -> Double,
        readIslandBlue: () -> Double,
        readDockRed: () -> Double,
        readDockGreen: () -> Double,
        readDockBlue: () -> Double,
        sanitize: (Double) -> Double,
        makeZeroPosition: () -> Position,
        savedPosition: (String) -> Position,
        channel255: (Double) -> Int
    ) -> EagleAuraStudioRequestParameters<Position> {
        let selectedRGB: (red: Double, green: Double, blue: Double) =
            target == .island
                ? (sanitize(readIslandRed()), sanitize(readIslandGreen()), sanitize(readIslandBlue()))
                : (sanitize(readDockRed()), sanitize(readDockGreen()), sanitize(readDockBlue()))
        let requestedPosition = isRemoving
            ? makeZeroPosition()
            : savedPosition(target == .island ? "island" : "dock")
        let positionSurface: Int32 = target == .island ? 1 : 0
        let redValue = Int32(channel255(selectedRGB.red))
        let greenValue = Int32(channel255(selectedRGB.green))
        let blueValue = Int32(channel255(selectedRGB.blue))
        return EagleAuraStudioRequestParameters(
            position: requestedPosition,
            positionSurface: positionSurface,
            red: redValue,
            green: greenValue,
            blue: blueValue
        )
    }
}
