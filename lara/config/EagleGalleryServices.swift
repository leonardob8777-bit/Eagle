import Foundation

/// App-owned composition. The screen observes this one lazily created Store.
@MainActor
enum EagleGalleryServices {
    static let dock = EagleDockGalleryStore(
        catalogFailureMessage: {
            EagleLocalization.text(
                en: "The online collection could not be loaded.",
                es: "No se pudo cargar la colección en línea."
            )
        },
        diagnostics: { EagleAppDiagnostics.log }
    )
}
