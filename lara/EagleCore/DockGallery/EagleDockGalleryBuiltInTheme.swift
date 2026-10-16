import Foundation

/// Built-in Dock theme metadata and asset selection, independent of the screen.
/// Display colors deliberately retain their original values separately from RGB.
nonisolated enum EagleDockGalleryBuiltInTheme: Int, CaseIterable, Identifiable, Sendable {
    case bubblegum = 15
    case springfield = 16
    case bikiniBottom = 17
    case duckMood = 28
    case blueScreen = 29
    case walkingFlame = 30

    var id: Int { rawValue }

    var titleText: (en: String, es: String) {
        switch self {
        case .bubblegum: return ("Bubblegum", "Chicle")
        case .springfield: return ("Springfield", "Springfield")
        case .bikiniBottom: return ("Bikini Bottom", "Fondo de Bikini")
        case .duckMood: return ("Duck Mood", "Humor de pato")
        case .blueScreen: return ("Blue Screen", "Pantalla azul")
        case .walkingFlame: return ("Walking Flame", "Llama ambulante")
        }
    }

    var subtitleText: (en: String, es: String) {
        switch self {
        case .bubblegum: return ("Pink and yellow bubbles", "Burbujas rosas y amarillas")
        case .springfield: return ("Bright blue animated city", "Ciudad animada azul brillante")
        case .bikiniBottom: return ("Colorful underwater neighborhood", "Vecindario submarino colorido")
        case .duckMood: return ("Classic animated duck close-up", "Primer plano de pato animado clásico")
        case .blueScreen: return ("Electric blue system portrait", "Retrato de sistema azul eléctrico")
        case .walkingFlame: return ("Surreal street fire portrait", "Retrato surrealista de fuego urbano")
        }
    }

    var assetName: String {
        switch self {
        case .bubblegum: return "DockGalleryBubblegum"
        case .springfield: return "DockGallerySpringfield"
        case .bikiniBottom: return "DockGalleryBikiniBottom"
        case .duckMood: return "DockGalleryDuckMood"
        case .blueScreen: return "DockGalleryBlueScreen"
        case .walkingFlame: return "DockGalleryWalkingFlame"
        }
    }

    var accentComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .bubblegum: return (1.0, 0.18, 0.62)
        case .springfield: return (0.0, 0.64, 1.0)
        case .bikiniBottom: return (0.0, 0.75, 0.92)
        case .duckMood: return (1.0, 0.47, 0.08)
        case .blueScreen: return (0.10, 0.28, 1.0)
        case .walkingFlame: return (1.0, 0.30, 0.06)
        }
    }

    var rgb: (Int32, Int32, Int32) {
        switch self {
        case .bubblegum: return (255, 45, 158)
        case .springfield: return (0, 164, 255)
        case .bikiniBottom: return (0, 191, 235)
        case .duckMood: return (255, 120, 20)
        case .blueScreen: return (26, 71, 255)
        case .walkingFlame: return (255, 77, 15)
        }
    }

    var isAnimated: Bool {
        return false
    }

    private var animationAssetPrefix: String? {
        nil
    }

    func previewAsset(at date: Date) -> String {
        guard let animationAssetPrefix else { return assetName }
        let frame = Int(date.timeIntervalSinceReferenceDate * 6.0) % 17 + 1
        return String(format: "%@%02d", animationAssetPrefix, frame)
    }
}
