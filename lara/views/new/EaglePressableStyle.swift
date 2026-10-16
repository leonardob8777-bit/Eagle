import SwiftUI

/// Press feedback for the cards and rows that open a screen: cards give slightly under the finger,
/// rows light up like a system list row. Visual only: the link or button works exactly as before, and
/// no gesture is added (a gesture would compete with the tap and with scrolling).
struct EaglePressableStyle: ButtonStyle {
    enum Kind {
        /// A standalone card: it shrinks a little and dims a touch.
        case card
        /// A row inside a grouped card: its background lights up.
        case row
        /// A small round control such as a colour swatch: it squeezes under the finger.
        case swatch
    }

    var kind: Kind = .card

    func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .card:
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.68), value: configuration.isPressed)
        case .swatch:
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.86 : 1)
                .animation(.spring(response: 0.26, dampingFraction: 0.55), value: configuration.isPressed)
        case .row:
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0))
                .contentShape(Rectangle())
                .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.3), value: configuration.isPressed)
        }
    }
}

/// Eagle's secondary button (Preview, Choose wallpaper, Undo) where it sits on the backdrop: a solid
/// capsule like the rest of the options, instead of the system's washed-out translucent grey, with the
/// same give under the finger as the cards. Appearance only: the button and its action are unchanged.
struct EagleSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EagleSecondaryButtonBody(configuration: configuration)
    }
}

private struct EagleSecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
