import SwiftUI

/// Eagle's own "working" indicator: a thin ring in the text colour, with an arc turning around it
/// whose tail fades out. Black and white like the rest of Eagle. Appearance only.
struct EagleMarkSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 20
    var color: Color = .primary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0.0 : Self.phase(at: context.date, duration: 0.95)
            ZStack {
                // The full ring, faint.
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: ringWidth)
                // The turning arc, with a fading tail.
                Circle()
                    .trim(from: 0, to: 0.32)
                    .stroke(
                        AngularGradient(
                            stops: [
                                .init(color: color.opacity(0), location: 0),
                                .init(color: color, location: 0.32),
                                // Past the head the colour fades again, so the tail's rounded cap
                                // (just behind the start) stays invisible.
                                .init(color: color, location: 0.34),
                                .init(color: color.opacity(0), location: 1)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(phase * 360 - 90))
            }
            .padding(ringWidth / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var ringWidth: CGFloat { max(1.6, size * 0.085) }

    private static func phase(at date: Date, duration: TimeInterval) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / duration
        return cycles - floor(cycles)
    }
}

/// The eagle mark (the launch artwork's vector outline), fitted to the frame it is given.
struct EagleMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let art = CGSize(width: 120, height: 104)
        let scale = min(rect.width / art.width, rect.height / art.height)
        let offset = CGPoint(
            x: rect.midX - art.width * scale / 2,
            y: rect.midY - art.height * scale / 2
        )
        return EagleLaunchSplash.mark.applying(
            CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        )
    }
}
