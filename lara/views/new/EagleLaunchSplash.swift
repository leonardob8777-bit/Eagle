import SwiftUI
import UIKit

/// Eagle's opening, picked up from the launch screen (only its background, black or white following
/// the iPhone's own appearance, so a fresh install goes straight from it to the welcome film without
/// any logo): the logo appears softly (white on black, or black on white) and stays still for a beat,
/// then the whole opening (logo and background) melts away in a soft blur onto the app, with no cut
/// or seam anywhere. The logo is drawn as vector paths (traced from the launch artwork) so it stays
/// sharp, and the motion is computed from one clock on every display frame. Appearance only.
struct EagleLaunchSplash: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The iPhone's own appearance: the launch screen follows it, not Eagle's Light/Dark setting.
    @State private var systemDark: Bool = {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen ?? UIScreen.main
        return screen.traitCollection.userInterfaceStyle != .light
    }()
    @State private var veil: Double = 1

    // Timeline (seconds from the first frame).
    /// The logo appearing on the launch background.
    fileprivate static let appear = 0.3
    /// Still, once it has appeared.
    fileprivate static let hold = 0.42
    /// The opening melting away onto the app.
    fileprivate static let dissolveLength = 0.55
    fileprivate static var dissolveStart: Double { appear + hold }
    fileprivate static var total: Double { dissolveStart + dissolveLength }
    /// The blur reached as the opening melts away.
    private static let maxBlur: CGFloat = 20

    var body: some View {
        EagleLaunchSplashFrame(progress: progress, systemDark: systemDark)
            // Larger than the screen, so the blur at the end never shows the app along the edges.
            .padding(-60)
            .opacity(veil)
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onAppear(perform: play)
    }

    @State private var progress: Double = 0

    private func play() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.35).delay(0.25)) { veil = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { onFinished() }
            return
        }
        // One linear clock from 0 to 1; the frame turns it into size and opacity (below), so every
        // display frame is drawn on schedule. While Eagle is still loading, the first frames can come
        // late and the clock with them, so the opening ends when the animation itself ends (iOS 17),
        // never cut short by a timer that started counting earlier.
        if #available(iOS 17.0, *) {
            withAnimation(.linear(duration: Self.total)) {
                progress = 1
            } completion: {
                onFinished()
            }
        } else {
            withAnimation(.linear(duration: Self.total)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.total) { onFinished() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dissolveStart) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
    }

    /// The logo's size: it settles from a touch smaller as it appears, then stays still.
    fileprivate static func scale(at t: Double) -> CGFloat {
        guard t < appear else { return 1 }
        let u = t / appear
        return 0.96 + 0.04 * CGFloat(1 - pow(1 - u, 3))
    }

    /// How visible the logo is as it appears (ease out).
    fileprivate static func shown(at t: Double) -> Double {
        let u = min(1, t / appear)
        return 1 - pow(1 - u, 3)
    }

    /// How far the opening has melted away, 0…1 (smootherstep: gentle at both ends).
    fileprivate static func dissolve(at t: Double) -> Double {
        let c = min(1, max(0, (t - dissolveStart) / dissolveLength))
        return c * c * c * (c * (c * 6 - 15) + 10)
    }

    fileprivate static func blur(at t: Double) -> CGFloat {
        maxBlur * CGFloat(pow(dissolve(at: t), 0.7))
    }

    /// The logo comes straight at the camera from the middle of the screen.
    fileprivate static let anchor = UnitPoint(x: 0.5, y: 0.5)

    /// The launch artwork's logo, traced from `EagleLaunchMark` (@3x pixels, drawn at 1/3 scale).
    static let mark: Path = {
        var path = Path()
        for outline in [upperOutline, leftWing, rightWing] {
            path.addLines(outline)
            path.closeSubpath()
        }
        return path
    }()

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 3, y: y / 3) }

    /// Upper wings and body (one outline).
    private static let upperOutline: [CGPoint] = [
        p(11.5, 36.8), p(10.7, 37.5), p(11.1, 40.5), p(15.2, 59.5),
        p(19.2, 74.5), p(25.2, 92.5), p(30.3, 104.5), p(35.3, 114.5),
        p(43.2, 127.5), p(48.4, 134.5), p(57.5, 144.1), p(64.5, 149.7),
        p(135.5, 188.2), p(141.5, 192.7), p(145.5, 196.9), p(148.0, 200.5),
        p(150.9, 206.5), p(158.8, 231.5), p(180.5, 306.8), p(206.1, 218.5),
        p(210.4, 205.5), p(214.3, 198.5), p(219.7, 192.5), p(225.5, 188.2),
        p(294.5, 150.9), p(302.5, 144.9), p(311.7, 135.5), p(317.8, 127.5),
        p(322.8, 119.5), p(329.7, 106.5), p(335.7, 92.5), p(343.8, 67.5),
        p(347.6, 51.5), p(350.2, 37.5), p(349.5, 36.8), p(347.5, 38.4),
        p(220.5, 142.3), p(214.5, 147.7), p(211.0, 152.5), p(208.3, 159.5),
        p(204.9, 184.5), p(204.0, 189.5), p(203.5, 190.2), p(192.7, 163.5),
        p(191.5, 161.8), p(190.5, 161.7), p(169.5, 161.8), p(168.3, 163.5),
        p(157.5, 190.2), p(156.9, 189.5), p(156.4, 186.5), p(152.7, 159.5),
        p(149.9, 152.5), p(145.5, 146.8)
    ]
    private static let leftWing: [CGPoint] = [
        p(58.5, 160.1), p(58.0, 160.5), p(58.2, 161.5), p(61.3, 168.5),
        p(71.3, 187.5), p(81.1, 201.5), p(86.5, 207.5), p(91.9, 212.5),
        p(97.5, 216.7), p(105.5, 220.9), p(148.5, 238.8), p(153.5, 240.8),
        p(153.9, 240.5), p(139.7, 207.5), p(136.8, 202.5), p(130.5, 196.0),
        p(122.5, 191.1)
    ]
    private static let rightWing: [CGPoint] = [
        p(302.5, 160.1), p(240.5, 190.1), p(234.5, 193.2), p(229.8, 196.5),
        p(224.2, 202.5), p(220.2, 209.5), p(209.3, 234.5), p(207.2, 240.5),
        p(212.5, 238.7), p(257.5, 219.7), p(264.5, 215.7), p(269.5, 211.9),
        p(279.7, 201.5), p(288.9, 188.5), p(298.7, 170.5), p(302.7, 161.5),
        p(302.9, 160.5)
    ]
}

