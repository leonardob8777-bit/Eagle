import SwiftUI
import UIKit
import Darwin

private struct HomeIconNeonNotice: Identifiable {
    let id = UUID()
    let message: String
}

private enum HomeIconNeonStyle: Int, CaseIterable, Identifiable {
    case glow = 1
    case outline = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .glow: return LaraL10n.text(en: "Glow", es: "Sombra")
        case .outline: return LaraL10n.text(en: "Outline", es: "Contorno")
        }
    }

    var detail: String {
        switch self {
        case .glow:
            return LaraL10n.text(
                en: "A soft neon light spreads beneath each icon.",
                es: "Una luz neón suave se difumina debajo de cada icono."
            )
        case .outline:
            return LaraL10n.text(
                en: "A precise neon line follows the icon's real size.",
                es: "Una línea neón precisa sigue el tamaño real del icono."
            )
        }
    }
}

private enum HomeIconNeonPalette: Int, CaseIterable, Identifiable {
    case electric = 1
    case signalRed = 2
    case hotPink = 3
    case acidGreen = 4
    case ultraviolet = 5
    case amber = 6
    case custom = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .electric: return LaraL10n.text(en: "Electric blue", es: "Azul eléctrico")
        case .signalRed: return LaraL10n.text(en: "Signal red", es: "Rojo señal")
        case .hotPink: return LaraL10n.text(en: "Hot pink", es: "Rosa intenso")
        case .acidGreen: return LaraL10n.text(en: "Acid green", es: "Verde ácido")
        case .ultraviolet: return LaraL10n.text(en: "Ultraviolet", es: "Ultravioleta")
        case .amber: return LaraL10n.text(en: "Amber", es: "Ámbar")
        case .custom: return LaraL10n.text(en: "Custom", es: "Personalizado")
        }
    }

    var color: Color {
        switch self {
        case .electric: return .cyan
        case .signalRed: return .red
        case .hotPink: return .pink
        case .acidGreen: return .green
        case .ultraviolet: return .purple
        case .amber: return .orange
        case .custom: return .white
        }
    }
}

private enum HomeIconNeonIntensity: Int, CaseIterable, Identifiable {
    case subtle = 1
    case vivid = 2
    case maximum = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .subtle: return LaraL10n.text(en: "Subtle", es: "Suave")
        case .vivid: return LaraL10n.text(en: "Vivid", es: "Vivo")
        case .maximum: return LaraL10n.text(en: "Maximum", es: "Máximo")
        }
    }

    var radius: CGFloat {
        switch self {
        case .subtle: return 5
        case .vivid: return 9
        case .maximum: return 13
        }
    }
}

private enum HomeIconNeonDiagnostics {
    static func log(_ stage: String, _ detail: String = "") {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let suffix = detail.isEmpty ? "" : " \(detail)"
        globallogger.log(
            "[\(formatter.string(from: Date()))] " +
            "(eagle.home-icon-neon.apply) stage=\(stage)\(suffix)"
        )
    }
}

@MainActor
private enum HomeIconNeonApplyGate {
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

struct HomeIconNeonView: View {
    var embedded = false

    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(EagleReleaseChannel.storageKey) private var releaseChannelRaw =
        EagleReleaseChannel.stable.rawValue
    @AppStorage("eagle.homeIconNeon.palette")
    private var selectedPaletteRaw = HomeIconNeonPalette.electric.rawValue
    @AppStorage("eagle.homeIconNeon.style")
    private var selectedStyleRaw = HomeIconNeonStyle.glow.rawValue
    @AppStorage("eagle.homeIconNeon.intensity")
    private var selectedIntensityRaw = HomeIconNeonIntensity.vivid.rawValue
    @AppStorage("eagle.homeIconNeon.customRed")
    private var customRed = 0.12
    @AppStorage("eagle.homeIconNeon.customGreen")
    private var customGreen = 0.78
    @AppStorage("eagle.homeIconNeon.customBlue")
    private var customBlue = 1.0
    @AppStorage("eagle.homeIconNeon.activePalette")
    private var activePaletteRaw = 0
    @AppStorage("eagle.homeIconNeon.activeIntensity")
    private var activeIntensityRaw = 0
    @AppStorage("eagle.homeIconNeon.activeSpringBoardPID")
    private var activeSpringBoardPID = 0
    @AppStorage("eagle.homeIconNeon.activePageCount")
    private var activePageCount = 0
    @AppStorage("eagle.homeIconNeon.cleanupRequired")
    private var cleanupRequired = false

