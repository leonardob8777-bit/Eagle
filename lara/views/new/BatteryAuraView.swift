import SwiftUI
import UIKit
import Darwin

private struct BatteryAuraNotice: Identifiable {
    let id = UUID()
    let message: String
}

private enum BatteryAuraStyle: Int, CaseIterable, Identifiable {
    case fill = 1
    case full = 2
    case neon = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fill: return LaraL10n.text(en: "Fill", es: "Carga")
        case .full: return LaraL10n.text(en: "Full", es: "Completa")
        case .neon: return LaraL10n.text(en: "Neon", es: "Neón")
        }
    }

    var summary: String {
        switch self {
        case .fill:
            return LaraL10n.text(
                en: "Colors the energy inside the battery while keeping the system outline.",
                es: "Colorea la energía dentro de la batería y conserva el contorno del sistema."
            )
        case .full:
            return LaraL10n.text(
                en: "Colors the fill, outline, and charging bolt while keeping the percentage readable.",
                es: "Colorea la carga, el contorno y el rayo, manteniendo legible el porcentaje."
            )
        case .neon:
            return LaraL10n.text(
                en: "Adds a focused glow around the fully colored battery glyph.",
                es: "Añade un brillo concentrado alrededor del icono completo."
            )
        }
    }
}

private enum BatteryAuraDiagnostics {
    static func log(_ stage: String, _ detail: String = "") {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let suffix = detail.isEmpty ? "" : " \(detail)"
        globallogger.log("[\(formatter.string(from: Date()))] (eagle.battery.apply) stage=\(stage)\(suffix)")
    }
}

@MainActor
private enum BatteryAuraApplyGate {
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

struct BatteryAuraView: View {
    @ObservedObject private var mgr = laramgr.shared
    @AppStorage("eagle.batteryAura.red") private var red = 0.22
    @AppStorage("eagle.batteryAura.green") private var green = 0.92
    @AppStorage("eagle.batteryAura.blue") private var blue = 0.48
    @AppStorage("eagle.batteryAura.style") private var selectedStyleRaw = BatteryAuraStyle.neon.rawValue
    @AppStorage("eagle.batteryAura.activeStyle") private var activeStyleRaw = 0

    @State private var isApplying = false
    @State private var notice: BatteryAuraNotice?

    private var selectedStyle: BatteryAuraStyle {
        get { BatteryAuraStyle(rawValue: selectedStyleRaw) ?? .neon }
        nonmutating set { selectedStyleRaw = newValue.rawValue }
    }

    private var auraColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    private var supportedOS: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major == 17 || major == 18
    }

