import SwiftUI

/// Presentation-only motion shared by Gallery previews. It never changes the
/// media bytes, crop, native geometry or the value sent to SpringBoard.
struct EagleGalleryPresentationMotion: ViewModifier {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let paused = !active || reduceMotion || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: paused)) { context in
            let time = paused ? 0 : context.date.timeIntervalSinceReferenceDate
            let horizontal = paused ? 0 : sin(time * 0.54) * 1.6
            let vertical = paused ? 0 : cos(time * 0.43) * 1.1
            let scale = paused ? 1 : 1.008 + (sin(time * 0.36) + 1) * 0.004

            content
                .scaleEffect(scale)
                .offset(x: horizontal, y: vertical)
        }
    }
}

extension View {
    func eagleGalleryPresentationMotion(active: Bool) -> some View {
        modifier(EagleGalleryPresentationMotion(active: active))
    }
}

/// A very light reflected highlight used only on the single featured preview.
/// The timeline pauses in the background and when Reduce Motion is enabled.
struct EagleGalleryPreviewSheen: View {
    let active: Bool
    var opacity = 0.12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let paused = !active || reduceMotion || scenePhase != .active
        // Measured once, outside the clock; 60 fps: the highlight crosses the preview at about 120 pt a
        // second, which steps visibly at 20.
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
                let progress = paused
                    ? -0.25
                    : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 5.5) / 5.5

                LinearGradient(
                    colors: [.clear, .white.opacity(opacity), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width * 0.34, height: proxy.size.height * 1.35)
                .rotationEffect(.degrees(14))
                .offset(x: -width * 0.55 + width * 1.75 * progress,
                        y: -proxy.size.height * 0.16)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EagleGalleryTransitionModifier: ViewModifier {
    let x: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

enum EagleGallerySelectionTransition {
    static func moving(_ direction: Int) -> AnyTransition {
        let sign: CGFloat = direction < 0 ? -1 : 1
        return .asymmetric(
            insertion: .modifier(
                active: EagleGalleryTransitionModifier(x: 24 * sign, scale: 0.985, opacity: 0),
                identity: EagleGalleryTransitionModifier(x: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: EagleGalleryTransitionModifier(x: -18 * sign, scale: 0.992, opacity: 0),
                identity: EagleGalleryTransitionModifier(x: 0, scale: 1, opacity: 1)
            )
        )
    }
}
