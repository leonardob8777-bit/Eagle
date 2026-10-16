import Foundation

/// Catalog decoding and selection, independent of Gallery UI or transport.
/// Decode every entry before checking the schema and filtering supported themes.
nonisolated struct EagleDockGalleryCatalog: Decodable, Sendable {
    let schemaVersion: Int
    let themes: [EagleDockGalleryTheme]

    static func decodeSupportedThemes(from data: Data) throws -> [EagleDockGalleryTheme] {
        let catalog = try JSONDecoder().decode(EagleDockGalleryCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else { throw URLError(.cannotParseResponse) }
        return catalog.themes.filter { $0.isSupportedPackage }
    }
}