    private var auraColorBinding: Binding<Color> {
        Binding(
            get: { auraColor },
            set: { color in
                let resolved = UIColor(color)
                var nextRed: CGFloat = 0
                var nextGreen: CGFloat = 0
                var nextBlue: CGFloat = 0
                var alpha: CGFloat = 0
                guard resolved.getRed(
                    &nextRed,
                    green: &nextGreen,
                    blue: &nextBlue,
                    alpha: &alpha
                ) else { return }
                red = Double(nextRed)
                green = Double(nextGreen)
                blue = Double(nextBlue)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                previewCard
                controlsCard
                scopeCard
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
        .navigationTitle("Battery Aura")
        .navigationBarTitleDisplayMode(.inline)
        .eagleNotice(item: $notice, title: "Battery Aura") { $0.message }
        .overlay {
            if isApplying {
                ZStack {
                    Color.black.opacity(0.14).ignoresSafeArea()
                    VStack(spacing: 12) {
                        EagleRainbowSpinner(size: 28)
                        Text(LaraL10n.text(
                            en: "Coloring the system battery…",
                            es: "Coloreando la batería del sistema…"
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

    private var previewCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text(LaraL10n.text(en: "Make power feel alive", es: "Haz que la energía cobre vida"))
                    .font(.title2.bold())
                Text(LaraL10n.text(
                    en: "A verified color treatment for the system battery.",
                    es: "Un tratamiento de color verificado para la batería del sistema."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.055, blue: 0.09),
                        auraColor.opacity(0.20),
                        Color(red: 0.025, green: 0.03, blue: 0.055),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack {
                    Text("9:41")
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        batteryGlyph
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 18)
            }
            .frame(height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 7) {
                Circle()
                    .fill(activeStyleRaw == 0 ? Color.secondary.opacity(0.5) : Color.green)
                    .frame(width: 8, height: 8)
                Text(activeStyleRaw == 0
                     ? LaraL10n.text(en: "No verified Battery Aura", es: "Sin Battery Aura verificada")
                     : LaraL10n.text(en: "Last apply was verified", es: "La última aplicación fue verificada"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var batteryGlyph: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        selectedStyle == .fill ? Color.white.opacity(0.86) : auraColor,
                        lineWidth: 1.8
                    )
                    .frame(width: 29, height: 14)
                RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                    .fill(auraColor)
                    .frame(width: 20, height: 9)
                    .padding(.leading, 2.5)
                Text("72")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedStyle == .fill ? Color.white : Color.black.opacity(0.76))
                    .frame(width: 29)
            }
            Capsule()
                .fill(selectedStyle == .fill ? Color.white.opacity(0.8) : auraColor)
                .frame(width: 2.5, height: 6)
        }
        .shadow(
            color: selectedStyle == .neon ? auraColor.opacity(0.98) : .clear,
            radius: selectedStyle == .neon ? 7 : 0
        )
        .scaleEffect(1.12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LaraL10n.text(en: "Battery Aura preview", es: "Vista previa de Battery Aura"))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LaraL10n.text(en: "Your Battery", es: "Tu batería"))
                .font(.headline)

            Picker(
                LaraL10n.text(en: "Style", es: "Estilo"),
                selection: Binding(
                    get: { selectedStyle },
                    set: { selectedStyle = $0 }
                )
            ) {
                ForEach(BatteryAuraStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedStyle.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            ColorPicker(
                LaraL10n.text(en: "Battery color", es: "Color de batería"),
                selection: auraColorBinding,
                supportsOpacity: false
            )
            .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                ForEach(presets, id: \.name) { preset in
                    Button {
                        red = preset.red
                        green = preset.green
                        blue = preset.blue
                    } label: {
                        Circle()
                            .fill(Color(red: preset.red, green: preset.green, blue: preset.blue))
                            .frame(width: 32, height: 32)
                            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
                            .shadow(
                                color: Color(red: preset.red, green: preset.green, blue: preset.blue).opacity(0.48),
                                radius: 5
                            )
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .accessibilityLabel(preset.name)
                }
                Spacer()
            }
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

    private var scopeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: supportedOS ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(supportedOS ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(supportedOS
                     ? LaraL10n.text(en: "Bounded system change", es: "Cambio limitado del sistema")
                     : LaraL10n.text(en: "Version not verified", es: "Versión no verificada"))
                    .font(.subheadline.weight(.semibold))
                Text(supportedOS
                     ? LaraL10n.text(
                        en: "Eagle changes only battery views already exposed by SpringBoard on iOS 17 or 18. Some third-party apps redraw their own status bar, and a respring or recreated system view may end the effect.",
                        es: "Eagle cambia únicamente las vistas de batería que SpringBoard ya expone en iOS 17 o 18. Algunas apps redibujan su propia barra de estado, y un respring o una vista recreada puede terminar el efecto."
                     )
                     : LaraL10n.text(
                        en: "Battery Aura is currently limited to iOS 17 and 18 while its private battery surface is verified.",
                        es: "Battery Aura está limitada por ahora a iOS 17 y 18 mientras se verifica su superficie privada."
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
        Button {
            apply(style: selectedStyle.rawValue)
        } label: {
            Label(
                LaraL10n.text(en: "Apply Battery Aura", es: "Aplicar Battery Aura"),
                systemImage: "bolt.fill"
            )
            .font(.headline)
            .foregroundStyle(EagleVisualTheme.actionText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(EagleVisualTheme.actionFill)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(EagleApplyButtonStyle(fill: nil, busy: isApplying))
        .disabled(isApplying || !supportedOS)
    }

    private var restoreButton: some View {
        Button {
            apply(style: 0)
        } label: {
            Label(
                LaraL10n.text(en: "Restore System Battery", es: "Restaurar batería del sistema"),
                systemImage: "arrow.counterclockwise"
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isApplying || !supportedOS)
    }

    private var presets: [(name: String, red: Double, green: Double, blue: Double)] {
        [
            ("Energy", 0.22, 0.92, 0.48),
            ("Electric", 0.10, 0.78, 1.00),
            ("Hot Pink", 1.00, 0.16, 0.62),
            ("Amber", 1.00, 0.62, 0.12),
            ("Violet", 0.62, 0.25, 1.00),
        ]
    }

    private func apply(style: Int) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        BatteryAuraDiagnostics.log(
            "request",
            "style=\(style) device=\(devicemachine()) ios=\(versionString) " +
            "dsready=\(mgr.dsready) rcrunning=\(mgr.rcrunning) rcready=\(mgr.rcready) session=\(mgr.sbProc != nil)"
        )

        guard !isApplying else {
            BatteryAuraDiagnostics.log("rejected", "reason=already-applying")
            return
        }
        guard supportedOS else {
            finish(
                stage: "rejected.unsupported-os",
                message: LaraL10n.text(
                    en: "Battery Aura is currently verified only on iOS 17 and 18.",
                    es: "Battery Aura está verificada por ahora únicamente en iOS 17 y 18."
                )
            )
            return
        }
        guard !isdebugged() else {
            finish(
                stage: "rejected.debugger",
                message: LaraL10n.text(
                    en: "Stop the Xcode run and open Eagle manually from the Home Screen before changing SpringBoard.",
                    es: "Detén la ejecución en Xcode y abre Eagle manualmente desde la pantalla de inicio antes de modificar SpringBoard."
                )
            )
            return
        }
        guard mgr.dsready else {
            finish(
                stage: "rejected.access",
                message: LaraL10n.text(
                    en: "Prepare Eagle access before changing the system battery.",
                    es: "Prepara el acceso de Eagle antes de cambiar la batería del sistema."
                )
            )
            return
        }
        if mgr.rcrunning, !(mgr.rcready && mgr.sbProc != nil) {
            finish(
                stage: "rejected.session-busy",
                message: LaraL10n.text(
                    en: "Eagle is already preparing a SpringBoard session. Wait for it to finish.",
                    es: "Eagle ya está preparando una sesión de SpringBoard. Espera a que termine."
                )
            )
            return
        }

        guard BatteryAuraApplyGate.begin() else {
            finish(
                stage: "rejected.operation-in-flight",
                message: LaraL10n.text(
                    en: "Battery Aura is still finishing a previous system operation. Keep Eagle open and wait for its result before applying again.",
                    es: "Battery Aura todavía está terminando una operación anterior del sistema. Mantén Eagle abierto y espera el resultado antes de volver a aplicar."
                )
            )
            return
        }

        isApplying = true
        let applyWithSession = {
            guard let process = self.mgr.sbProc else {
                self.finish(
                    stage: "session.invalid",
                    message: LaraL10n.text(
                        en: "Eagle connected to SpringBoard but did not receive a live session.",
                        es: "Eagle se conectó a SpringBoard, pero no recibió una sesión activa."
                    )
                )
                return
            }

            let targetPID = process.pid
            let probeResult = targetPID > 0 ? Darwin.kill(targetPID, 0) : -1
            let probeError = errno
            guard targetPID > 0, probeResult == 0 || probeError == EPERM else {
                self.finish(
                    stage: "session.stale",
                    message: LaraL10n.text(
                        en: "The SpringBoard session is no longer alive. Reopen Eagle and prepare access again.",
                        es: "La sesión de SpringBoard ya no está activa. Vuelve a abrir Eagle y prepara el acceso otra vez."
                    )
                )
                return
            }

            let redValue = Int32(max(0, min(255, Int((self.red * 255).rounded()))))
            let greenValue = Int32(max(0, min(255, Int((self.green * 255).rounded()))))
            let blueValue = Int32(max(0, min(255, Int((self.blue * 255).rounded()))))
            BatteryAuraDiagnostics.log(
                "session.ready",
                "pid=\(targetPID) isolatedThread=\(process.creatingExtraThread) style=\(style) rgb=\(redValue),\(greenValue),\(blueValue)"
            )

            DispatchQueue.global(qos: .userInitiated).async {
                BatteryAuraDiagnostics.log("native-call.begin", "style=\(style)")
                let result = autoreleasepool {
                    eagle_set_battery_aura(
                        process,
                        redValue,
                        greenValue,
                        blueValue,
                        Int32(style)
                    )
                }
                BatteryAuraDiagnostics.log("native-call.end", "result=\(result)")
                DispatchQueue.main.async {
                    BatteryAuraApplyGate.end()
                    self.isApplying = false
                    if result > 0 {
                        self.activeStyleRaw = style
                        self.notice = BatteryAuraNotice(
                            message: style == 0
                                ? LaraL10n.text(
                                    en: "The original system battery colors were restored.",
                                    es: "Se restauraron los colores originales de la batería del sistema."
                                )
                                : LaraL10n.text(
                                    en: "Battery Aura was applied and verified on \(result) drawable system view\(result == 1 ? "" : "s"). Return to the Home Screen to see the SpringBoard battery.",
                                    es: "Battery Aura fue aplicada y verificada en \(result) vista\(result == 1 ? "" : "s") dibujable\(result == 1 ? "" : "s") del sistema. Vuelve a la pantalla de inicio para ver la batería de SpringBoard."
                                )
                        )
                    } else {
                        self.notice = BatteryAuraNotice(message: self.message(for: result))
                    }
                }
            }
        }

        if mgr.rcready, mgr.sbProc != nil {
            BatteryAuraDiagnostics.log("session.reuse")
            applyWithSession()
        } else {
            BatteryAuraDiagnostics.log("session.init.begin", "process=SpringBoard")
            mgr.rcinit(process: "SpringBoard") { success in
                BatteryAuraDiagnostics.log(
                    "session.init.end",
                    "success=\(success) rcready=\(self.mgr.rcready) session=\(self.mgr.sbProc != nil)"
                )
                if success || (self.mgr.rcready && self.mgr.sbProc != nil) {
                    applyWithSession()
                } else {
                    let detail = self.mgr.rcLastError?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.finish(
                        stage: "session.init.failure",
                        message: detail?.isEmpty == false
                            ? detail!
                            : LaraL10n.text(
                                en: "Eagle could not start the live SpringBoard session.",
                                es: "Eagle no pudo iniciar la sesión en vivo con SpringBoard."
                            )
                    )
                }
            }
        }
    }

    private func finish(stage: String, message: String) {
        BatteryAuraDiagnostics.log(stage, "finish=true")
        DispatchQueue.main.async {
            if self.isApplying {
                BatteryAuraApplyGate.end()
            }
            self.isApplying = false
            self.notice = BatteryAuraNotice(message: message)
        }
    }

    private func message(for result: Int32) -> String {
        switch result {
        case -2:
            return LaraL10n.text(
                en: "SpringBoard did not expose a live battery view. Unlock the iPhone, visit the Home or Lock Screen once, reopen Eagle, and try again.",
                es: "SpringBoard no mostró una vista activa de batería. Desbloquea el iPhone, visita una vez la pantalla de inicio o bloqueo, vuelve a Eagle e inténtalo otra vez."
            )
        case -3:
            return LaraL10n.text(en: "The selected Battery Aura style is invalid.", es: "El estilo seleccionado de Battery Aura no es válido.")
        case -4:
            return LaraL10n.text(
                en: "The SpringBoard session did not provide an isolated call thread. Nothing was changed.",
                es: "La sesión de SpringBoard no proporcionó un hilo aislado. No se cambió nada."
            )
        case -5:
            return LaraL10n.text(
                en: "Battery Aura is currently limited to verified iOS 17 and 18 surfaces.",
                es: "Battery Aura está limitada actualmente a superficies verificadas de iOS 17 y 18."
            )
        case -6:
            return LaraL10n.text(
                en: "SpringBoard could not create the requested battery color. Nothing was changed.",
                es: "SpringBoard no pudo crear el color solicitado para la batería. No se cambió nada."
            )
        case -7:
            return LaraL10n.text(
                en: "Battery Aura caught an Objective-C exception and stopped. Copy the end of Documents/lara.log before trying again.",
                es: "Battery Aura detectó una excepción de Objective-C y se detuvo. Copia el final de Documents/lara.log antes de volver a intentarlo."
            )
        case -8:
            return LaraL10n.text(
                en: "Eagle found the status-bar battery container, but iOS did not expose its drawable battery glyph. Visit the Home Screen once, reopen Eagle, and try again.",
                es: "Eagle encontró el contenedor de batería de la barra de estado, pero iOS no mostró su icono dibujable. Visita una vez la pantalla de inicio, vuelve a Eagle e inténtalo otra vez."
            )
        case -9:
            return LaraL10n.text(
                en: "Eagle found the real battery glyph but could not install its reversible color route. Nothing was reported as applied.",
                es: "Eagle encontró el icono real de batería, pero no pudo instalar su ruta reversible de color. No se marcó como aplicado."
            )
        case -10:
            return LaraL10n.text(
                en: "UIKit repainted the battery with a different color during verification. Eagle restored the original view instead of reporting a false success.",
                es: "UIKit volvió a dibujar la batería con otro color durante la verificación. Eagle restauró la vista original en lugar de mostrar un éxito falso."
            )
        case -11:
            return LaraL10n.text(
                en: "This iOS battery surface exposes Fill but not the private outline and percentage routes required by Full or Neon. Select Fill and apply again.",
                es: "La superficie de batería de esta versión de iOS permite Carga, pero no las rutas privadas de contorno y porcentaje que requieren Completa o Neón. Selecciona Carga y vuelve a aplicar."
            )
        default:
            return LaraL10n.text(
                en: "SpringBoard rejected the Battery Aura update. Nothing was changed.",
                es: "SpringBoard rechazó la actualización de Battery Aura. No se cambió nada."
            )
        }
    }
}
