import SwiftUI

/// Existing SwiftUI shape styles; draft mode/color reads remain supplied by the screen.
@MainActor
struct EagleAuraStudioPreviewStyles {
    let mode: (EagleAuraStudioTarget) -> EagleAuraStudioMode
    let color: (EagleAuraStudioTarget) -> Color
    let tintFillColor: () -> Color

    func previewRingStyle(for target: EagleAuraStudioTarget) -> AnyShapeStyle {
        let mode = mode(target)
        if mode == .rainbow {
            return AnyShapeStyle(LinearGradient(
                colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple, .pink],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
        return AnyShapeStyle(color(target))
    }

    func islandPreviewFillStyle(for mode: EagleAuraStudioMode) -> AnyShapeStyle {
        switch mode {
        case .tint:
            return AnyShapeStyle(tintFillColor())
        case .rainbow:
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color.pink,
                    Color.orange,
                    Color.cyan,
                    Color.purple,
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        case .glow, .pulse,
             .photo, .photoRainbow, .photoInferno, .photoSky, .photoVortex,
             .photoBubblegum, .photoTraffic:
            return AnyShapeStyle(Color.black)
        }
    }

    func islandRingStyle(for mode: EagleAuraStudioMode, angle: Double) -> AnyShapeStyle {
        switch mode {
        case .rainbow:
            return AnyShapeStyle(AngularGradient(
                colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                center: .center,
                angle: .degrees(angle)
            ))
        case .photo, .photoRainbow, .photoInferno, .photoSky, .photoVortex,
             .photoBubblegum, .photoTraffic:
            // The real preview is the bundled transparent PNG. This fallback
            // style is used only by shared shape helpers.
            return AnyShapeStyle(Color.purple)
        case .glow, .pulse, .tint:
            return AnyShapeStyle(color(.island))
        }
    }

    func islandFillStyle(for mode: EagleAuraStudioMode, angle: Double) -> AnyShapeStyle {
        guard mode == .rainbow else {
            return islandPreviewFillStyle(for: mode)
        }
        return AnyShapeStyle(AngularGradient(
            colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
            center: .center,
            angle: .degrees(angle)
        ))
    }
}
