import Foundation
import UIKit
import CryptoKit

typealias IslandLiveManifest = EagleIslandGalleryManifest
typealias IslandLiveTheme = EagleIslandGalleryTheme
private typealias IslandLiveCatalog = EagleIslandGalleryCatalog

/// An isolated, on-demand Island package. Dock caches and configuration are
/// never reused or overwritten. The frame alpha is Vortex's original mask.
nonisolated enum IslandLiveMedia {
    static let previewURL = URL(string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/previews/island/singularity-live.gif")!
    static let posterURL = URL(string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/previews/island/singularity-live.png")!

    static func loadCatalog(force: Bool = false) async throws -> [IslandLiveTheme] {
        try await EagleIslandGalleryCatalogLoader.loadCatalog(force: force)
    }

    static func prepare(theme: IslandLiveTheme? = nil) async throws -> URL {
        try await EagleIslandGalleryPackage.prepare(theme: theme, log: EagleAppDiagnostics.log)
    }
}
