import Foundation

/// Preview-only color and motion calculations; rendering, clock and color reads are supplied by the view.
nonisolated enum EagleAuraStudioPreview {
    static func compactIslandSize(
        readLogicalWidth: () -> CGFloat,
        readCompactWidth: () -> CGFloat,
        readCompactHeight: () -> CGFloat
    ) -> CGSize {
        let logicalWidth = max(readLogicalWidth(), 1)
        let canvasWidth: CGFloat = 318
        let scaledWidth = readCompactWidth() /
            logicalWidth * canvasWidth
        let aspect = readCompactHeight() /
            max(readCompactWidth(), 1)
        let width = max(96, min(122, scaledWidth))
        return CGSize(width: width, height: max(31, width * aspect))
    }

    static func tintFill<Color>(
        readRed: () -> Double,
        readGreen: () -> Double,
        readBlue: () -> Double,
        makeColor: (Double, Double, Double) -> Color
    ) -> Color {
        let red = readRed()
        let green = readGreen()
        let blue = readBlue()
        let brightest = max(red, max(green, blue))
        let scale = brightest > (112.0 / 255.0)
            ? (112.0 / 255.0) / brightest
            : 1.0
        return makeColor(
            red * scale,
            green * scale,
            blue * scale
        )
    }

    static func spectrumHue(for mode: EagleAuraStudioMode, now: () -> Date) -> Double {
        switch mode {
        case .rainbow:
            return spectrumPhase(at: now())
        case .photo, .photoRainbow, .photoInferno, .photoSky, .photoVortex,
             .photoBubblegum, .photoTraffic:
            return 0.73
        case .glow, .pulse, .tint:
            return 0
        }
    }

    static func spectrumPhase(at date: Date) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / 5.2
        return cycles - floor(cycles)
    }

    static func pulseLevel(at date: Date) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / 2.3
        let phase = cycles - floor(cycles)
        let wave = 0.5 - (0.5 * cos(phase * 2 * Double.pi))
        return 0.58 + (0.42 * wave)
    }
}
