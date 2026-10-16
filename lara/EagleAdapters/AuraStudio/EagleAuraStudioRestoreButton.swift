import SwiftUI

/// Existing Restore control; the screen retains the action and native executor.
@MainActor
struct EagleAuraStudioRestoreButton {
    let restore: () -> Void
    let operationInProgress: () -> Bool
    let accessReady: () -> Bool
    let selectedFlags: () -> UInt32
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let targetTitle: () -> String
    let localizedText: (String, String) -> String

    var button: some View {
        Button {
            restore()
        } label: {
            Label(
                localizedText("Restore", "Restaurar"),
                systemImage: "arrow.counterclockwise"
            )
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
        }
        .buttonStyle(.bordered)
        .disabled(
            operationInProgress() || !accessReady() || selectedFlags() == 0 ||
            localSafetyBlocked() || remoteSafetyLocked()
        )
        .opacity(!accessReady() || localSafetyBlocked() || remoteSafetyLocked() ? 0.52 : 1)
        .accessibilityHint(localizedText(
            "Restores only \(targetTitle()) and keeps the other aura active.",
            "Restaura únicamente \(targetTitle()) y mantiene activa la otra aura."
        ))
    }
}
