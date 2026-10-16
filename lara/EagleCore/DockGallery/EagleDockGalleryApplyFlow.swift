import Foundation

/// Owns remote Apply coordination, not package I/O, UI effects or native execution.
/// Retains the original guarded snapshot, unstructured Task and completion order.
@MainActor
enum EagleDockGalleryApplyFlow {
    static func start(
        _ theme: EagleDockGalleryTheme,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        intensity: () -> Double,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        prepare: @escaping @MainActor @Sendable (EagleDockGalleryTheme) async throws -> URL,
        apply: @escaping @MainActor @Sendable (EagleDockGalleryApplyRequest) async -> EagleDockGalleryOutcome,
        successFeedback: @escaping @MainActor @Sendable () -> Void,
        notify: @escaping @MainActor @Sendable (Bool, String) -> Void,
        preparationFailureMessage: @escaping @MainActor @Sendable () -> String
    ) {
        guard !isApplying(), downloadingID() == nil else { return }
        let requestedIntensity = intensity()
        setApplying(true)
        Task { @MainActor in
            do {
                let directory = try await prepare(theme)
                let result = await apply(EagleDockGalleryApplyRequest(
                    theme: theme,
                    directory: directory,
                    intensity: requestedIntensity
                ))
                if result.succeeded {
                    successFeedback()
                }
                notify(result.succeeded, result.message)
            } catch {
                notify(false, preparationFailureMessage())
            }
            setApplying(false)
        }
    }
}
