import Foundation

/// Coordinates the existing visit lifecycle without retaining callbacks or
/// introducing scheduled retries. The screen maps its scene phase and storage.
@MainActor
enum EagleDockGalleryLifecycle {
    nonisolated enum Phase: Sendable {
        case active, background, other
    }

    static func appear(
        visitStarted: () -> Bool,
        beginVisit: () -> Void
    ) {
        if !visitStarted() { beginVisit() }
    }

    static func disappear(
        showAccessSetup: () -> Bool,
        setVisitStarted: (Bool) -> Void
    ) {
        // Returning from access setup must keep the theme being prepared.
        if !showAccessSetup() { setVisitStarted(false) }
    }

    static func sceneChanged(
        _ phase: Phase,
        visitStarted: () -> Bool,
        needsNewVisitOnResume: () -> Bool,
        setNeedsNewVisitOnResume: (Bool) -> Void,
        showAccessSetup: () -> Bool,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        beginVisit: () -> Void
    ) {
        if phase == .background, visitStarted() {
            setNeedsNewVisitOnResume(true)
        } else if phase == .active, needsNewVisitOnResume() {
            setNeedsNewVisitOnResume(false)
            if visitStarted(), !showAccessSetup(), !isApplying(), downloadingID() == nil {
                beginVisit()
            }
        }
    }
}
