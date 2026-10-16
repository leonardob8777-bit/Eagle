import SwiftUI

private struct EagleDockAlert: Identifiable {
    let id = UUID()
    let message: String
}

struct DockCustomizerView: View {
    @ObservedObject private var mgr = laramgr.shared
    @AppStorage("eagle.dock.capacity") private var selectedCapacity = 5
    @AppStorage("eagle.dock.backgroundRecipeHidden") private var hideDockBackground = false

    @State private var isApplying = false
    @State private var alert: EagleDockAlert?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let capacities = [4, 5, 6]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                dockPreview
                capacityCard
                explanationCard
            }
            .padding(20)
        }
        // Apply stays fixed at the bottom, in reach of the thumb; Prepare takes its place until ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: true) {
                applyButton
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("Dock")
        .navigationBarTitleDisplayMode(.inline)
        .eagleNotice(item: $alert, title: "Dock") { $0.message }
        .overlay {
            if isApplying {
                ZStack {
                    Color.black.opacity(0.14).ignoresSafeArea()
                    VStack(spacing: 12) {
                        EagleRainbowSpinner(size: 28)
                        Text(LaraL10n.text(
                            en: "Updating the Dock…",
                            es: "Actualizando el Dock…"
                        ))
                            .font(.headline)
                    }
                    .padding(22)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .transition(.eagleWorking)
            }
        }
    }

    private var dockPreview: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(LaraL10n.text(en: "More room, same Dock", es: "Más espacio, el mismo Dock"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(capacityDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.25), value: selectedCapacity)
            }

            dockStrip
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    /// The little Dock mock-up. A slow colour wash drifts behind the tiles and
    /// each icon breathes on its own phase, so the preview feels alive without
    /// distracting. Everything freezes cleanly when Reduce Motion is on.
    private var dockStrip: some View {
        let previewCapacity = EagleStoredThemeValues.dockPreviewCapacity(selectedCapacity)
        let compact = previewCapacity == 6
        return EagleAmbientTimeline(paused: reduceMotion) { context in
            ZStack {
                AngularGradient(
                    colors: washColors,
                    center: .center,
                    angle: .degrees(reduceMotion ? 45 : washAngle(at: context.date))
                )
                .blur(radius: 26)
                .opacity(0.85)
                .allowsHitTesting(false)

                HStack(spacing: compact ? 8 : 11) {
                    ForEach(0..<previewCapacity, id: \.self) { index in
                        let glow = reduceMotion ? 0.8 : tileGlow(at: context.date, index: index)
                        RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                            .fill(previewColor(for: index).gradient)
                            .frame(
                                width: compact ? 39 : 45,
                                height: compact ? 39 : 45
                            )
                            .overlay {
                                Image(systemName: previewSymbol(for: index))
                                    .font(.system(size: compact ? 15 : 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(
                                color: previewColor(for: index).opacity(0.45 * glow),
                                radius: 7 * glow,
                                y: 2
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background {
            if !hideDockBackground {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if !hideDockBackground {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: selectedCapacity)
    }

    /// Soft, low-alpha hues for the wash behind the Dock tiles. The first colour
    /// repeats at the end so the angular sweep loops seamlessly.
    private var washColors: [Color] {
        [Color.blue, .indigo, .purple, .pink, .orange, .blue].map { $0.opacity(0.18) }
    }

    /// One slow rotation (0…360) for the colour wash behind the tiles.
    private func washAngle(at date: Date) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / 16.0
        return (cycles - floor(cycles)) * 360
    }

    /// Gentle breathing level (0.55…1.0) for a tile's colour halo, offset per
    /// icon so the row shimmers rather than pulsing in unison.
    private func tileGlow(at date: Date, index: Int) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / 4.8 + Double(index) * 0.18
        let phase = cycles - floor(cycles)
        return 0.55 + 0.45 * (0.5 - 0.5 * cos(phase * 2 * Double.pi))
    }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LaraL10n.text(en: "Dock Capacity", es: "Capacidad del Dock"))
                .font(.headline)

            Picker(
                LaraL10n.text(en: "Dock Capacity", es: "Capacidad del Dock"),
                selection: $selectedCapacity
            ) {
                ForEach(capacities, id: \.self) { capacity in
                    Text("\(capacity)").tag(capacity)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                Text(capacityLabel)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.interpolate)
                Spacer(minLength: 0)
                if selectedCapacity == 4 {
                    ThinBadge(text: LaraL10n.text(en: "Apple default", es: "Original de Apple"))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: selectedCapacity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(LaraL10n.text(en: "Add apps after applying", es: "Añade apps después de aplicar"))
                    .font(.subheadline.weight(.semibold))
                Text(LaraL10n.text(
                    en: "Eagle creates the extra Dock spaces. Return to the Home Screen, then drag apps into them. A respring or reboot returns the standard layout.",
                    es: "Eagle crea los espacios adicionales. Vuelve a la pantalla de inicio y arrastra apps al Dock. Un respring o reinicio devuelve el diseño estándar."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var applyButton: some View {
        Button(action: applySelectedCapacity) {
            HStack(spacing: 9) {
                Image(systemName: selectedCapacity == 4
                      ? "arrow.counterclockwise"
                      : "checkmark.circle.fill")
                Text(selectedCapacity == 4
                     ? LaraL10n.text(en: "Restore Standard Dock", es: "Restaurar Dock estándar")
                     : LaraL10n.text(en: "Apply \(selectedCapacity)-Icon Dock", es: "Aplicar Dock de \(selectedCapacity) iconos"))
            }
            .font(.headline)
            .foregroundStyle(EagleVisualTheme.actionText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                EagleVisualTheme.actionFill,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .shadow(color: Color.primary.opacity(0.12), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(EagleApplyButtonStyle(fill: nil, busy: isApplying))
        .disabled(isApplying)
    }

    private var capacityLabel: String {
        switch selectedCapacity {
        case 4:
            return LaraL10n.text(en: "Standard spacing", es: "Espaciado estándar")
        case 5:
            return LaraL10n.text(en: "Balanced", es: "Equilibrado")
        default:
            return LaraL10n.text(en: "Compact", es: "Compacto")
        }
    }

    private var capacityDescription: String {
        switch selectedCapacity {
        case 4:
            return LaraL10n.text(en: "Restore the familiar four-icon layout.", es: "Restaura el diseño familiar de cuatro iconos.")
        case 5:
            return LaraL10n.text(en: "One useful extra space without feeling crowded.", es: "Un espacio adicional sin que se sienta apretado.")
        default:
            return LaraL10n.text(en: "Maximum useful space on an iPhone Dock.", es: "El máximo espacio útil en el Dock del iPhone.")
        }
    }

    private func previewColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .indigo, .orange, .purple, .pink]
        return colors[index % colors.count]
    }

    private func previewSymbol(for index: Int) -> String {
        let symbols = ["phone.fill", "safari.fill", "message.fill", "music.note", "camera.fill", "envelope.fill"]
        return symbols[index % symbols.count]
    }

    private func applySelectedCapacity() {
        guard !isApplying else { return }
        guard UIApplication.shared.applicationState == .active,
              !mgr.dsrunning, !mgr.rcrunning,
              !mgr.rcSafetyLocked else {
            finishWithError(mgr.rcLastError ?? LaraL10n.text(
                en: "Finish the current operation before changing the Dock.",
                es: "Termina la operación actual antes de cambiar el Dock."
            ))
            return
        }
        guard capacities.contains(selectedCapacity) else {
            finishWithError(LaraL10n.text(
                en: "Choose 4, 5, or 6 Dock icons.",
                es: "Elige 4, 5 o 6 iconos para el Dock."
            ))
            return
        }
        let capacity = selectedCapacity
        isApplying = true

        let applyWithSession = {
            guard let process = self.mgr.sbProc else {
                self.finishWithError(LaraL10n.text(
                    en: "Eagle connected to SpringBoard but did not receive a live session.",
                    es: "Eagle se conectó a SpringBoard, pero no recibió una sesión activa."
                ))
                return
            }

            let operationLabel = "Dock capacity \(UUID().uuidString)"
            guard self.mgr.beginExclusiveRemoteCall(label: operationLabel, expectedSession: process) else {
                self.finishWithError(self.mgr.rcLastError ?? LaraL10n.text(
                    en: "The Dock session is busy or unavailable.",
                    es: "La sesión del Dock está ocupada o no está disponible."
                ))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let capacityResult = set_dock_icon_count(process, Int32(capacity))
                let healthy = process.isHealthy && !process.lastCallTimedOut
                DispatchQueue.main.async {
                    if !healthy {
                        self.mgr.quarantineRemoteCall(reason: "Dock capacity session failed verification")
                    }
                    self.mgr.endExclusiveRemoteCall(label: operationLabel)
                    self.isApplying = false
                    if !healthy {
                        self.alert = EagleDockAlert(message: LaraL10n.text(
                            en: "The Dock update could not be verified. Fully close and reopen Eagle before another operation.",
                            es: "No se pudo verificar el cambio del Dock. Cierra Eagle completamente y vuelve a abrirlo antes de otra operación."
                        ))
                    } else if capacityResult == 0 {
                        self.alert = EagleDockAlert(message: LaraL10n.text(
                            en: "The Dock now accepts \(capacity) icons. Return to the Home Screen and drag apps into the new spaces.",
                            es: "El Dock ahora acepta \(capacity) iconos. Vuelve a la pantalla de inicio y arrastra apps a los espacios nuevos."
                        ))
                    } else {
                        self.alert = EagleDockAlert(message: self.message(forResult: capacityResult))
                    }
                }
            }
        }

        if mgr.rcready, mgr.sbProc != nil {
            applyWithSession()
            return
        }

        guard mgr.dsready else {
            finishWithError(LaraL10n.text(
                en: "Complete Eagle setup before changing the Dock.",
                es: "Completa la preparación de Eagle antes de cambiar el Dock."
            ))
            return
        }

        mgr.rcinit(process: "SpringBoard") { success in
            if success {
                applyWithSession()
            } else {
                let detail = self.mgr.rcLastError?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.finishWithError(detail?.isEmpty == false
                    ? detail!
                    : LaraL10n.text(
                        en: "Eagle could not start the live SpringBoard session.",
                        es: "Eagle no pudo iniciar la sesión en vivo con SpringBoard."
                    ))
            }
        }
    }

    private func finishWithError(_ message: String) {
        DispatchQueue.main.async {
            self.isApplying = false
            self.alert = EagleDockAlert(message: message)
        }
    }

    private func message(forResult result: Int32) -> String {
        switch result {
        case -2:
            return LaraL10n.text(
                en: "SpringBoard did not expose its icon controller.",
                es: "SpringBoard no mostró su controlador de iconos."
            )
        case -3:
            return LaraL10n.text(
                en: "Eagle could not find the active Dock. Unlock the iPhone, visit the Home Screen once, and try again.",
                es: "Eagle no encontró el Dock activo. Desbloquea el iPhone, visita la pantalla de inicio una vez e inténtalo de nuevo."
            )
        case -5:
            return LaraL10n.text(
                en: "SpringBoard could not confirm the Dock update.",
                es: "SpringBoard no pudo confirmar el cambio del Dock."
            )
        default:
            return LaraL10n.text(
                en: "The Dock was found, but iOS did not accept the new capacity.",
                es: "Se encontró el Dock, pero iOS no aceptó la nueva capacidad."
            )
        }
    }

}

/// Slim, quiet capsule for a single-word status ("Apple default").
private struct ThinBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

/// Gentle press feedback for the primary Dock action: a small scale so the
/// button feels responsive under the finger without any layout change.
private struct DockPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
