import SwiftUI

struct EagleNewBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var text = LaraL10n.text(en: "NEW", es: "NUEVO")
    /// Only while on screen, like the header's sweep.
    @State private var onScreen = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
            .overlay {
                // A soft rainbow glint crosses the badge with the same pass as the header's brand
                // sweep, so one light seems to travel over the whole screen.
                if !reduceMotion && onScreen {
                    TimelineView(EagleBrandSweepSchedule()) { context in
                        GeometryReader { geometry in
                            if let progress = eagleBrandSweepProgress(at: context.date) {
                                glint(progress: progress, size: geometry.size)
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }
            }
            .fixedSize()
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }

    private func glint(progress: Double, size: CGSize) -> some View {
        let band = max(size.width * 0.7, 24)
        let travel = size.width + band * 2
        return LinearGradient(colors: EagleSpectrumStyle.colors, startPoint: .leading, endPoint: .trailing)
            .frame(width: band, height: size.height * 2.4)
            .mask(LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing))
            .rotationEffect(.degrees(-18))
            .opacity(colorScheme == .dark ? 0.55 : 0.75)
            .position(x: -band + travel * progress, y: size.height / 2)
    }
}
