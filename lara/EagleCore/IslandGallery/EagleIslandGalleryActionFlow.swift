import Foundation

/// Owns Apply/Restore sequencing, not the native executor or its result contract.
/// Retains the unstructured main-actor task and reset-before-feedback ordering.
@MainActor
enum EagleIslandGalleryActionFlow {
    static func apply<Artwork, Theme, Response>(
        _ item: Artwork,
        isApplying: () -> Bool,
        select: (Artwork) -> Void,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        liveTheme: @escaping @MainActor @Sendable (Artwork) -> Theme?,
        applyLive: @escaping @MainActor @Sendable (Theme) async -> Response,
        applyStyle: @escaping @MainActor @Sendable (Artwork) async -> Response,
        feedback: @escaping @MainActor @Sendable (Response) -> Void,
        notify: @escaping @MainActor @Sendable (Response) -> Void
    ) {
        guard !isApplying() else { return }
        select(item)
        setApplying(true)
        Task { @MainActor in
            let response: Response
            if let theme = liveTheme(item) {
                response = await applyLive(theme)
            } else {
                response = await applyStyle(item)
            }
            setApplying(false)
            feedback(response)
            notify(response)
        }
    }

    static func restore<Response>(
        isApplying: () -> Bool,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        execute: @escaping @MainActor @Sendable () async -> Response,
        feedback: @escaping @MainActor @Sendable (Response) -> Void,
        notify: @escaping @MainActor @Sendable (Response) -> Void
    ) {
        guard !isApplying() else { return }
        setApplying(true)
        Task { @MainActor in
            let response = await execute()
            setApplying(false)
            feedback(response)
            notify(response)
        }
    }
}
