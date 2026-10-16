import SwiftUI

/// Existing Apply control; the screen retains eligibility and native execution.
@MainActor
struct EagleAuraStudioApplyButton {
    let apply: () -> Void
    let accessReady: () -> Bool
    let modeTitle: () -> String
    let foreground: () -> Color
    let background: () -> Color
    let isDark: () -> Bool
    let surfaceBorder: () -> Color
    let isDisabled: () -> Bool
    let targetTitle: () -> String
    let localizedText: (String, String) -> String

    var button: some View {
        Button {
            apply()
        } label: {
            Label(
                accessReady()
                    ? localizedText(
                        "Apply \(modeTitle())",
                        "Aplicar \(modeTitle())"
                    )
                    : localizedText(
                        "System Access Required",
                        "Se requiere acceso al sistema"
                    ),
                systemImage: accessReady() ? "sparkles" : "lock.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(foreground())
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                background(),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        !accessReady()
                            ? Color.red.opacity(isDark() ? 0.42 : 0.30)
                            : surfaceBorder(),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(EagleApplyButtonStyle(fill: nil))
        .disabled(isDisabled())
        .accessibilityHint(localizedText(
            "Changes only \(targetTitle()).",
            "Cambia únicamente \(targetTitle())."
        ))
    }
}
