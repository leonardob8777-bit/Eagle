import SwiftUI
import UIKit

enum EagleVisualTheme {
    static let accent = Color(red: 0.34, green: 0.29, blue: 0.88)
    static let actionFill = Color.primary
    static let actionText = Color(uiColor: .systemBackground)

    static let accentUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.58, green: 0.50, blue: 1.0, alpha: 1)
            : UIColor(red: 0.29, green: 0.24, blue: 0.78, alpha: 1)
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.74)
            : Color.black.opacity(0.68)
    }

    static func surfaceBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.11)
    }

    static func surfaceShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.clear
            : Color.black.opacity(0.06)
    }
}

/// Eagle's switches: the system switch with an "on" track the white knob always stands out on —
/// light grey in dark appearance (the app tint is white there, which hid the knob) and black in light.
/// Applied once at the root, so every switch in the app gets it. Appearance only.
struct EagleSwitchToggleStyle: ToggleStyle {
    static let onTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.56, alpha: 1) : .label
    })

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(Self.onTint)
    }
}

extension View {
    /// The label of a prominent action button (black or white fill): the contrasting colour while the
    /// button can be used, grey while it is disabled, so it never turns white on light grey.
    /// Appearance only.
    func eagleProminentLabel() -> some View {
        modifier(EagleProminentLabel())
    }
}

private struct EagleProminentLabel: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.foregroundStyle(
            isEnabled ? AnyShapeStyle(EagleVisualTheme.actionText) : AnyShapeStyle(.secondary)
        )
    }
}
