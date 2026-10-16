import UIKit

/// Reads the same screen measurements as the existing app; all numerical decisions live in Core.
@MainActor
enum EagleAuraStudioDisplayMetrics {
    static var current: EagleAuraStudioDisplayGeometry {
        let screen = UIScreen.main
        return EagleAuraStudioDisplayGeometry.resolve(
            readBounds: { screen.bounds },
            readNativeBounds: { screen.nativeBounds },
            readScale: { screen.scale },
            readNativeScale: { screen.nativeScale }
        )
    }
}
