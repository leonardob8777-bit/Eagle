import Foundation

/// Color selection and conversion decisions; storage and platform color construction stay injected.
@MainActor
struct EagleAuraStudioColorPresentation<ColorValue> {
    let readDraftRed: (EagleAuraStudioTarget) -> Double
    let readDraftGreen: (EagleAuraStudioTarget) -> Double
    let readDraftBlue: (EagleAuraStudioTarget) -> Double
    let readActiveRGB: (EagleAuraStudioTarget) -> (Int, Int, Int)
    let islandFlag: UInt32
    let mode: (EagleAuraStudioTarget) -> EagleAuraStudioMode
    let spectrumHue: (EagleAuraStudioMode) -> Double
    let sanitize: (Double) -> Double
    let makeRGB: (Double, Double, Double) -> ColorValue
    let makeHSB: (Double, Double, Double) -> ColorValue

    func color(for target: EagleAuraStudioTarget) -> ColorValue {
        switch target {
        case .island:
            return makeRGB(
                sanitize(readDraftRed(.island)),
                sanitize(readDraftGreen(.island)),
                sanitize(readDraftBlue(.island))
            )
        case .dock:
            return makeRGB(
                sanitize(readDraftRed(.dock)),
                sanitize(readDraftGreen(.dock)),
                sanitize(readDraftBlue(.dock))
            )
        }
    }

    func previewLightColor(for target: EagleAuraStudioTarget) -> ColorValue {
        let mode = mode(target)
        return mode.usesFixedPalette
            ? makeHSB(
                spectrumHue(mode),
                0.96,
                1.0
            )
            : color(for: target)
    }

    func activeColor(for flag: UInt32) -> ColorValue {
        let rgb = flag == islandFlag
            ? readActiveRGB(.island)
            : readActiveRGB(.dock)
        return makeRGB(
            Double(rgb.0) / 255.0,
            Double(rgb.1) / 255.0,
            Double(rgb.2) / 255.0
        )
    }
}
