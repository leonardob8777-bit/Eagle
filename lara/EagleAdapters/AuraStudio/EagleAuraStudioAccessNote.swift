import SwiftUI

/// Existing read-only access note; decisions and native access remain outside this view adapter.
@MainActor
struct EagleAuraStudioAccessNote {
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let accessReady: () -> Bool
    let lightColor: () -> Color
    let capabilityTitle: () -> String
    let capabilityDescription: () -> String
    let engineBuild: () -> String
    let channelTitle: () -> String
    let displayZoomed: () -> Bool

    var note: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: localSafetyBlocked() || remoteSafetyLocked()
                  ? "exclamationmark.shield.fill"
                  : (accessReady() ? "checkmark.shield.fill" : "lock.shield.fill"))
                .foregroundStyle(
                    localSafetyBlocked() || remoteSafetyLocked()
                        ? Color.orange
                        : lightColor()
                )
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(capabilityTitle())
                    .font(.subheadline.weight(.semibold))
                Text(capabilityDescription())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(
                    "Aura Engine \(engineBuild()) · \(channelTitle()) · " +
                    (displayZoomed() ? "Display Zoom" : "Standard")
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
