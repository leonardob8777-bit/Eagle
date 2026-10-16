import Foundation

nonisolated struct EagleIslandGalleryManifest: Codable, Sendable {
    let schemaVersion: Int
    let id: String
    let version: Int
    let packageURL: URL
    let sha256: String
    let byteCount: Int
    let frameCount: Int
    let fps: Double
    let width: Int
    let height: Int
    let frameSHA256: [String]

    var isSupported: Bool {
        let validID = id.range(of: "^[a-z0-9][a-z0-9-]{0,79}$", options: .regularExpression) != nil
        let release = id == "singularity-live" ? "island-v1" : "island-gifs-v1"
        return schemaVersion == 1 && validID && version == 1 &&
        packageURL.absoluteString == "https://github.com/leonardob8777-bit/Eagle-Gallery/releases/download/\(release)/\(id)-v1.zip" &&
        frameCount == 17 && fps == 6 && width == 1200 && height == 500 &&
        byteCount > 0 && byteCount <= 34 * 1024 * 1024 &&
        frameSHA256.count == 17 && ([sha256] + frameSHA256).allSatisfy {
            $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) }
        }
    }
}

nonisolated struct EagleIslandGalleryTheme: Decodable, Identifiable, Sendable {
    let manifest: EagleIslandGalleryManifest
    let title: String
    let titleES: String
    let accent: String
    let previewURL: URL
    let posterURL: URL
    var id: String { manifest.id }
    // Still sources are packaged as 17 repeated frames for the same native
    // renderer. Classify by verified frame hashes, not the ZIP frame count.
    var isAnimated: Bool {
        guard let first = manifest.frameSHA256.first else { return false }
        return manifest.frameSHA256.dropFirst().contains { $0 != first }
    }

    private enum CodingKeys: String, CodingKey { case title, titleES, accent, previewURL, posterURL }
    init(from decoder: Decoder) throws {
        manifest = try EagleIslandGalleryManifest(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        titleES = try values.decode(String.self, forKey: .titleES)
        accent = try values.decode(String.self, forKey: .accent)
        previewURL = try values.decode(URL.self, forKey: .previewURL)
        posterURL = try values.decode(URL.self, forKey: .posterURL)
    }
    var isSupported: Bool {
        let base = "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/previews/island/"
        return manifest.isSupported && !title.isEmpty && title.count <= 80 &&
            !titleES.isEmpty && titleES.count <= 80 &&
            accent.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil &&
            previewURL.absoluteString == "\(base)\(id).gif" &&
            posterURL.absoluteString == "\(base)\(id).png"
    }
    var rgb: (red: Int32, green: Int32, blue: Int32) {
        let value = UInt32(accent.dropFirst(), radix: 16) ?? 0xD9D9D9
        return (Int32((value >> 16) & 255), Int32((value >> 8) & 255), Int32(value & 255))
    }
}

nonisolated struct EagleIslandGalleryCatalog: Decodable {
    let schemaVersion: Int
    let themes: [EagleIslandGalleryTheme]
    var isSupported: Bool {
        schemaVersion == 1 && !themes.isEmpty && themes.count <= 500 &&
            themes.allSatisfy(\.isSupported) && Set(themes.map(\.id)).count == themes.count
    }
}
