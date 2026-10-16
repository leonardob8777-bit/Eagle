import SwiftUI
import UIKit

/// Existing color-picker binding; UIKit conversion stays outside Core.
@MainActor
struct EagleAuraStudioColorBinding {
    let readColor: () -> Color
    let readMode: () -> EagleAuraStudioMode
    let writeMode: (EagleAuraStudioMode) -> Void
    let writeRGB: (Double, Double, Double) -> Void

    var binding: Binding<Color> {
        Binding(
            get: { readColor() },
            set: { color in
                if readMode().usesFixedPalette {
                    writeMode(.glow)
                }
                let resolved = UIColor(color)
                var nextRed: CGFloat = 0
                var nextGreen: CGFloat = 0
                var nextBlue: CGFloat = 0
                var alpha: CGFloat = 0
                guard resolved.getRed(
                    &nextRed,
                    green: &nextGreen,
                    blue: &nextBlue,
                    alpha: &alpha
                ) else { return }
                writeRGB(
                    Double(nextRed),
                    Double(nextGreen),
                    Double(nextBlue)
                )
            }
        )
    }
}
