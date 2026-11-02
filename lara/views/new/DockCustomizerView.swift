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

    private let capacities = [4, 5, 6]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dockPreview
                capacityPicker
                Label(
                    LaraL10n.text(
                        en: "After applying, drag apps into the new spaces. A respring returns the standard Dock.",
                        es: "Después de aplicar, arrastra apps a los espacios nuevos. Un respring devuelve el Dock estándar."
                    ),
                    systemImage: "hand.draw"
                )
                .font(.footnote)
                .opacity(0.7)
                .eagleBackdropText()
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        // Apply stays fixed at the bottom, in reach of the thumb.
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

    /// The bottom of a Home Screen: two quiet rows of apps, the page dots and the Dock holding the
    /// chosen number of apps, which rearrange as the choice changes.
    private var dockPreview: some View {
        let count = EagleStoredThemeValues.dockPreviewCapacity(selectedCapacity)
        let icon: CGFloat = count >= 6 ? 42 : (count == 5 ? 48 : 56)
        let spacing: CGFloat = count >= 6 ? 7 : (count == 5 ? 10 : 18)

        return VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 16) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 54, height: 54)
                }
            }
            .padding(.horizontal, 10)

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { page in
                    Circle()
                        .fill(Color.white.opacity(page == 0 ? 0.85 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 4)

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: icon * 0.225, style: .continuous)
                        .fill(previewColor(for: index).gradient)
                        .frame(width: icon, height: icon)
                        .overlay {
                            Image(systemName: previewSymbol(for: index))
                                .font(.system(size: icon * 0.4, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background {
                if !hideDockBackground {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: count)
        }
        .padding(12)
        .padding(.top, 14)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LaraL10n.text(
            en: "Dock preview with \(count) apps",
            es: "Vista previa del Dock con \(count) apps"
        ))
    }

    /// Three large choices, each with a miniature of its Dock.
    private var capacityPicker: some View {
        HStack(spacing: 10) {
            ForEach(capacities, id: \.self) { capacity in
                let selected = capacity == selectedCapacity
                Button {
                    guard !selected else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedCapacity = capacity
                    }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 2.5) {
                            ForEach(0..<capacity, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .opacity(0.55)
                        Text("\(capacity)")
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                        Text(capacityLabel(capacity))
                            .font(.caption.weight(.semibold))
                            .opacity(0.75)
                    }
                    .foregroundStyle(selected ? EagleVisualTheme.actionText : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        selected ? EagleVisualTheme.actionFill : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.primary.opacity(selected ? 0 : 0.06), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(EaglePressableStyle())
                .accessibilityLabel("\(capacity) · \(capacityLabel(capacity))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var applyButton: some View {
        Button(action: applySelectedCapacity) {
            Text(selectedCapacity == 4
                 ? LaraL10n.text(en: "Restore Standard Dock", es: "Restaurar Dock estándar")
                 : LaraL10n.text(en: "Apply \(selectedCapacity)-Icon Dock", es: "Aplicar Dock de \(selectedCapacity) iconos"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EagleApplyButtonStyle(busy: isApplying))
        .disabled(isApplying)
    }

    private func capacityLabel(_ capacity: Int) -> String {
        switch capacity {
        case 4:
            return LaraL10n.text(en: "Original", es: "Original")
        case 5:
            return LaraL10n.text(en: "Balanced", es: "Equilibrado")
        default:
            return LaraL10n.text(en: "Compact", es: "Compacto")
        }
    }

    private func previewColor(for index: Int) -> Color {
        let colors: [Color] = [.green, .blue, .indigo, .orange, .pink, .teal]
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
