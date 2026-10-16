import Foundation

/// Shared Aura style metadata; policy, preferences, rendering and execution stay at the app boundary.
nonisolated enum EagleAuraStudioMode: Int, CaseIterable, Identifiable, Sendable {
    case glow = 1
    case pulse = 2
    case tint = 3
    case rainbow = 4
    case photo = 8
    case photoRainbow = 9
    case photoInferno = 10
    case photoSky = 11
    case photoVortex = 12
    case photoBubblegum = 13
    case photoTraffic = 14

    var id: Int { rawValue }

    func title(localizedText: (String, String) -> String) -> String {
        switch self {
        case .glow: return localizedText("Glow", "Brillo")
        case .pulse: return localizedText("Pulse", "Pulso")
        case .tint: return localizedText("Tint", "Color")
        case .rainbow: return localizedText("Rainbow", "Arcoíris")
        case .photo: return localizedText("Photo", "Foto")
        case .photoRainbow: return localizedText("Starlight", "Luz estelar")
        case .photoInferno: return localizedText("Inferno", "Inferno")
        case .photoSky: return localizedText("Horizon", "Horizonte")
        case .photoVortex: return localizedText("Vortex", "Vórtice")
        case .photoBubblegum: return localizedText("Bubblegum", "Chicle")
        case .photoTraffic: return localizedText("Traffic", "Tráfico")
        }
    }

    func summary(localizedText: (String, String) -> String) -> String {
        switch self {
        case .glow:
            return localizedText(
                "Keeps the system-black center and adds a thick, bright outer light.",
                "Mantiene el centro negro del sistema y añade una luz exterior gruesa e intensa."
            )
        case .pulse:
            return localizedText(
                "The current surface breathes gently without changing the other profile.",
                "La superficie actual respira suavemente sin cambiar el otro perfil."
            )
        case .tint:
            return localizedText(
                "Replaces the software-black center with color; only the physical camera cutouts stay black.",
                "Reemplaza el centro negro generado por software con color; solo los recortes físicos de la cámara permanecen negros."
            )
        case .rainbow:
            return localizedText(
                "A vivid spectrum moves through the background, bright edge, and outer light.",
                "Un espectro intenso recorre el fondo, el borde brillante y la luz exterior."
            )
        case .photo, .photoRainbow, .photoInferno, .photoSky, .photoVortex,
             .photoBubblegum, .photoTraffic:
            return localizedText(
                "A photographic Island style with a fixed high-contrast halo.",
                "Un estilo fotográfico para Island con un halo fijo de alto contraste."
            )
        }
    }

    var usesFixedPalette: Bool {
        self == .rainbow || isPhotoTexture
    }

    var isPhotoTexture: Bool {
        [.photo, .photoRainbow, .photoInferno, .photoSky, .photoVortex,
         .photoBubblegum, .photoTraffic].contains(self)
    }

    var photoAssetName: String? {
        switch self {
        case .photo: return "PhotoAuraGalaxy"
        case .photoRainbow: return "PhotoAuraRainbow"
        case .photoInferno: return "PhotoAuraInferno"
        case .photoSky: return "PhotoAuraSky"
        case .photoVortex: return "PhotoAuraVortex"
        case .photoBubblegum: return "PhotoAuraBubblegum"
        case .photoTraffic: return "PhotoAuraTraffic"
        default: return nil
        }
    }

    var fillsIslandBackground: Bool {
        self == .tint || self == .rainbow
    }
}
