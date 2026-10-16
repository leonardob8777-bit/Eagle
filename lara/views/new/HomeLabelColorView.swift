import SwiftUI
import UIKit
import Darwin

private struct HomeLabelColorNotice: Identifiable {
    let id = UUID()
    let message: String
}

private struct HomeLabelColorPreset: Identifiable {
    let id: String
    let englishName: String
    let spanishName: String
    let color: Color

    var title: String {
        LaraL10n.text(en: englishName, es: spanishName)
    }

    static let all: [HomeLabelColorPreset] = [
        .init(id: "white", englishName: "White", spanishName: "Blanco", color: .white),
        .init(id: "black", englishName: "Black", spanishName: "Negro", color: .black),
        .init(id: "red", englishName: "Red", spanishName: "Rojo", color: .red),
        .init(id: "blue", englishName: "Blue", spanishName: "Azul", color: .blue),
        .init(id: "green", englishName: "Green", spanishName: "Verde", color: .green),
        .init(id: "yellow", englishName: "Yellow", spanishName: "Amarillo", color: .yellow),
        .init(id: "orange", englishName: "Orange", spanishName: "Naranja", color: .orange),
        .init(id: "purple", englishName: "Purple", spanishName: "Morado", color: .purple),
    ]
}

private enum HomeLabelColorDiagnostics {
    static func log(_ stage: String, _ detail: String = "") {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let suffix = detail.isEmpty ? "" : " \(detail)"
        globallogger.log(
            "[\(formatter.string(from: Date()))] " +
            "(eagle.home-label-color.apply) stage=\(stage)\(suffix)"
        )
    }
}

@MainActor
private enum HomeLabelColorApplyGate {
    private static var operationInFlight = false

    static func begin() -> Bool {
        guard !operationInFlight else { return false }
        operationInFlight = true
        return true
    }

    static func end() {
        operationInFlight = false
    }
}

private struct HomeLabelColorPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15),
                value: configuration.isPressed
            )
    }
}

struct HomeLabelColorView: View {
    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(EagleReleaseChannel.storageKey) private var releaseChannelRaw =
        EagleReleaseChannel.stable.rawValue
    @AppStorage("eagle.homeLabelColor.red") private var red = 1.0
    @AppStorage("eagle.homeLabelColor.green") private var green = 1.0
    @AppStorage("eagle.homeLabelColor.blue") private var blue = 1.0
    @AppStorage("eagle.homeLabelColor.activeSpringBoardPID")
    private var activeSpringBoardPID = 0
    @AppStorage("eagle.homeLabelColor.activePageCount")
    private var activePageCount = 0
    @AppStorage("eagle.homeLabelColor.cleanupRequired")
    private var cleanupRequired = false

    @State private var isApplying = false
    @State private var operationStage = ""
    @State private var notice: HomeLabelColorNotice?
    @State private var lastResult: Int32?

    private var selectedColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    private var selectedColorBinding: Binding<Color> {
        Binding(
            get: { selectedColor },
            set: { store($0) }
        )
    }

