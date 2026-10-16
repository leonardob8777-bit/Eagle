import Foundation

/// Coordinates Gallery actions synchronously, preserving guarded reads and
/// committing the session before persistence, synchronization or feedback.
@MainActor
enum EagleDockGalleryInteractions {
    static func selectCategory(
        _ filter: EagleDockGalleryMediaFilter,
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        selectedThemeID: () -> String?,
        synchronize: () -> Void,
        feedback: () -> Void
    ) {
        guard readSession().mediaFilter != filter, !isApplying(), downloadingID() == nil else { return }
        let selectedThemeID = selectedThemeID()
        var updated = readSession()
        updated.selectCategory(filter, remembering: selectedThemeID)
        writeSession(updated)
        synchronize()
        feedback()
    }

    static func step(
        _ step: Int,
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        visibleThemes: () -> [EagleDockGalleryTheme],
        rememberViewedTheme: () -> Void,
        feedback: () -> Void
    ) {
        guard !isApplying(), downloadingID() == nil else { return }
        let themes = visibleThemes()
        guard themes.count > 1 else { return }
        var updated = readSession()
        updated.step(step, in: themes)
        writeSession(updated)
        rememberViewedTheme()
        feedback()
    }

    static func toggleFavorite(
        _ theme: EagleDockGalleryTheme,
        readFavorites: () -> Set<String>,
        writeFavoritesJSON: (String) -> Void,
        synchronize: () -> Void,
        feedback: () -> Void
    ) {
        let ids = EagleDockGalleryFavorites.toggling(readFavorites(), id: theme.id)
        guard let json = EagleDockGalleryFavorites.encode(ids) else { return }
        // Store catalog IDs, so favorites survive app restarts and asset updates.
        writeFavoritesJSON(json)
        synchronize()
        feedback()
    }

    static func beginVisit(
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        synchronize: () -> Void
    ) {
        var updated = readSession()
        updated.beginVisit()
        writeSession(updated)
        synchronize()
    }
}