/// One frame of the opening, drawn from the clock's progress (animated by SwiftUI on every display
/// frame): the background giving way to the app, and the logo.
private struct EagleLaunchSplashFrame: View, Animatable {
    var progress: Double
    let systemDark: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let t = progress * EagleLaunchSplash.total
        let scale = EagleLaunchSplash.scale(at: t)
        let shown = EagleLaunchSplash.shown(at: t)
        let dissolve = EagleLaunchSplash.dissolve(at: t)
        let blur = EagleLaunchSplash.blur(at: t)
        let background: Color = systemDark ? .black : .white
        let logo: Color = systemDark ? .white : .black
        return Canvas { context, size in
            // The launch screen's background, centred artwork at its natural size (120 × 104 pt).
            let art = CGSize(width: 120, height: 104)
            let origin = CGPoint(x: (size.width - art.width) / 2, y: (size.height - art.height) / 2)
            let unit = EagleLaunchSplash.anchor
            let anchor = CGPoint(x: origin.x + unit.x * art.width, y: origin.y + unit.y * art.height)
            let place = CGAffineTransform(translationX: origin.x, y: origin.y)
                .concatenating(CGAffineTransform(translationX: -anchor.x, y: -anchor.y))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            context.fill(EagleLaunchSplash.mark.applying(place), with: .color(logo.opacity(shown)))
        }
        .blur(radius: blur, opaque: false)
        .opacity(1 - dissolve)
    }
}
