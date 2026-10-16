import Foundation

/// Owns built-in Apply coordination, not native execution or UI effects.
/// Unlike remote Apply, intensity is read inside the Task and busy resets before feedback.
@MainActor
enum EagleDockGalleryBuiltInApplyFlow {
    static func start(
        _ style: EagleDockGalleryBuiltInTheme,
        isApplying: () -> Bool,
        selectStyle: (Int) -> Void,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        intensity: @escaping @MainActor @Sendable () -> Double,
        apply: @escaping @MainActor @Sendable (EagleDockGalleryBuiltInTheme, Double) async -> EagleDockGalleryOutcome,
        successFeedback: @escaping @MainActor @Sendable () -> Void,
        notify: @escaping @MainActor @Sendable (Bool, String) -> Void
    ) {
        guard !isApplying() else { return }
        selectStyle(style.rawValue)
        setApplying(true)
        Task { @MainActor in
            let result = await apply(style, intensity())
            setApplying(false)
            if result.succeeded {
                successFeedback()
            }
            notify(result.succeeded, result.message)
        }
    }
}
