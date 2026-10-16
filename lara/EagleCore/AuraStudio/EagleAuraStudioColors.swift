import Foundation

/// Color data and draft-update decisions; platform Color conversion and storage stay injected.
@MainActor
enum EagleAuraStudioColors {
    static func presets(localizedText: (String, String) -> String) -> [(name: String, red: Double, green: Double, blue: Double)] {
        [
            (localizedText("Electric Blue", "Azul eléctrico"), 0.10, 0.78, 1.00),
            (localizedText("Ultra Violet", "Ultravioleta"), 0.62, 0.25, 1.00),
            (localizedText("Hot Pink", "Rosa intenso"), 1.00, 0.16, 0.62),
            (localizedText("Acid Green", "Verde ácido"), 0.42, 1.00, 0.24),
        ]
    }

    static func presetIsSelected(
        _ preset: (name: String, red: Double, green: Double, blue: Double),
        selectedRGB: () -> (Double, Double, Double)
    ) -> Bool {
        let selectedRGB = selectedRGB()
        let tolerance = 0.002
        return abs(selectedRGB.0 - preset.red) < tolerance &&
            abs(selectedRGB.1 - preset.green) < tolerance &&
            abs(selectedRGB.2 - preset.blue) < tolerance
    }

    static func setSelectedRGB(
        red: Double, green: Double, blue: Double,
        isIsland: @autoclosure () -> Bool,
        writeIsland: (Double, Double, Double) -> Void,
        writeDock: (Double, Double, Double) -> Void
    ) {
        let nextRed = sanitizedChannel(red)
        let nextGreen = sanitizedChannel(green)
        let nextBlue = sanitizedChannel(blue)
        if isIsland() {
            writeIsland(nextRed, nextGreen, nextBlue)
        } else {
            writeDock(nextRed, nextGreen, nextBlue)
        }
    }

    static func sanitizedChannel(_ value: Double, fallback: Double = 0) -> Double {
        guard value.isFinite else { return fallback }
        return max(0, min(1, value))
    }

    static func channel255(_ value: Double) -> Int {
        Int((sanitizedChannel(value) * 255).rounded())
    }
}
