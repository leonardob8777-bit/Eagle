import SwiftUI
import UIKit

extension View {
    /// An SF Symbol that changes on a tap (a heart filling, a star) swaps with the system's replace
    /// animation, pops once and gives a light tap of feedback each time `trigger` changes.
    /// iOS 17 and later; earlier systems keep the plain swap.
    @ViewBuilder
    func eagleSymbolPop<Trigger: Equatable>(_ trigger: Trigger) -> some View {
        if #available(iOS 17.0, *) {
            self
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: trigger)
                .sensoryFeedback(.impact(weight: .light), trigger: trigger)
        } else {
            self
        }
    }
}

extension AnyTransition {
    /// Eagle's "working…" overlays ease in and out on their own (a fade with a slight scale), even
    /// where they are shown without an animation.
    static var eagleWorking: AnyTransition {
        AnyTransition.opacity.combined(with: .scale(scale: 0.97))
            .animation(.spring(response: 0.38, dampingFraction: 0.86))
    }
}

/// Switching between light and dark (or the language) crossfades the whole window from its old look
/// to the new one, instead of flipping at once. Appearance only.
enum EagleThemeCrossfade {
    static func run() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.4
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        window.layer.add(fade, forKey: "eagle.theme")
    }
}

extension AnyTransition {
    /// A selection checkmark pops in (and shrinks away) on its own spring.
    static var eagleCheck: AnyTransition {
        AnyTransition.scale(scale: 0.3).combined(with: .opacity)
            .animation(.spring(response: 0.3, dampingFraction: 0.6))
    }
}
