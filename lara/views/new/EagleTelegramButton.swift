import SwiftUI

/// Eagle's Telegram button: white, scattered with blue Telegram marks (the modern logo) floating
/// gently in place, the word "Telegram" large over them, and soft waves leaving its
/// edge now and then to invite a tap. The action is the screen's own. Appearance only.
struct EagleTelegramButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    static let blue = Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255)
    static let lightBlue = Color(red: 42 / 255, green: 171 / 255, blue: 238 / 255)
    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        Button(action: action) {
            ZStack {
                Self.shape.fill(.white)
                EagleTelegramScatter(moving: !reduceMotion)
                    .clipShape(Self.shape)
                Text("Telegram")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.black)
                    // A soft white edge so the word reads over the marks behind it.
                    .shadow(color: .white, radius: 1.5)
                    .shadow(color: .white.opacity(0.8), radius: 4)
            }
            // Narrower than Get started, centred under it.
            .frame(width: 236, height: 54)
            .contentShape(Self.shape)
        }
        .buttonStyle(EagleApplyButtonStyle(fill: nil))
        .background {
            if !reduceMotion && isEnabled {
                EagleTelegramWaves()
            }
        }
        .accessibilityLabel("Telegram")
    }
}

/// The modern Telegram logo: a blue gradient disc with Telegram's own white paper plane.
struct EagleTelegramMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [EagleTelegramButton.lightBlue, EagleTelegramButton.blue],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            EagleTelegramPlane()
                .fill(.white)
            EagleTelegramPlane()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.02, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Telegram's paper plane, on the logo's 240-unit grid.
private struct EagleTelegramPlane: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (54, 119), (175, 72), (156, 169), (119, 141), (100, 159), (102, 133), (157, 82), (89, 125)
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 / 240 * rect.width, y: rect.minY + point.1 / 240 * rect.height)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Telegram marks scattered at random sizes and angles (always the same layout), each floating gently
/// in place (the word sits over them).
private struct EagleTelegramScatter: View {
    let moving: Bool

    private struct Mark {
        let x: CGFloat, y: CGFloat, size: CGFloat, angle: Double, phase: Double
    }

    /// A fixed pseudo-random layout, in fractions of the button.
    private static let marks: [Mark] = {
        var seed: UInt64 = 0xEA61E
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        // One mark per cell of a loose grid, placed at random inside it: the button is covered evenly
        // without the marks ever lining up.
        let columns = 9, rows = 3
        return (0..<(columns * rows)).map { cell in
            let column = cell % columns, row = cell / columns
            let x = (Double(column) + 0.15 + next() * 0.7) / Double(columns)
            let y = (Double(row) + 0.15 + next() * 0.7) / Double(rows)
            return Mark(x: CGFloat(x), y: CGFloat(y), size: 10 + CGFloat(next()) * 8,
                        angle: (next() - 0.5) * 60, phase: next() * .pi * 2)
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moving)) { context in
            let time = moving ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas { canvas, size in
                guard let mark = canvas.resolveSymbol(id: 0) else { return }
                for item in Self.marks {
                    let float = CGFloat(sin(time * 0.9 + item.phase)) * 2.5
                    let center = CGPoint(x: item.x * size.width, y: item.y * size.height + float)
                    var placed = canvas
                    placed.translateBy(x: center.x, y: center.y)
                    placed.rotate(by: .degrees(item.angle + sin(time * 0.6 + item.phase) * 6))
                    placed.scaleBy(x: item.size / 22, y: item.size / 22)
                    placed.draw(mark, at: .zero)
                }
            } symbols: {
                EagleTelegramMark(size: 22).tag(0)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Two soft outlines leaving the button's edge every couple of seconds, fading as they grow.
private struct EagleTelegramWaves: View {
    private static let period = 2.2
    private static let reach: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let raw = (time / Self.period + Double(index) * 0.22).truncatingRemainder(dividingBy: 1)
                    // Each wave travels during the first part of the period, then rests.
                    let p = min(1, raw / 0.62)
                    let eased = 1 - pow(1 - p, 2.4)
                    RoundedRectangle(cornerRadius: 14 + Self.reach * eased, style: .continuous)
                        .stroke(EagleTelegramButton.blue.opacity(0.75 * (1 - p)), lineWidth: 1.6 * (1 - p) + 0.4)
                        .padding(-Self.reach * eased)
                        .opacity(raw < 0.62 ? 1 : 0)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
