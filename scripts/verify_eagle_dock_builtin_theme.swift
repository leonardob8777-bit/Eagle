import Foundation

@main
private enum EagleDockBuiltInThemeContract {
    static func main() {
        MainActor.preconditionIsolated()
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let ids = [15, 16, 17, 28, 29, 30]
        let assets = ["DockGalleryBubblegum", "DockGallerySpringfield", "DockGalleryBikiniBottom",
                      "DockGalleryDuckMood", "DockGalleryBlueScreen", "DockGalleryWalkingFlame"]
        // These floating-point fixtures are deliberately not derived from rgb.
        // Public Color literals and native integer triplets are independent values.
        let accents: [(Double, Double, Double)] = [
            (1.0, 0.18, 0.62), (0.0, 0.64, 1.0), (0.0, 0.75, 0.92),
            (1.0, 0.47, 0.08), (0.10, 0.28, 1.0), (1.0, 0.30, 0.06),
        ]
        let nativeColors: [(Int32, Int32, Int32)] = [
            (255, 45, 158), (0, 164, 255), (0, 191, 235),
            (255, 120, 20), (26, 71, 255), (255, 77, 15),
        ]
        let publicThemes = PublicDockGalleryStyle.allCases
        let ownedThemes = EagleDockGalleryBuiltInTheme.allCases
        expect(publicThemes.map(\.rawValue) == ids, "Public case order or IDs changed")
        expect(ownedThemes.map(\.rawValue) == ids, "Owned case order or IDs changed")
        expect(ownedThemes.map(\.id) == publicThemes.map(\.id), "Identifiable projection changed")
        expect(ownedThemes.map(\.assetName) == assets, "Owned asset mapping changed")

        for raw in Array(-3...35) + [Int.min, Int.max] {
            expect(EagleDockGalleryBuiltInTheme(rawValue: raw)?.rawValue ==
                   PublicDockGalleryStyle(rawValue: raw)?.rawValue, "Raw-value round trip changed")
        }
        let timeValues: [Double] = [
            0, 1, -1, 1.0 / 6.0, -1.0 / 6.0, 17.0 / 6.0, -17.0 / 6.0,
            .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
            Date.distantPast.timeIntervalSinceReferenceDate,
            Date.distantFuture.timeIntervalSinceReferenceDate,
        ]
        for (index, owned) in ownedThemes.enumerated() {
            let reference = publicThemes[index]
            expect(owned.rawValue == reference.rawValue && owned.id == reference.id, "Case identity changed")
            expect(owned.assetName == reference.assetName, "Public asset name differs")
            expect(!owned.isAnimated && owned.isAnimated == reference.isAnimated, "Static flag changed")
            let rgb = owned.rgb
            let publicRGB = reference.rgb
            let expectedRGB = nativeColors[index]
            expect(rgb.0 == publicRGB.0 && rgb.1 == publicRGB.1 && rgb.2 == publicRGB.2, "Public rgb projection differs")
            expect(rgb.0 == expectedRGB.0 && rgb.1 == expectedRGB.1 && rgb.2 == expectedRGB.2, "Native rgb fixture changed")

            LaraL10n.reset(language: "en")
            let titleText = owned.titleText
            let subtitleText = owned.subtitleText
            let components = owned.accentComponents
            expect(LaraL10n.calls.isEmpty, "Pure metadata evaluated app localization")
            let publicColor = reference.accent
            let ownedColor = owned.accent
            let expected = accents[index]
            for (actual, original, projected, literal) in [
                (components.red, publicColor.red, ownedColor.red, expected.0),
                (components.green, publicColor.green, ownedColor.green, expected.1),
                (components.blue, publicColor.blue, ownedColor.blue, expected.2),
            ] {
                expect(actual.bitPattern == original.bitPattern, "Exact public floating-point accent changed")
                expect(actual.bitPattern == literal.bitPattern, "Independent accent fixture changed")
                expect(projected.bitPattern == actual.bitPattern, "UI Color projection changed")
            }
            expect(LaraL10n.calls.isEmpty, "Color projection unexpectedly localized text")

            // Repeated language changes occur after the same enum instance exists.
            // Check both selected values and the public invocation count/arguments.
            for language in ["en", "es", "es", "en"] {
                LaraL10n.reset(language: language)
                let actualTitle = owned.title
                let titleCalls = LaraL10n.calls
                LaraL10n.reset(language: language)
                let originalTitle = reference.title
                expect(actualTitle == originalTitle, "Localized title differs")
                expect(titleCalls == LaraL10n.calls, "Title localization arguments/count changed")
                expect(titleCalls.count == (owned == .springfield ? 0 : 1), "Springfield must bypass title localization")
                expect(actualTitle == (language == "es" ? titleText.es : titleText.en), "Bilingual title metadata differs")

                LaraL10n.reset(language: language)
                let actualSubtitle = owned.subtitle
                let subtitleCalls = LaraL10n.calls
                LaraL10n.reset(language: language)
                let originalSubtitle = reference.subtitle
                expect(actualSubtitle == originalSubtitle, "Localized subtitle differs")
                expect(subtitleCalls == LaraL10n.calls && subtitleCalls.count == 1, "Subtitle localization arguments/count changed")
                expect(actualSubtitle == (language == "es" ? subtitleText.es : subtitleText.en), "Bilingual subtitle metadata differs")
            }
            for time in timeValues {
                let date = Date(timeIntervalSinceReferenceDate: time)
                let original = reference.previewAsset(at: date)
                let actual = owned.previewAsset(at: date)
                expect(original == reference.assetName && actual == owned.assetName && actual == original,
                       "Static preview evaluated time/frame conversion or changed assets")
            }
        }
        print("PASS: \(checks) public/owned built-in Dock theme checks across 6 styles, exact IDs/assets/rgb/floating accents, EN/ES late localization and call counts, and \(timeValues.count) ordinary/nonfinite/extreme preview dates; no UI runtime or native engine")
    }
}
