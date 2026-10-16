import SwiftUI

extension View {
    /// While scrolling, a card easing out past the top or bottom edge fades and shrinks a little, and
    /// settles back as it comes into view, so the list has depth. iOS 17 and later; on earlier systems
    /// the card simply scrolls as before. Meant for compact cards, not tall sections.
    @ViewBuilder
    func eagleScrollDepth() -> some View {
        if #available(iOS 17.0, *) {
            scrollTransition(.interactive, axis: .vertical) { content, phase in
                let amount = min(1, abs(phase.value))
                return content
                    .opacity(1 - 0.4 * amount)
                    .scaleEffect(1 - 0.05 * amount, anchor: phase.value < 0 ? .bottom : .top)
            }
        } else {
            self
        }
    }
}
