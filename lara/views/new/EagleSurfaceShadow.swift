import SwiftUI

extension View {
    /// The cards' soft shadow (light appearance only; in dark it is clear), cast by a plain rounded
    /// shape behind the card instead of by the card's whole content. It looks the same, but it is not
    /// recomputed whenever something inside the card moves or animates, and nothing is drawn at all in
    /// dark appearance. For cards with an opaque background. Appearance only.
    func eagleSurfaceShadow(cornerRadius: CGFloat, radius: CGFloat = 10, y: CGFloat = 4) -> some View {
        modifier(EagleSurfaceShadowModifier(cornerRadius: cornerRadius, radius: radius, y: y))
    }
}

private struct EagleSurfaceShadowModifier: ViewModifier {
    let cornerRadius: CGFloat
    let radius: CGFloat
    let y: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            if colorScheme != .dark {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: EagleVisualTheme.surfaceShadow(for: colorScheme), radius: radius, y: y)
            }
        }
    }
}
