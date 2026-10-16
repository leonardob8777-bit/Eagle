import SwiftUI

/// Existing Island/Dock/Icons navigation UI; state, storage and hardware checks stay with the screen.
@MainActor
struct EagleAuraStudioSurfacePicker {
    let readEditingIcons: () -> Bool
    let writeEditingIcons: (Bool) -> Void
    let readTarget: () -> EagleAuraStudioTarget
    let writeTarget: (EagleAuraStudioTarget) -> Void
    let islandAvailable: () -> Bool
    let operationInProgress: () -> Bool
    let modeTitle: (EagleAuraStudioTarget) -> String
    let localizedText: (String, String) -> String

    var surfaceProfilesCard: some View {
        HStack(spacing: 8) {
            ForEach(EagleAuraStudioTarget.allCases) { target in
                profileButton(for: target)
            }
            homeIconCompactLink
        }
    }

    func profileButton(for target: EagleAuraStudioTarget) -> some View {
        let isSelected = !readEditingIcons() && readTarget() == target
        let isHardwareAvailable = target != .island || islandAvailable()

        return Button {
            writeEditingIcons(false)
            writeTarget(target)
        } label: {
            tile(
                icon: target == .island ? "capsule.fill" : "dock.rectangle",
                title: target == .island ? "Island" : target.title,
                selected: isSelected
            )
        }
        .buttonStyle(EaglePressableStyle(kind: .card))
        .disabled(operationInProgress() || !isHardwareAvailable)
        .opacity(isHardwareAvailable ? 1 : 0.64)
        .accessibilityLabel(target.title)
        .accessibilityValue(modeTitle(target))
        .accessibilityHint(localizedText(
            isHardwareAvailable
                ? "Edits only this surface."
                : "This model has no verified Dynamic Island. Dock remains available.",
            isHardwareAvailable
                ? "Edita únicamente esta superficie."
                : "Este modelo no tiene una Dynamic Island verificada. El Dock sigue disponible."
        ))
    }

    var homeIconCompactLink: some View {
        Button {
            writeEditingIcons(true)
        } label: {
            tile(icon: "app.fill", title: localizedText("Icons", "Iconos"), selected: readEditingIcons())
        }
        .buttonStyle(EaglePressableStyle(kind: .card))
        .disabled(operationInProgress())
        .accessibilityLabel(localizedText("Home Icon Neon", "Neón de iconos"))
    }

    /// One option. Solid colours, so it reads the same on the light top of the backdrop as on the dark:
    /// the chosen one in the action colours (white with black text in dark appearance, black with white
    /// text in light), the others on their own opaque surface with a hairline.
    private func tile(icon: String, title: String, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let ink: Color = selected ? EagleVisualTheme.actionText : .primary
        return HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 28, height: 28)
                .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(selected ? EagleVisualTheme.actionFill : Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        .overlay {
            shape.strokeBorder(Color.primary.opacity(selected ? 0 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .contentShape(Rectangle())
    }
}
