import SwiftUI
import UIKit

/// Eagle-owned look and feel for Apply buttons. Visual only: each screen keeps its action,
/// its enablement and its own label.
///
/// - Touch-down: the button gives under the finger and brightens, with a soft haptic, and a ripple of
///   light opens from the exact point that was touched (`EagleTouchTracker`, which never interferes with
///   the tap itself).
/// - Disabled and idle: dimmed.
///
/// With `fill`, the style draws the button (white with black text in dark mode, black with white text
/// in light mode, from `EagleVisualTheme`). With `fill: nil`, the label already draws its own
/// background and the style only adds the reactions on top.
struct EagleApplyButtonStyle: ButtonStyle {
    var fill: Color? = EagleVisualTheme.actionFill
    var text: Color = EagleVisualTheme.actionText
    var busy = false
    /// Small inline variant (lists), instead of the full-width 50 pt button.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        EagleApplyButtonBody(configuration: configuration, fill: fill, text: text, busy: busy, compact: compact)
    }
}

private struct EagleApplyButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let fill: Color?
    let text: Color
    let busy: Bool
    let compact: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var touch: CGPoint?
    @State private var anchor = EagleTouchAnchor()
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: compact ? 10 : 15, style: .continuous)
    }

    /// Light that shows on the button's face: dark on the white (dark-mode) button, light otherwise.
    private var reaction: Color {
        let themedFill = fill == nil || fill == EagleVisualTheme.actionFill
        return themedFill && colorScheme == .dark ? Color.black.opacity(0.14) : Color.white.opacity(0.28)
    }

    var body: some View {
        styledLabel
            .eagleTouchAnchor(anchor)
            .overlay {
                ZStack {
                    if let touch {
                        GeometryReader { geometry in
                            let size = max(geometry.size.width, geometry.size.height) * 2.4
                            Circle()
                                .fill(reaction)
                                .frame(width: size, height: size)
                                .scaleEffect(rippleScale)
                                .opacity(rippleOpacity)
                                .position(touch)
                        }
                    }
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? (colorScheme == .dark ? -0.06 : 0.08) : 0)
            .opacity(fill != nil && !isEnabled && !busy ? 0.45 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
            // The touch point comes from `EagleTouchTracker`: a gesture attached here for it would stop
            // the button's own tap from firing.
            .onChange(of: configuration.isPressed) { pressed in
                guard pressed else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.75)
                touch = anchor.lastTouch ?? anchor.center
                guard !reduceMotion, touch != nil else { return }
                rippleScale = 0.04
                rippleOpacity = 1
                withAnimation(.easeOut(duration: 0.6)) {
                    rippleScale = 1
                    rippleOpacity = 0
                }
            }
    }

    @ViewBuilder
    private var styledLabel: some View {
        if let fill {
            configuration.label
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(text)
                .padding(.horizontal, compact ? 14 : 16)
                .frame(minHeight: compact ? 34 : 50)
                .background(fill, in: shape)
        } else {
            configuration.label
        }
    }
}
