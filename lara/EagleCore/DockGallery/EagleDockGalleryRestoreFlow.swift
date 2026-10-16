import Foundation

/// Owns Restore coordination, not the inherited executor or its result contract.
/// Keeps the original busy guard, unstructured Task and reset-before-feedback order.
@MainActor
enum EagleDockGalleryRestoreFlow {
    static func start(
        isApplying: () -> Bool,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        restore: @escaping @MainActor @Sendable () async -> EagleDockGalleryOutcome,
        successFeedback: @escaping @MainActor @Sendable () -> Void,
        notify: @escaping @MainActor @Sendable (Bool, String) -> Void
    ) {
        guard !isApplying() else { return }
        setApplying(true)
        Task { @MainActor in
            let result = await restore()
            setApplying(false)
            if result.succeeded {
                successFeedback()
            }
            notify(result.succeeded, result.message)
        }
    }
}
