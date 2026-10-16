import SwiftUI

/// Existing Apply colors only. Eligibility and execution remain at their existing boundaries.
@MainActor
struct EagleAuraStudioButtonStyles {
    let isDisabled: () -> Bool
    let isDark: () -> Bool
    let accessReady: () -> Bool
    let actionText: () -> Color
    let actionFill: () -> Color

    var applyButtonForeground: Color {
        isDisabled()
            ? (isDark() ? Color.white.opacity(0.86) : Color.black.opacity(0.78))
            : actionText()
    }

    var applyButtonBackground: Color {
        if !accessReady() {
            return Color.red.opacity(isDark() ? 0.24 : 0.13)
        }
        if isDisabled() {
            return Color.primary.opacity(isDark() ? 0.14 : 0.09)
        }
        return actionFill()
    }
}