    @State private var isApplying = false
    @State private var operationStage = ""
    @State private var notice: HomeIconNeonNotice?
    @State private var lastResult: Int32?

    private var selectedPalette: HomeIconNeonPalette {
        get { HomeIconNeonPalette(rawValue: selectedPaletteRaw) ?? .electric }
        nonmutating set { selectedPaletteRaw = newValue.rawValue }
    }

    private var selectedStyle: HomeIconNeonStyle {
        get { HomeIconNeonStyle(rawValue: selectedStyleRaw) ?? .glow }
        nonmutating set { selectedStyleRaw = newValue.rawValue }
    }

    private var selectedIntensity: HomeIconNeonIntensity {
        get { HomeIconNeonIntensity(rawValue: selectedIntensityRaw) ?? .vivid }
        nonmutating set { selectedIntensityRaw = newValue.rawValue }
    }

    private var customColor: Color {
        Color(red: customRed, green: customGreen, blue: customBlue)
    }

    private var selectedDisplayColor: Color {
        selectedPalette == .custom ? customColor : selectedPalette.color
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { customColor },
            set: { newValue in
                let resolved = UIColor(newValue).resolvedColor(with: .current)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                    customRed = Double(red)
                    customGreen = Double(green)
                    customBlue = Double(blue)
                    selectedPalette = .custom
                }
            }
        )
    }

    private var selectedRGB: (red: Int32, green: Int32, blue: Int32) {
        let color = selectedPalette == .custom
            ? UIColor(customColor).resolvedColor(with: .current)
            : UIColor(selectedPalette.color).resolvedColor(with: .current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (0, 199, 255)
        }
        return (
            Int32((red * 255).rounded()),
            Int32((green * 255).rounded()),
            Int32((blue * 255).rounded())
        )
    }

    private var releaseChannel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: releaseChannelRaw)
    }

    private var policyAllowsApply: Bool {
        EagleFeaturePolicy.allows(.homeIconNeon, channel: releaseChannel)
    }

    private var supportedDevice: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return devicemachine() == "iPhone17,1" &&
            version.majorVersion == 18 &&
            version.minorVersion == 6 &&
            version.patchVersion == 2
    }

    private var recordedPageCount: Int {
        max(activePageCount, activePaletteRaw != 0 ? 1 : 0)
    }

    private var hasRecordedEffect: Bool {
        recordedPageCount > 0 || cleanupRequired
    }

    var body: some View {
        Group {
            if embedded {
                compactEditor
            } else {
                standaloneEditor
            }
        }
        .eagleNotice(item: $notice, title: LaraL10n.text(en: "Home Icon Neon", es: "Neón de iconos")) { $0.message }
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

    private var standaloneEditor: some View {
        ScrollView {
            VStack(spacing: 18) {
                previewCard
                styleCard
                paletteCard
                intensityCard
                scopeCard
                diagnosticsCard
            }
            .padding(20)
        }
        // Apply stays fixed at the bottom, in reach of the thumb; Prepare takes its place until ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: mgr.dsready) {
                applyButton
                removeButton
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "Home Icon Neon", es: "Neón de iconos"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isApplying)
    }

    private var compactEditor: some View {
        VStack(spacing: 12) {
            compactPreview
            compactControls
        }
    }

    private var compactPreview: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "app.fill")
                    .foregroundStyle(selectedDisplayColor)
                Text(LaraL10n.text(en: "Home Icon", es: "Icono de inicio"))
                    .font(.headline)
                Spacer()
                Text(selectedStyle.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedDisplayColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(selectedDisplayColor.opacity(0.12), in: Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.04, blue: 0.065),
                            Color(red: 0.012, green: 0.014, blue: 0.025),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.88), Color.white.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 82, height: 82)
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.72))
                    }
                    .overlay {
                        if selectedStyle == .outline {
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .stroke(selectedDisplayColor, lineWidth: selectedIntensity == .subtle ? 2 : 3.5)
                                .padding(-3)
                        }
                    }
                    .shadow(
                        color: selectedDisplayColor.opacity(selectedStyle == .glow ? 0.95 : 0.62),
                        radius: selectedStyle == .glow ? selectedIntensity.radius * 1.7 : selectedIntensity.radius
                    )
            }
            .frame(height: 145)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LaraL10n.text(
                en: "Home icon preview, \(selectedStyle.title), \(selectedPalette.title)",
                es: "Vista previa del icono, \(selectedStyle.title), \(selectedPalette.title)"
            ))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                LaraL10n.text(en: "Icon neon effect", es: "Efecto neón del icono"),
                selection: $selectedStyleRaw
            ) {
                ForEach(HomeIconNeonStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Picker(
                LaraL10n.text(en: "Neon intensity", es: "Intensidad del neón"),
                selection: $selectedIntensityRaw
            ) {
                ForEach(HomeIconNeonIntensity.allCases) { intensity in
                    Text(intensity.title).tag(intensity.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            HStack {
                Text(LaraL10n.text(en: "Color", es: "Color"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ColorPicker(
                    LaraL10n.text(en: "Custom color", es: "Color personalizado"),
                    selection: customColorBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
            }

            HStack(spacing: 9) {
                ForEach(HomeIconNeonPalette.allCases.filter { $0 != .custom }) { palette in
                    Button {
                        selectedPalette = palette
                    } label: {
                        ZStack {
                            Circle()
                                .fill(palette.color)
                                .frame(width: 34, height: 34)
                                .shadow(color: palette.color.opacity(0.55), radius: 5)
                            if selectedPalette == palette {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .transition(.eagleCheck)
                            }
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                }
                Spacer(minLength: 0)
            }

            applyButton
            removeButton
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .disabled(isApplying)
    }

    private var previewCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(LaraL10n.text(
                    en: "Light up the current page",
                    es: "Ilumina la página actual"
                ))
                .font(.headline)
                Text(selectedStyle.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 18) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: Double(index) / 9.0, saturation: 0.78, brightness: 0.96),
                                    Color(hue: Double(index + 1) / 9.0, saturation: 0.86, brightness: 0.64),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: index.isMultiple(of: 2) ? "sparkles" : "app.fill")
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .shadow(
                            color: selectedDisplayColor.opacity(
                                selectedStyle == .glow ? 0.68 : 0.46
                            ),
                            radius: selectedStyle == .glow
                                ? max(4, selectedIntensity.radius - 1)
                                : max(3, selectedIntensity.radius - 4)
                        )
                        .overlay {
                            if selectedStyle == .outline {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        selectedDisplayColor,
                                        lineWidth: selectedIntensity == .subtle
                                            ? 1.25
                                            : (selectedIntensity == .vivid ? 1.85 : 2.45)
                                    )
                                    .padding(-2)
                            }
                        }
                }
            }
            .padding(.vertical, 5)
            .accessibilityHidden(true)

            Label(
                hasRecordedEffect
                    ? LaraL10n.text(
                        en: cleanupRequired
                            ? "Cleanup required"
                            : "\(recordedPageCount) Home page\(recordedPageCount == 1 ? "" : "s") recorded",
                        es: cleanupRequired
                            ? "Se requiere limpieza"
                            : "\(recordedPageCount) página\(recordedPageCount == 1 ? "" : "s") registrada\(recordedPageCount == 1 ? "" : "s")"
                    )
                    : LaraL10n.text(
                        en: "No icon glow recorded",
                        es: "Sin brillo de iconos registrado"
                    ),
                systemImage: cleanupRequired
                    ? "exclamationmark.triangle.fill"
                    : (activePaletteRaw != 0 ? "checkmark.circle.fill" : "circle")
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(cleanupRequired ? .orange : (activePaletteRaw != 0 ? .green : .secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.96), selectedDisplayColor.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .foregroundStyle(.white)
    }

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LaraL10n.text(en: "Effect", es: "Efecto"))
                .font(.headline)
            Picker(
                LaraL10n.text(en: "Icon neon effect", es: "Efecto neón del icono"),
                selection: $selectedStyleRaw
            ) {
                ForEach(HomeIconNeonStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isApplying)

            Text(selectedStyle.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var paletteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LaraL10n.text(en: "Neon color", es: "Color neón"))
                    .font(.headline)
                Spacer()
                Text(selectedPalette.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 12)],
                spacing: 12
            ) {
                ForEach(HomeIconNeonPalette.allCases.filter { $0 != .custom }) { palette in
                    Button {
                        selectedPalette = palette
                    } label: {
                        ZStack {
                            Circle()
                                .fill(palette.color)
                                .frame(width: 34, height: 34)
                                .shadow(color: palette.color.opacity(0.48), radius: 5)
                            if selectedPalette == palette {
                                Circle()
                                    .strokeBorder(.primary, lineWidth: 2.5)
                                    .frame(width: 42, height: 42)
                                    .transition(.eagleCheck)
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .transition(.eagleCheck)
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .disabled(isApplying)
                    .accessibilityLabel(palette.title)
                    .accessibilityAddTraits(selectedPalette == palette ? .isSelected : [])
                }
            }

            Divider()

            ColorPicker(
                LaraL10n.text(en: "Choose any color", es: "Elegir cualquier color"),
                selection: customColorBinding,
                supportsOpacity: false
            )
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
            .disabled(isApplying)
            .accessibilityHint(LaraL10n.text(
                en: "Selects Custom and uses this exact color for the icon glow.",
                es: "Selecciona Personalizado y usa este color exacto para el brillo."
            ))
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var intensityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LaraL10n.text(en: "Intensity", es: "Intensidad"))
                .font(.headline)
            Picker(
                LaraL10n.text(en: "Neon intensity", es: "Intensidad del neón"),
                selection: $selectedIntensityRaw
            ) {
                ForEach(HomeIconNeonIntensity.allCases) { intensity in
                    Text(intensity.title).tag(intensity.rawValue)
                }
            }
            .pickerStyle(.segmented)
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
                LaraL10n.text(
                    en: "Current Home page only",
                    es: "Solo la página de inicio actual"
                ),
                systemImage: "checkmark.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(.green)

            Text(LaraL10n.text(
                en: "Before Apply, visit the Home page you want, then reopen Eagle. Eagle accepts only app icons from that current root page. Dock, App Library, folders, Dynamic Island, and Prepare are outside this transaction.",
                es: "Antes de Aplicar, visita la página de inicio deseada y vuelve a abrir Eagle. Eagle acepta únicamente iconos de apps de esa página raíz actual. Dock, Biblioteca de apps, carpetas, Dynamic Island y Preparar quedan fuera de esta transacción."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text(LaraL10n.text(
                en: "This is a one-time page snapshot. SpringBoard may recreate icon views after changing pages, opening folders, rotating, or respringing. Return to the same page before Remove.",
                es: "Es una captura puntual de la página. SpringBoard puede recrear los iconos al cambiar de página, abrir carpetas, rotar o hacer respring. Vuelve a la misma página antes de Quitar."
            ))
            .font(.caption)
            .foregroundStyle(.orange)

            Text(LaraL10n.text(
                en: "You can repeat Apply page by page. Up to 24 app icons are accepted on each page; two simultaneous pages were verified in the jailbreak lab.",
                es: "Puedes repetir Aplicar página por página. Se aceptan hasta 24 iconos de apps por página; el laboratorio jailbreak verificó dos páginas simultáneas."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
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
            run(intensity: selectedIntensity.rawValue)
        } label: {
            Label(
                LaraL10n.text(en: "Apply to Current Page", es: "Aplicar a la página actual"),
                systemImage: "sparkles.rectangle.stack.fill"
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

    private var removeButton: some View {
        Button(role: .destructive) {
            run(intensity: 0)
        } label: {
            Label(
                LaraL10n.text(en: "Remove from Current Page", es: "Quitar de la página actual"),
                systemImage: "arrow.uturn.backward.circle.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .disabled(isApplying || !mgr.dsready || mgr.rcSafetyLocked)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                LaraL10n.text(en: "Field-test status", es: "Estado de prueba"),
                systemImage: "stethoscope"
            )
            .font(.headline)

            Text(
                supportedDevice
                    ? LaraL10n.text(
                        en: "Verified allowlist: iPhone 16 Pro · iOS 18.6.2.",
                        es: "Lista permitida: iPhone 16 Pro · iOS 18.6.2."
                    )
                    : LaraL10n.text(
                        en: "This first test build is locked to iPhone 16 Pro on iOS 18.6.2.",
                        es: "Esta primera build de prueba está limitada al iPhone 16 Pro con iOS 18.6.2."
                    )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if !policyAllowsApply {
                Text(LaraL10n.text(
                    en: "Switch the feature channel to Advanced to apply. Remove remains available for recovery.",
                    es: "Cambia el canal de funciones a Avanzado para aplicar. Quitar sigue disponible para recuperación."
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

    private func reconcileState() {
        guard hasRecordedEffect else { return }
        if activePageCount == 0, activePaletteRaw != 0 {
            activePageCount = 1
        }
        let currentPID = "SpringBoard".withCString { find_process_pid($0) }
        guard currentPID > 0 else {
            cleanupRequired = true
            return
        }
        if activeSpringBoardPID > 0, currentPID != activeSpringBoardPID {
            activePaletteRaw = 0
            activeIntensityRaw = 0
            activeSpringBoardPID = 0
            activePageCount = 0
            cleanupRequired = false
        }
    }

    private func run(intensity: Int) {
        let removing = intensity == 0
        let operationStyle = selectedStyle
        let operationPalette = selectedPalette
        let operationRGB = selectedRGB
        HomeIconNeonDiagnostics.log(
            "request",
            "action=\(removing ? "remove" : "apply") style=\(operationStyle.rawValue) " +
            "palette=\(operationPalette.rawValue) " +
            "rgb=\(operationRGB.red),\(operationRGB.green),\(operationRGB.blue) " +
            "intensity=\(intensity) device=\(devicemachine()) channel=\(releaseChannel.rawValue)"
        )

        guard !isApplying, HomeIconNeonApplyGate.begin() else {
            notice = HomeIconNeonNotice(message: LaraL10n.text(
                en: "Home Icon Neon is still finishing the previous operation.",
                es: "Neón de iconos todavía está terminando la operación anterior."
            ))
            return
        }

        func finishBeforeCall(_ message: String) {
            HomeIconNeonApplyGate.end()
            isApplying = false
            notice = HomeIconNeonNotice(message: message)
        }

        guard removing || policyAllowsApply else {
            finishBeforeCall(LaraL10n.text(
                en: "Select the Advanced feature channel before applying this field test.",
                es: "Selecciona el canal Avanzado antes de aplicar esta prueba."
            ))
            return
        }
        guard supportedDevice else {
            finishBeforeCall(LaraL10n.text(
                en: "No system call was sent. This build accepts only iPhone 16 Pro on iOS 18.6.2.",
                es: "No se envió ninguna llamada. Esta build acepta solo iPhone 16 Pro con iOS 18.6.2."
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
            en: "Preparing a fresh Home Screen session…",
            es: "Preparando una sesión nueva de Inicio…"
        )

        mgr.prepareFreshRemoteCall(process: "SpringBoard", timeout: 20) { process, error in
            guard let process else {
                let reason = error ?? "Fresh SpringBoard session unavailable"
                let preflight =
                    reason.localizedCaseInsensitiveContains("access is not ready") ||
                    reason.localizedCaseInsensitiveContains("still running") ||
                    reason.localizedCaseInsensitiveContains("safety locked")
                if !preflight {
                    mgr.quarantineRemoteCall(reason: "Home Icon Neon session failed: \(reason)")
                }
                finishBeforeCall(reason)
                return
            }

            let targetPID = process.pid
            let currentPID = "SpringBoard".withCString { find_process_pid($0) }
            guard targetPID > 0,
                  currentPID == targetPID,
                  process.creatingExtraThread else {
                let reason = "Home Icon Neon fresh-session identity check failed " +
                    "(target \(targetPID), current \(currentPID), isolated \(process.creatingExtraThread))"
                mgr.quarantineRemoteCall(reason: reason)
                finishBeforeCall(reason)
                return
            }

            let label = "Home Icon Neon \(UUID().uuidString)"
            guard mgr.beginExclusiveRemoteCall(label: label, expectedSession: process) else {
                finishBeforeCall(LaraL10n.text(
                    en: "Another protected operation is active. Wait and try again.",
                    es: "Hay otra operación protegida activa. Espera e inténtalo de nuevo."
                ))
                return
            }

            operationStage = removing
                ? LaraL10n.text(en: "Removing only tagged icon glows…", es: "Quitando solo brillos etiquetados…")
                : operationStyle == .outline
                    ? LaraL10n.text(en: "Staging and verifying icon outlines…", es: "Preparando y verificando los contornos…")
                    : LaraL10n.text(en: "Staging and verifying icon glows…", es: "Preparando y verificando los brillos…")

            var nativeFinished = false
            var deadlineExceeded = false
            let deadlineWork = DispatchWorkItem {
                guard !nativeFinished else { return }
                deadlineExceeded = true
                cleanupRequired = true
                let reason = "Home Icon Neon exceeded the 60-second safety deadline"
                mgr.quarantineRemoteCall(reason: reason)
                operationStage = LaraL10n.text(
                    en: "Waiting safely · no automatic retry will start…",
                    es: "Esperando de forma segura · no habrá reintento automático…"
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: deadlineWork)

            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool {
                    eagle_set_home_icon_neon(
                        process,
                        Int32(operationStyle.rawValue),
                        Int32(removing ? 0 : operationPalette.rawValue),
                        Int32(intensity),
                        operationRGB.red,
                        operationRGB.green,
                        operationRGB.blue
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
                    HomeIconNeonApplyGate.end()
                    isApplying = false
                    lastResult = result

                    HomeIconNeonDiagnostics.log(
                        "native.end",
                        "result=\(result) target=\(targetPID) current=\(pidAfter) " +
                        "healthy=\(healthy) timeout=\(timedOut) error=\(processError ?? "none")"
                    )

                    if deadlineExceeded {
                        notice = HomeIconNeonNotice(message: LaraL10n.text(
                            en: "The safety deadline expired. Fully close and reopen Eagle before another test, then use Remove on the same Home page.",
                            es: "Venció el límite de seguridad. Cierra y abre Eagle antes de otra prueba y usa Quitar en la misma página."
                        ))
                        return
                    }

                    let transportVerified = healthy && !timedOut && pidAfter == targetPID
                    if !transportVerified || result == -7 || result == -12 {
                        cleanupRequired = true
                        let reason = "Home Icon Neon unverified transport/result \(result)"
                        mgr.quarantineRemoteCall(reason: reason)
                        notice = HomeIconNeonNotice(message: LaraL10n.text(
                            en: "The protected result could not be verified. No retry will start. Fully close Eagle, reopen it, return to the same page, and use Remove.",
                            es: "No se pudo verificar el resultado protegido. No habrá reintento. Cierra Eagle, vuelve a abrirla, regresa a la misma página y usa Quitar."
                        ))
                        return
                    }

                    if removing {
                        if result > 0 {
                            activePageCount = max(0, recordedPageCount - 1)
                            if activePageCount == 0 {
                                activePaletteRaw = 0
                                activeIntensityRaw = 0
                                activeSpringBoardPID = 0
                            }
                            notice = HomeIconNeonNotice(message: LaraL10n.text(
                                en: "Removed \(result) tagged icon glow\(result == 1 ? "" : "s") from the current page. \(activePageCount) other page\(activePageCount == 1 ? " remains" : "s remain") recorded. Dock and Island were not changed.",
                                es: "Se quitaron \(result) brillo\(result == 1 ? "" : "s") etiquetado\(result == 1 ? "" : "s") de la página actual. Quedan \(activePageCount) página\(activePageCount == 1 ? "" : "s") registrada\(activePageCount == 1 ? "" : "s"). Dock e Isla no cambiaron."
                            ))
                        } else if result == 0 {
                            cleanupRequired = true
                            notice = HomeIconNeonNotice(message: LaraL10n.text(
                                en: "No tagged glow was found on this page. Return to the exact Home page where you applied it, then try Remove again.",
                                es: "No se encontró brillo etiquetado en esta página. Vuelve a la página exacta donde lo aplicaste e intenta Quitar otra vez."
                            ))
                        } else {
                            notice = HomeIconNeonNotice(message: message(for: result, removing: true))
                        }
                        return
                    }

                    if result > 0 {
                        let effectName = operationStyle == .outline
                            ? LaraL10n.text(en: "neon outline", es: "contorno neón")
                            : LaraL10n.text(en: "diffuse glow", es: "resplandor difuminado")
                        activePageCount = min(32, recordedPageCount + 1)
                        activePaletteRaw = operationPalette.rawValue
                        activeIntensityRaw = intensity
                        activeSpringBoardPID = Int(targetPID)
                        notice = HomeIconNeonNotice(message: LaraL10n.text(
                            en: "Applied and verified \(effectName) on \(result) app icon\(result == 1 ? "" : "s") on this Home page. \(activePageCount) page\(activePageCount == 1 ? " is" : "s are") now recorded. Dock, folders, App Library, Island, and Prepare were not changed.",
                            es: "Se aplicó y verificó \(effectName) en \(result) icono\(result == 1 ? "" : "s") de esta página. Ahora hay \(activePageCount) página\(activePageCount == 1 ? "" : "s") registrada\(activePageCount == 1 ? "" : "s"). Dock, carpetas, Biblioteca, Isla y Preparar no cambiaron."
                        ))
                    } else {
                        if result == -9 { cleanupRequired = true }
                        notice = HomeIconNeonNotice(message: message(for: result, removing: false))
                    }
                }
            }
        }
    }

    private func message(for result: Int32, removing: Bool) -> String {
        switch result {
        case -2:
            return LaraL10n.text(
                en: "SpringBoard did not expose a current root Home page with app icons. Visit the desired Home page once, reopen Eagle, and try again.",
                es: "SpringBoard no expuso una página raíz actual con iconos. Visita la página deseada, vuelve a abrir Eagle e inténtalo otra vez."
            )
        case -3:
            return LaraL10n.text(en: "The selected effect, color, or intensity is invalid.", es: "El efecto, color o intensidad no son válidos.")
        case -4:
            return LaraL10n.text(en: "The isolated protected thread was unavailable.", es: "El hilo protegido aislado no estaba disponible.")
        case -5:
            return LaraL10n.text(en: "This device/build is outside the first safe allowlist.", es: "Este dispositivo o versión no está en la primera lista segura.")
        case -6:
            return LaraL10n.text(en: "SpringBoard could not create the selected system neon color.", es: "SpringBoard no pudo crear el color neón seleccionado.")
        case -8:
            return LaraL10n.text(en: "The current page hierarchy was larger or more ambiguous than the safe limit.", es: "La jerarquía de la página era mayor o más ambigua que el límite seguro.")
        case -9:
            return LaraL10n.text(
                en: "Tagged icon glow already exists on this page. Use Remove before choosing another color or intensity.",
                es: "Ya existe brillo etiquetado en esta página. Usa Quitar antes de elegir otro color o intensidad."
            )
        case -10:
            return LaraL10n.text(
                en: "The candidate did not verify and Eagle removed its staging views. Nothing was marked active.",
                es: "La candidata no se verificó y Eagle quitó las vistas temporales. Nada se marcó como activo."
            )
        case -11:
            return LaraL10n.text(en: "The existing direct-child state could not be read safely.", es: "No se pudo leer con seguridad el estado de hijos directos.")
        case -13:
            return LaraL10n.text(en: "The page exceeded the safe call budget before mutation.", es: "La página superó el presupuesto seguro antes de la mutación.")
        default:
            return LaraL10n.text(
                en: "Home Icon Neon returned result \(result). \(removing ? "No cleanup was confirmed." : "Nothing was marked active.")",
                es: "Neón de iconos devolvió \(result). \(removing ? "No se confirmó la limpieza." : "Nada se marcó como activo.")"
            )
        }
    }
}
