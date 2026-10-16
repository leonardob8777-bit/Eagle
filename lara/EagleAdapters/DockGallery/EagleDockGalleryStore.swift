import Foundation
import Combine

/// Owns Gallery display state and its benign data services outside the screen.
/// App localization and diagnostics stay injected and are evaluated when needed.
@MainActor
final class EagleDockGalleryStore: ObservableObject {
    @Published private(set) var themes: [EagleDockGalleryTheme] = []
    @Published private(set) var loading = false
    @Published private(set) var downloadingID: String?
    @Published private(set) var errorMessage: String?

    private let catalogLoader: EagleDockGalleryCatalogLoader
    private let packagePreparation: EagleDockGalleryPackagePreparation
    private let catalogFailureMessage: @MainActor @Sendable () -> String
    private let diagnostics: @MainActor @Sendable () -> (@Sendable (String) -> Void)

    init(
        catalogLoader: EagleDockGalleryCatalogLoader = EagleDockGalleryCatalogLoader(),
        packagePreparation: EagleDockGalleryPackagePreparation = EagleDockGalleryPackagePreparation(),
        catalogFailureMessage: @escaping @MainActor @Sendable () -> String,
        diagnostics: @escaping @MainActor @Sendable () -> (@Sendable (String) -> Void)
    ) {
        self.catalogLoader = catalogLoader
        self.packagePreparation = packagePreparation
        self.catalogFailureMessage = catalogFailureMessage
        self.diagnostics = diagnostics
    }

    func load(force: Bool = false) async {
        if loading || (!force && !themes.isEmpty) { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            themes = try await catalogLoader.load(force: force)
        } catch {
            errorMessage = catalogFailureMessage()
        }
    }

    func prepare(_ theme: EagleDockGalleryTheme) async throws -> URL {
        return try await packagePreparation.prepare(
            theme,
            diagnostics: diagnostics,
            willDownload: { self.downloadingID = theme.id },
            didFinish: { self.downloadingID = nil }
        )
    }

    private static func isSupported(_ theme: EagleDockGalleryTheme) -> Bool {
        theme.isSupportedPackage
    }
}
