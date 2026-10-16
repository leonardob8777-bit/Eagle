import Foundation

/// Accepts media readiness only for the currently displayed theme. Storage and
/// media rendering stay at the screen boundary; no callbacks are retained.
@MainActor
enum EagleDockGalleryPreviewReadiness {
    static func update(
        _ ready: Bool,
        themeID: String,
        selectedThemeID: () -> String?,
        readyPreviewID: () -> String,
        setReadyPreviewID: (String) -> Void
    ) {
        guard selectedThemeID() == themeID else { return }
        if ready {
            setReadyPreviewID(themeID)
        } else if readyPreviewID() == themeID {
            setReadyPreviewID("")
        }
    }
}
