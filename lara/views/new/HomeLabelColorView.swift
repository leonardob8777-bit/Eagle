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
    @State private var showsDetails = false

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
        eagleSupportAssessment().allowsPrepare
    }

    private var hasRecordedEffect: Bool {
        activePageCount > 0 || cleanupRequired
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                previewCard
                colorCard
                detailsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        // Apply stays fixed at the bottom, in reach of the thumb; Prepare takes its place until ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: mgr.dsready) {
                applyButton
                if hasRecordedEffect {
                    restoreButton
                }
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

    /// A Home Screen page: eight apps with their names in the chosen colour, and the recorded state
    /// only when there is one.
    private var previewCard: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
                ForEach(Array(previewApps.enumerated()), id: \.offset) { _, app in
                    previewApp(icon: app.icon, name: app.name, tint: app.tint)
                }
            }
            .accessibilityHidden(true)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.25),
                value: selectedColor
            )

            if hasRecordedEffect {
                Label(
                    cleanupRequired
                        ? LaraL10n.text(en: "Restore required", es: "Se requiere restaurar")
                        : LaraL10n.text(
                            en: "\(activePageCount) Home page\(activePageCount == 1 ? "" : "s") recorded",
                            es: "\(activePageCount) página\(activePageCount == 1 ? "" : "s") registrada\(activePageCount == 1 ? "" : "s")"
                        ),
                    systemImage: cleanupRequired ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(cleanupRequired ? Color.orange : Color.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    private var previewApps: [(icon: String, name: String, tint: Color)] {
        [
            ("message.fill", LaraL10n.text(en: "Messages", es: "Mensajes"), .green),
            ("safari.fill", "Safari", .blue),
            ("music.note", LaraL10n.text(en: "Music", es: "Música"), .pink),
            ("camera.fill", LaraL10n.text(en: "Camera", es: "Cámara"), .gray),
            ("photo.fill", LaraL10n.text(en: "Photos", es: "Fotos"), .orange),
            ("map.fill", LaraL10n.text(en: "Maps", es: "Mapas"), .teal),
            ("cloud.sun.fill", LaraL10n.text(en: "Weather", es: "Tiempo"), .cyan),
            ("gearshape.fill", LaraL10n.text(en: "Settings", es: "Ajustes"), .gray),
        ]
    }

    private func previewApp(icon: String, name: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selectedColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// The eight colours and, as the ninth swatch, any colour at all.
    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LaraL10n.text(en: "Text color", es: "Color del texto"))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                ForEach(HomeLabelColorPreset.all) { preset in
                    Button {
                        store(preset.color)
                    } label: {
                        swatch(preset.color, selected: matchesSelection(preset))
                    }
                    .buttonStyle(HomeLabelColorPressStyle())
                    .disabled(isApplying)
                    .accessibilityLabel(preset.title)
                    .accessibilityAddTraits(matchesSelection(preset) ? .isSelected : [])
                }

                ColorPicker(
                    LaraL10n.text(en: "Choose any color", es: "Elegir cualquier color"),
                    selection: selectedColorBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .scaleEffect(1.25)
                .frame(width: 48, height: 48)
                .disabled(isApplying)
            }

            if !policyAllowsApply {
                Label(
                    LaraL10n.text(
                        en: "Switch the feature channel to Advanced to apply. Restore remains available.",
                        es: "Cambia el canal de funciones a Avanzado para aplicar. Restaurar sigue disponible."
                    ),
                    systemImage: "bolt.fill"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay { Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1) }
            .padding(4)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 2)
                    .opacity(selected ? 1 : 0)
            }
            .frame(width: 48, height: 48)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selected)
    }

    /// What it changes in one line; the rest (limits, compatibility, logs) folded away.
    private var detailsCard: some View {
        DisclosureGroup(isExpanded: $showsDetails) {
            VStack(alignment: .leading, spacing: 10) {
                Text(LaraL10n.text(
                    en: "Visit the Home page you want, reopen Eagle, then apply. Dock, folders, App Library, Dynamic Island, and Prepare are excluded.",
                    es: "Visita la página de inicio deseada, vuelve a abrir Eagle y aplica. Dock, carpetas, Biblioteca, Dynamic Island y Preparar quedan excluidos."
                ))
                Text(LaraL10n.text(
                    en: "SpringBoard may rebuild labels after changing pages, rotating, or respringing. Restore removes only Eagle's colored copy; the original system label is not modified.",
                    es: "SpringBoard puede reconstruir los nombres al cambiar de página, rotar o hacer respring. Restaurar elimina solo la copia coloreada de Eagle; el nombre original del sistema no se modifica."
                ))
                Text(supportedDevice
                    ? LaraL10n.text(
                        en: "The access engine supports this device. This effect still needs testing on each device and iOS version.",
                        es: "El motor de acceso admite este dispositivo. Este efecto aún necesita pruebas en cada dispositivo y versión de iOS."
                    )
                    : LaraL10n.text(
                        en: "The access engine does not support this device and iOS version.",
                        es: "El motor de acceso no admite este dispositivo y esta versión de iOS."
                    ))
                if let lastResult {
                    Text(LaraL10n.text(en: "Native result: \(lastResult)", es: "Resultado nativo: \(lastResult)"))
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
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(LaraL10n.text(en: "How it works", es: "Cómo funciona"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(LaraL10n.text(
                    en: "Only the names on the current Home page change.",
                    es: "Solo cambian los nombres de la página de inicio actual."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.secondary)
        .padding(16)
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
            Text(LaraL10n.text(en: "Apply to Current Page", es: "Aplicar a la página actual"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EagleApplyButtonStyle(busy: isApplying))
        .disabled(
            isApplying || !mgr.dsready || mgr.rcSafetyLocked ||
            !supportedDevice || !policyAllowsApply
        )
    }

    private var restoreButton: some View {
        Button {
            run(enabled: false)
        } label: {
            Text(LaraL10n.text(en: "Restore System Color", es: "Restaurar color del sistema"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EagleSecondaryButtonStyle())
        .disabled(isApplying || !mgr.dsready || mgr.rcSafetyLocked)
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
                en: "No system call was sent. The access engine does not support this device and iOS version.",
                es: "No se envió ninguna llamada. El motor de acceso no admite este dispositivo y esta versión de iOS."
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
