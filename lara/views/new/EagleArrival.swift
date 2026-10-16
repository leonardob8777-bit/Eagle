import SwiftUI
import Combine

/// The moment Eagle's main screens first appear: right away on a normal launch, or as the welcome
/// clears (its content then lands on the same backdrop the welcome leaves behind). Appearance only.
final class EagleArrival: ObservableObject {
    static let shared = EagleArrival()

    @Published private(set) var arrived = false

    /// Lets the content land. Only the first call counts; later launches of a screen just show it.
    func arrive() {
        guard !arrived else { return }
        arrived = true
    }
}

private struct EagleTabIsCurrentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the tab holding this view is the one on screen (set by the app shell).
    var eagleTabIsCurrent: Bool {
        get { self[EagleTabIsCurrentKey.self] }
        set { self[EagleTabIsCurrentKey.self] = newValue }
    }
}

extension View {
    /// The view lands softly (fades in while rising a few points) the first time Eagle appears.
    /// `order` staggers it after the views above it, so a screen settles from the top down. Choosing
    /// a tab again shows its content at once, already in place (re-landing it made the rows look as if
    /// they were still loading).
    func eagleArrival(_ order: Int) -> some View {
        modifier(EagleArrivalModifier(order: order))
    }
}

private struct EagleArrivalModifier: ViewModifier {
    let order: Int

    @ObservedObject private var arrival = EagleArrival.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(arrival.arrived ? 1 : 0)
            .offset(y: reduceMotion || arrival.arrived ? 0 : 18)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.3)
                    : .spring(response: 0.62, dampingFraction: 0.86).delay(0.065 * Double(order)),
                value: arrival.arrived
            )
    }
}

extension View {
    /// An SF Symbol gives one small bounce just after its screen lands on opening Eagle. Not on tab
    /// changes: there the icons must simply be there. iOS 17 and later; otherwise nothing changes.
    func eagleArrivalBounce(delay: Double = 0.42) -> some View {
        modifier(EagleArrivalBounceModifier(delay: delay))
    }
}

private struct EagleArrivalBounceModifier: ViewModifier {
    let delay: Double

    @ObservedObject private var arrival = EagleArrival.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.eagleTabIsCurrent) private var tabIsCurrent
    @State private var bounces = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .symbolEffect(.bounce, value: bounces)
                .onChange(of: arrival.arrived) { arrived in
                    if arrived && tabIsCurrent { bounce() }
                }
        } else {
            content
        }
    }

    private func bounce() {
        guard !reduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { bounces += 1 }
    }
}
