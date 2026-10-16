import Foundation

/// Catalog data and package-format policy, independent of the Gallery UI.
/// Fields, derived values and accepted formats retain the public 1.0.5 behavior.
nonisolated struct EagleDockGalleryTheme: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let version: Int
    let title: String
    let titleES: String
    let subtitle: String
    let subtitleES: String
    let accent: String
    let previewURL: URL
    let animatedPreviewURL: URL?
    let packageURL: URL
    let sha256: String
    let byteCount: Int
    let frameCount: Int
    let fps: Double
    let width: Int
    let height: Int

    var presentationPreviewURL: URL {
        let source = frameCount > 1 ? (animatedPreviewURL ?? previewURL) : previewURL
        var components = URLComponents(url: source, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(
            name: "preview",
            value: "\(version)-\(frameCount > 1 ? "animated" : "static")"
        )]
        return components?.url ?? source
    }
    var rgb: (Int32, Int32, Int32) {
        let hex = accent.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(hex, radix: 16) ?? 0xDB40E0
        return (Int32((value >> 16) & 0xff), Int32((value >> 8) & 0xff), Int32(value & 0xff))
    }
    var duration: Double { Double(frameCount) / fps }

    var isSupportedPackage: Bool {
        ((frameCount == 17 && fps == 6) ||
         (frameCount == 1 && fps == 1)) &&
            width == 1146 && height == 318 &&
            byteCount > 0 && byteCount <= 30 * 1024 * 1024
    }
}