    private var selectedRGB: (red: Int32, green: Int32, blue: Int32) {
        let resolved = UIColor(selectedColor).resolvedColor(with: .current)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return (255, 255, 255)
        }
        return (
            Int32((r * 255).rounded()),
            Int32((g * 255).rounded()),
            Int32((b * 255).rounded())
        )
    }

    private func matchesSelection(_ preset: HomeLabelColorPreset) -> Bool {
        let resolved = UIColor(preset.color).resolvedColor(with: .current)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        let target = selectedRGB
        return Int32((r * 255).rounded()) == target.red
            && Int32((g * 255).rounded()) == target.green
            && Int32((b * 255).rounded()) == target.blue
    }

    private var releaseChannel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: releaseChannelRaw)
    }

    private var policyAllowsApply: Bool {
        EagleFeaturePolicy.allows(.homeLabelColor, channel: releaseChannel)
    }

    private var supportedDevice: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return devicemachine() == "iPhone17,1" &&
            version.majorVersion == 18 &&
            version.minorVersion == 6 &&
            version.patchVersion == 2
    }

    private var hasRecordedEffect: Bool {
        activePageCount > 0 || cleanupRequired
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                previewCard
                colorCard
                scopeCard
                diagnosticsCard
            }
            .padding(20)
        }
        // Apply stays fixed at the bottom, in reach of the thumb; Prepare takes its place until ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: mgr.dsready) {
                applyButton
                restoreButton
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "App Name Color", es: "Color de nombres"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isApplying)
        .eagleNotice(item: $notice, title: LaraL10n.text(en: "App Name Color", es: "Color de nombres")) { $0.message }
        .overlay {
            if isApplying {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 12) {
                        EagleRainbowSpinner(size: 28)
                        Text(operationStage)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
                .transition(.eagleWorking)
            }
        }
        .onAppear(perform: reconcileState)
        .onChange(of: scenePhase) { phase in
            if phase == .active { reconcileState() }
        }
    }

    private var previewCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(LaraL10n.text(
                    en: "Give app names your color",
                    es: "Dale tu color a los nombres"
                ))
                .font(.headline)
                Text(LaraL10n.text(
                    en: "Solid color only — no glow, outline, or animation.",
                    es: "Solo color sólido: sin brillo, borde ni animación."
                ))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 24) {
                previewApp(icon: "message.fill", name: "Messages", tint: .green)
                previewApp(icon: "safari.fill", name: "Safari", tint: .blue)
                previewApp(icon: "music.note", name: "Music", tint: .pink)
            }
            .accessibilityHidden(true)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.25),
                value: selectedColor
            )

            Label(
                cleanupRequired
                    ? LaraL10n.text(en: "Restore required", es: "Se requiere restaurar")
                    : (activePageCount > 0
                        ? LaraL10n.text(
                            en: "\(activePageCount) Home page\(activePageCount == 1 ? "" : "s") recorded",
                            es: "\(activePageCount) página\(activePageCount == 1 ? "" : "s") registrada\(activePageCount == 1 ? "" : "s")"
                        )
                        : LaraL10n.text(en: "System colors unchanged", es: "Colores del sistema sin cambios")),
                systemImage: cleanupRequired
                    ? "exclamationmark.triangle.fill"
                    : (activePageCount > 0 ? "checkmark.circle.fill" : "circle")
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(cleanupRequired ? Color.orange : (activePageCount > 0 ? Color.green : Color.white.opacity(0.7)))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        // A solid black base under the gradient: it looks exactly as before on black, and the backdrop
        // no longer shows through the card's lighter corner.
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.black.opacity(0.94), Color.gray.opacity(0.26)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .foregroundStyle(.white)
    }

    private func previewApp(icon: String, name: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selectedColor)
                .lineLimit(1)
        }
        .frame(width: 72)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LaraL10n.text(en: "Text color", es: "Color del texto"))
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 10)],
                spacing: 10
            ) {
                ForEach(HomeLabelColorPreset.all) { preset in
                    Button {
                        store(preset.color)
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.22), lineWidth: 1)
                            }
                            .frame(width: 52, height: 52)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                                    .opacity(matchesSelection(preset) ? 1 : 0)
                            }
                    }
                    .buttonStyle(HomeLabelColorPressStyle())
                    .disabled(isApplying)
                    .accessibilityLabel(preset.title)
                    .accessibilityAddTraits(matchesSelection(preset) ? .isSelected : [])
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.18),
                        value: matchesSelection(preset)
                    )
                }
            }

            Divider()

            ColorPicker(
                LaraL10n.text(en: "Choose any color", es: "Elegir cualquier color"),
                selection: selectedColorBinding,
                supportsOpacity: false
            )
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
            .disabled(isApplying)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                LaraL10n.text(en: "Current Home page", es: "Página de inicio actual"),
                systemImage: "textformat"
            )
            // Keeps the "Aa" symbol in every language (it is redrawn as 格式 in Chinese).
            .environment(\.locale, Locale(identifier: "en"))
            .font(.headline)
            .foregroundStyle(.indigo)

            Text(LaraL10n.text(
                en: "Visit the Home page you want, reopen Eagle, then apply. Only the names beneath app icons on that root page are recolored. Dock, folders, App Library, Dynamic Island, and Prepare are excluded.",
                es: "Visita la página de inicio deseada, vuelve a abrir Eagle y aplica. Solo cambian los nombres bajo los iconos de apps de esa página raíz. Dock, carpetas, Biblioteca, Dynamic Island y Preparar quedan excluidos."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text(LaraL10n.text(
                en: "SpringBoard may rebuild labels after changing pages, rotating, or respringing. Restore removes only Eagle's colored copy; the original system label is not modified.",
                es: "SpringBoard puede reconstruir los nombres al cambiar de página, rotar o hacer respring. Restaurar elimina solo la copia coloreada de Eagle; el nombre original del sistema no se modifica."
            ))
            .font(.caption)
            .foregroundStyle(.orange)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var applyButton: some View {
        Button {
            run(enabled: true)
        } label: {
            Label(
                LaraL10n.text(en: "Apply to Current Page", es: "Aplicar a la página actual"),
                systemImage: "paintpalette.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(EagleApplyButtonStyle(busy: isApplying))
        .disabled(
            isApplying || !mgr.dsready || mgr.rcSafetyLocked ||
            !supportedDevice || !policyAllowsApply
        )
    }

    private var restoreButton: some View {
        Button(role: .destructive) {
            run(enabled: false)
        } label: {
            Label(
                LaraL10n.text(en: "Restore System Color", es: "Restaurar color del sistema"),
                systemImage: "arrow.uturn.backward.circle.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .disabled(isApplying || !hasRecordedEffect || !mgr.dsready || mgr.rcSafetyLocked)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                LaraL10n.text(en: "Compatibility", es: "Compatibilidad"),
                systemImage: "checkmark.shield"
            )
            .font(.headline)

            Text(
                supportedDevice
                    ? LaraL10n.text(
                        en: "Initial verified target: iPhone 16 Pro · iOS 18.6.2.",
                        es: "Objetivo verificado inicial: iPhone 16 Pro · iOS 18.6.2."
                    )
                    : LaraL10n.text(
                        en: "No system call will be sent on an unverified device/build.",
                        es: "No se enviará ninguna llamada en un dispositivo o versión sin verificar."
                    )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if !policyAllowsApply {
                Text(LaraL10n.text(
                    en: "Switch the feature channel to Advanced to apply. Restore remains available.",
                    es: "Cambia el canal de funciones a Avanzado para aplicar. Restaurar sigue disponible."
                ))
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let lastResult {
                Text("Native result: \(lastResult)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            NavigationLink {
                LogsView(logger: globallogger)
            } label: {
                Label(
                    LaraL10n.text(en: "Open Eagle Logs", es: "Abrir registros de Eagle"),
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func store(_ color: Color) {
        let resolved = UIColor(color).resolvedColor(with: .current)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        red = Double(r)
        green = Double(g)
        blue = Double(b)
    }

    private func reconcileState() {
        guard hasRecordedEffect else { return }
        let currentPID = "SpringBoard".withCString { find_process_pid($0) }
        guard currentPID > 0 else {
            cleanupRequired = true
            return
        }
        if activeSpringBoardPID > 0, currentPID != activeSpringBoardPID {
            activeSpringBoardPID = 0
            activePageCount = 0
            cleanupRequired = false
        }
    }

    private func run(enabled: Bool) {
        let operationRGB = selectedRGB
        HomeLabelColorDiagnostics.log(
            "request",
            "action=\(enabled ? "apply" : "restore") " +
            "rgb=\(operationRGB.red),\(operationRGB.green),\(operationRGB.blue) " +
            "device=\(devicemachine()) channel=\(releaseChannel.rawValue)"
        )

        guard !isApplying, HomeLabelColorApplyGate.begin() else {
            notice = HomeLabelColorNotice(message: LaraL10n.text(
                en: "App Name Color is still finishing the previous operation.",
                es: "Color de nombres todavía está terminando la operación anterior."
            ))
            return
        }

        func finishBeforeCall(_ message: String) {
            HomeLabelColorApplyGate.end()
            isApplying = false
            notice = HomeLabelColorNotice(message: message)
        }

        guard !enabled || policyAllowsApply else {
            finishBeforeCall(LaraL10n.text(
                en: "Select the Advanced feature channel before applying.",
                es: "Selecciona el canal Avanzado antes de aplicar."
            ))
            return
        }
        guard supportedDevice else {
            finishBeforeCall(LaraL10n.text(
                en: "No system call was sent. This test accepts only iPhone 16 Pro on iOS 18.6.2.",
                es: "No se envió ninguna llamada. Esta prueba acepta solo iPhone 16 Pro con iOS 18.6.2."
            ))
            return
        }
        guard !isdebugged() else {
            finishBeforeCall(LaraL10n.text(
                en: "Stop the Xcode run and open Eagle manually from the Home Screen before applying.",
                es: "Detén la ejecución de Xcode y abre Eagle manualmente desde Inicio antes de aplicar."
            ))
            return
        }
        guard mgr.dsready, !mgr.rcSafetyLocked else {
            finishBeforeCall(LaraL10n.text(
                en: "Prepare Eagle access first, or fully reopen Eagle if the safety lock is active.",
                es: "Prepara primero el acceso de Eagle o vuelve a abrir la app si el bloqueo de seguridad está activo."
            ))
            return
        }

        isApplying = true
        operationStage = LaraL10n.text(
            en: "Preparing the current Home page…",
            es: "Preparando la página actual…"
        )

        mgr.prepareFreshRemoteCall(process: "SpringBoard", timeout: 20) { process, error in
            guard let process else {
                let reason = error ?? "Fresh SpringBoard session unavailable"
                let preflight =
                    reason.localizedCaseInsensitiveContains("access is not ready") ||
                    reason.localizedCaseInsensitiveContains("still running") ||
                    reason.localizedCaseInsensitiveContains("safety locked")
                if !preflight {
                    mgr.quarantineRemoteCall(reason: "Home label color session failed: \(reason)")
                }
                finishBeforeCall(reason)
                return
            }

            let targetPID = process.pid
            let currentPID = "SpringBoard".withCString { find_process_pid($0) }
            guard targetPID > 0,
                  currentPID == targetPID,
                  process.creatingExtraThread else {
                let reason = "Home label color session identity failed " +
                    "(target \(targetPID), current \(currentPID), isolated \(process.creatingExtraThread))"
                mgr.quarantineRemoteCall(reason: reason)
                finishBeforeCall(reason)
                return
            }

            let label = "Home Label Color \(UUID().uuidString)"
            guard mgr.beginExclusiveRemoteCall(label: label, expectedSession: process) else {
                finishBeforeCall(LaraL10n.text(
                    en: "Another protected operation is active. Wait and try again.",
                    es: "Hay otra operación protegida activa. Espera e inténtalo de nuevo."
                ))
                return
            }

            operationStage = enabled
                ? LaraL10n.text(en: "Applying and verifying the text color…", es: "Aplicando y verificando el color del texto…")
                : LaraL10n.text(en: "Restoring the automatic system color…", es: "Restaurando el color automático del sistema…")

            var nativeFinished = false
            var deadlineExceeded = false
            let deadlineWork = DispatchWorkItem {
                guard !nativeFinished else { return }
                deadlineExceeded = true
                cleanupRequired = true
                mgr.quarantineRemoteCall(
                    reason: "Home label color exceeded the 60-second safety deadline"
                )
                operationStage = LaraL10n.text(
                    en: "Waiting safely · no automatic retry…",
                    es: "Esperando de forma segura · sin reintento automático…"
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: deadlineWork)

            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool {
                    eagle_set_home_label_color(
                        process,
                        operationRGB.red,
                        operationRGB.green,
                        operationRGB.blue,
                        enabled ? 1 : 0
                    )
                }
                let healthy = process.isHealthy
                let timedOut = process.lastCallTimedOut
                let processError = process.lastError
                let pidAfter = "SpringBoard".withCString { find_process_pid($0) }

                DispatchQueue.main.async {
                    nativeFinished = true
                    deadlineWork.cancel()
                    mgr.endExclusiveRemoteCall(label: label)
                    HomeLabelColorApplyGate.end()
                    isApplying = false
                    lastResult = result

                    HomeLabelColorDiagnostics.log(
                        "native.end",
                        "result=\(result) target=\(targetPID) current=\(pidAfter) " +
                        "healthy=\(healthy) timeout=\(timedOut) error=\(processError ?? "none")"
                    )

                    if deadlineExceeded {
                        notice = HomeLabelColorNotice(message: LaraL10n.text(
                            en: "The safety deadline expired. Fully close and reopen Eagle before using Restore on the same page.",
                            es: "Venció el límite de seguridad. Cierra y abre Eagle antes de usar Restaurar en la misma página."
                        ))
                        return
                    }

                    let transportVerified = healthy && !timedOut && pidAfter == targetPID
                    if !transportVerified || result == -7 || result == -12 {
                        cleanupRequired = true
                        mgr.quarantineRemoteCall(
                            reason: "Home label color unverified transport/result \(result)"
                        )
                        notice = HomeLabelColorNotice(message: LaraL10n.text(
                            en: "The protected result could not be verified. Fully close Eagle, reopen it, return to the same page, and use Restore.",
                            es: "No se pudo verificar el resultado protegido. Cierra Eagle, vuelve a abrirla, regresa a la misma página y usa Restaurar."
                        ))
                        return
                    }

                    if enabled, result > 0 {
                        activePageCount = min(32, max(activePageCount, 0) + 1)
                        activeSpringBoardPID = Int(targetPID)
                        cleanupRequired = false
                        notice = HomeLabelColorNotice(message: LaraL10n.text(
                            en: "Applied and verified the selected color on \(result) app name\(result == 1 ? "" : "s") on this page. Dock, folders, App Library, Island, and Prepare were not changed.",
                            es: "Se aplicó y verificó el color elegido en \(result) nombre\(result == 1 ? "" : "s") de apps de esta página. Dock, carpetas, Biblioteca, Isla y Preparar no cambiaron."
                        ))
                    } else if !enabled, result > 0 {
                        activePageCount = max(0, activePageCount - 1)
                        if activePageCount == 0 { activeSpringBoardPID = 0 }
                        cleanupRequired = false
                        notice = HomeLabelColorNotice(message: LaraL10n.text(
                            en: "Restored the automatic system color for \(result) app name\(result == 1 ? "" : "s") on this page.",
                            es: "Se restauró el color automático del sistema en \(result) nombre\(result == 1 ? "" : "s") de apps de esta página."
                        ))
                    } else {
                        notice = HomeLabelColorNotice(
                            message: message(for: result, restoring: !enabled)
                        )
                    }
                }
            }
        }
    }

    private func message(for result: Int32, restoring: Bool) -> String {
        switch result {
        case -2:
            return LaraL10n.text(
                en: "SpringBoard did not expose a current root Home page with visible app names. Visit the desired page, reopen Eagle, and try again.",
                es: "SpringBoard no expuso una página raíz actual con nombres visibles. Visita la página deseada, vuelve a abrir Eagle e inténtalo otra vez."
            )
        case -3:
            return LaraL10n.text(en: "The selected color is invalid.", es: "El color seleccionado no es válido.")
        case -4:
            return LaraL10n.text(en: "The isolated protected thread was unavailable.", es: "El hilo protegido aislado no estaba disponible.")
        case -5:
            return LaraL10n.text(en: "This device/build is outside the verified allowlist.", es: "Este dispositivo o versión no está en la lista verificada.")
        case -6:
            return LaraL10n.text(en: "SpringBoard did not expose the complete label-image renderer.", es: "SpringBoard no expuso el renderizador completo de imágenes de nombres.")
        case -8:
            return LaraL10n.text(en: "The current page hierarchy exceeded the safe limit.", es: "La jerarquía de la página superó el límite seguro.")
        case -9:
            return LaraL10n.text(en: "This page already has Eagle-colored app names. Use Restore before applying another color.", es: "Esta página ya tiene nombres coloreados por Eagle. Usa Restaurar antes de aplicar otro color.")
        case -10:
            return LaraL10n.text(
                en: "The color did not verify and the original system labels were restored.",
                es: "El color no se verificó y se restauraron los nombres originales del sistema."
            )
        case -13:
            return LaraL10n.text(en: "The page exceeded the safe call budget before changing text.", es: "La página superó el presupuesto seguro antes de cambiar el texto.")
        case -14:
            return LaraL10n.text(
                en: "iOS did not preserve the selected color in every copied label parameter. Nothing was attached or marked active.",
                es: "iOS no conservó el color elegido en todos los parámetros copiados. No se adjuntó ni marcó nada como activo."
            )
        default:
            return LaraL10n.text(
                en: "App Name Color returned result \(result). \(restoring ? "Restore was not confirmed." : "No active state was recorded.")",
                es: "Color de nombres devolvió \(result). \(restoring ? "No se confirmó la restauración." : "No se registró ningún estado activo.")"
            )
        }
    }
}
