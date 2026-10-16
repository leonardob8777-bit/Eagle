import Foundation

/// Coordinates one Gallery refresh synchronously. The caller supplies storage,
/// randomization and presentation reads; no callback is retained or scheduled.
@MainActor
enum EagleDockGallerySynchronization {
    static func synchronize(
        catalog: () -> [EagleDockGalleryTheme],
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        shuffle: ([String]) -> [String],
        lastViewedStaticID: () -> String,
        lastViewedLiveID: () -> String,
        visibleThemes: () -> [EagleDockGalleryTheme],
        rememberViewedTheme: () -> Void
    ) {
        let update = EagleDockGalleryVisitOrder.pendingUpdate(
            themes: catalog(),
            orderedIDs: readSession().shuffledRemoteIDs
        )
        let additions = shuffle(update.additions)
        let order = update.resolvedOrder(
            shuffledAdditions: additions,
            lastViewedStaticID: lastViewedStaticID(),
            lastViewedLiveID: lastViewedLiveID(),
            themes: catalog()
        )
        if let reorderedSession = readSession().adoptingOrder(order) {
            writeSession(reorderedSession)
        }
        let themes = visibleThemes()
        if let updatedSession = readSession().reconcilingSelection(in: themes) {
            writeSession(updatedSession)
        }
        rememberViewedTheme()
    }
}
