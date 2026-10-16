import SwiftUI
import UIKit
import Combine

private typealias DockGalleryStyle = EagleDockGalleryBuiltInTheme

private extension EagleDockGalleryBuiltInTheme {
    var title: String {
        let text = titleText
        if self == .springfield { return text.en }
        return LaraL10n.text(en: text.en, es: text.es)
    }

    var subtitle: String {
        let text = subtitleText
        return LaraL10n.text(en: text.en, es: text.es)
    }

    var accent: Color {
        let components = accentComponents
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}

private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme

private extension EagleDockGalleryTheme {
    var localizedTitle: String { LaraL10n.text(en: title, es: titleES) }
    var localizedSubtitle: String { LaraL10n.text(en: subtitle, es: subtitleES) }
    var color: Color { Color(eagleHex: accent) }
}

private extension Color {
    init(eagleHex: String) {
        let hex = eagleHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(hex, radix: 16) ?? 0xDB40E0
        self.init(
            red: Double((value >> 16) & 0xff) / 255.0,
            green: Double((value >> 8) & 0xff) / 255.0,
            blue: Double(value & 0xff) / 255.0
        )
    }
}

private final class DockGalleryRemoteCallBox: @unchecked Sendable {
    let value: RemoteCall

    init(_ value: RemoteCall) {
        self.value = value
    }
}

private struct DockGalleryNativeResponse: @unchecked Sendable {
    let result: Int32
    let targetPID: Int32
    let springBoardPID: Int32
    let healthy: Bool
    let timedOut: Bool
    let error: String?
}

private struct DockGalleryApplyResult {
    let succeeded: Bool
    let message: String
}

@MainActor
private final class DockGalleryExecutor {
    static let shared = DockGalleryExecutor()

    private let manager = laramgr.shared
    private let dockFlag: UInt32 = 1 << 5
    private let supportedFlags: UInt32 = 1 | (1 << 5)

    private init() {}

    func apply(_ style: DockGalleryStyle, intensity: Double) async -> DockGalleryApplyResult {
        await run(style: style, remote: nil, directory: nil, intensity: intensity, restoring: false)
    }

    func applyRemote(
        _ theme: RemoteDockGalleryTheme,
        directory: URL,
        intensity: Double
    ) async -> DockGalleryApplyResult {
        await run(style: nil, remote: theme, directory: directory, intensity: intensity, restoring: false)
    }

    func restore() async -> DockGalleryApplyResult {
        await run(style: nil, remote: nil, directory: nil, restoring: true)
    }

    private func run(
        style: DockGalleryStyle?,
        remote: RemoteDockGalleryTheme?,
        directory: URL?,
        intensity: Double = 0.72,
        restoring: Bool
    ) async -> DockGalleryApplyResult {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let position = restoring
            ? GalleryPosition(x: 0, y: 0)
            : GalleryPosition.saved("dock")
        guard manager.dsready else {
            return failure(
                en: "Prepare Eagle access before changing the Dock.",
                es: "Prepara el acceso de Eagle antes de cambiar el Dock."
            )
        }
        guard !manager.rcSafetyLocked else {
            return failure(
                en: "Fully close and reopen Eagle before retrying the protected Dock call.",
                es: "Cierra Eagle completamente y vuelve a abrirlo antes de reintentar la llamada protegida del Dock."
            )
        }
        guard !isdebugged() else {
            return failure(
                en: "Open Eagle manually from the Home Screen before applying a Dock theme.",
                es: "Abre Eagle manualmente desde Inicio antes de aplicar un tema del Dock."
            )
        }
        guard version.majorVersion == 17 || version.majorVersion == 18 else {
            return failure(
                en: "Dock Gallery is available only on iOS 17 and iOS 18.",
                es: "Galería Dock está disponible solo en iOS 17 y iOS 18."
            )
        }
        let preparation: (RemoteCall?, String?) = await withCheckedContinuation { continuation in
            manager.prepareFreshRemoteCall(process: "SpringBoard", timeout: 20) { process, error in
                continuation.resume(returning: (process, error))
            }
        }
        guard let process = preparation.0 else {
            return failure(
                en: "A fresh SpringBoard session could not be prepared. Nothing changed. \(preparation.1 ?? "")",
                es: "No se pudo preparar una sesión nueva de SpringBoard. Nada cambió. \(preparation.1 ?? "")"
            )
        }
        let operationID = String(UUID().uuidString.prefix(8))
        let label = "Dock Gallery \(operationID)"
        guard !Task.isCancelled,
              manager.beginExclusiveRemoteCall(label: label, expectedSession: process) else {
            return failure(
                en: "Another protected SpringBoard operation is still active.",
                es: "Otra operación protegida de SpringBoard sigue activa."
            )
        }
        defer { manager.endExclusiveRemoteCall(label: label) }

        let targetPID = process.pid
        let currentPID = Self.readSpringBoardPID()
        guard targetPID > 0,
              targetPID == currentPID,
              process.creatingExtraThread else {
            return failure(
                en: "The SpringBoard identity changed before Apply. Nothing was sent.",
                es: "La identidad de SpringBoard cambió antes de Aplicar. No se envió nada."
            )
        }

        let processBox = DockGalleryRemoteCallBox(process)
        let rgb = style?.rgb ?? remote?.rgb ?? (0, 0, 0)
        let mode = Int32(remote == nil ? (style?.rawValue ?? 0) : 35)
        let remoteDirectory = directory?.path
        let remoteDuration = remote?.duration ?? 0
        let appliedIntensity = EagleStoredThemeValues.intensity(intensity)
        let response: DockGalleryNativeResponse = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool {
                    eagle_configure_gallery_position(
                        0,
                        position.x,
                        position.y
                    )
                    defer { eagle_configure_gallery_position(0, 0, 0) }
                    eagle_set_dock_gallery_intensity(Int32((appliedIntensity * 100).rounded()))
                    if let remoteDirectory {
                        return remoteDirectory.withCString { path in
                            eagle_configure_remote_dock_gallery(path, Int32(remote?.frameCount ?? 0), remoteDuration)
                            defer { eagle_configure_remote_dock_gallery(nil, 0, 0) }
                            return eagle_set_aura_studio(
                                processBox.value, rgb.0, rgb.1, rgb.2,
                                mode, self.dockFlag
                            )
                        }
                    }
                    eagle_configure_remote_dock_gallery(nil, 0, 0)
                    return eagle_set_aura_studio(
                        processBox.value, rgb.0, rgb.1, rgb.2,
                        mode, self.dockFlag
                    )
                }
                continuation.resume(returning: DockGalleryNativeResponse(
                    result: result,
                    targetPID: targetPID,
                    springBoardPID: Self.readSpringBoardPID(),
                    healthy: processBox.value.isHealthy,
                    timedOut: processBox.value.lastCallTimedOut,
                    error: processBox.value.lastError
                ))
            }
        }

        guard response.targetPID == response.springBoardPID else {
            clearVerifiedDock()
            manager.quarantineRemoteCall(
                reason: "SpringBoard restarted during Dock Gallery verification"
            )
            return failure(
                en: "SpringBoard restarted during verification. The theme was not marked as applied.",
                es: "SpringBoard se reinició durante la verificación. El tema no se marcó como aplicado."
            )
        }
        guard response.healthy,
              !response.timedOut,
              response.error?.isEmpty != false else {
            clearVerifiedDock()
            manager.quarantineRemoteCall(
                reason: response.error ?? "Dock Gallery transport became unhealthy"
            )
            return failure(
                en: "The protected Dock call became unhealthy. Fully close and reopen Eagle.",
                es: "La llamada protegida del Dock dejó de estar disponible. Cierra Eagle completamente y vuelve a abrirlo."
            )
        }
        guard response.result >= 0 else {
            return failure(
                en: "The Dock theme returned result \(response.result) and was not applied.",
                es: "El tema del Dock devolvió el resultado \(response.result) y no se aplicó."
            )
        }
        let flags = UInt32(bitPattern: response.result)
        guard flags & dockFlag == dockFlag else {
            clearVerifiedDock()
            return failure(
                en: "SpringBoard returned without verifying the Dock surface.",
                es: "SpringBoard terminó sin verificar la superficie del Dock."
            )
        }

        if restoring {
            clearVerifiedDock(springBoardPID: response.springBoardPID)
            return DockGalleryApplyResult(
                succeeded: true,
                message: LaraL10n.text(
                    en: "The Dock artwork was removed.",
                    es: "Se quitó el arte del Dock."
                )
            )
        }
        guard style != nil || remote != nil else {
            return failure(en: "No theme was selected.", es: "No se seleccionó ningún tema.")
        }
        if let style {
            persistVerified(style, springBoardPID: response.springBoardPID)
        } else if let remote {
            persistVerified(remote, springBoardPID: response.springBoardPID)
        }
        UserDefaults.standard.set(appliedIntensity, forKey: "eagle.dockGallery.appliedGlowIntensity")
        let title = style?.title ?? remote?.localizedTitle ?? ""
        return DockGalleryApplyResult(
            succeeded: true,
            message: LaraL10n.text(
                en: "\(title) was applied behind the Dock apps.",
                es: "\(title) se aplicó detrás de las apps del Dock."
            )
        )
    }

    private func persistVerified(
        _ style: DockGalleryStyle,
        springBoardPID: Int32
    ) {
        let defaults = UserDefaults.standard
        let savedPID = defaults.integer(forKey: "eagle.auraStudio.activeSpringBoardPID")
        var flags = savedPID == Int(springBoardPID)
            ? EagleStoredThemeValues.flags(defaults.integer(forKey: "eagle.auraStudio.activeFlags")) & supportedFlags
            : 0
        flags |= dockFlag
        defaults.set(Int(flags), forKey: "eagle.auraStudio.activeFlags")
        defaults.set(Int(springBoardPID), forKey: "eagle.auraStudio.activeSpringBoardPID")
        defaults.set(style.rawValue, forKey: "eagle.auraStudio.activeDockMode")
        defaults.set(style.rawValue, forKey: "eagle.dockGallery.activeStyle")
        defaults.set(style.rawValue, forKey: "eagle.dockGallery.selectedStyle")
        defaults.set(Int(style.rgb.0), forKey: "eagle.auraStudio.activeDockRed")
        defaults.set(Int(style.rgb.1), forKey: "eagle.auraStudio.activeDockGreen")
        defaults.set(Int(style.rgb.2), forKey: "eagle.auraStudio.activeDockBlue")
        defaults.removeObject(forKey: "eagle.dockGallery.activeRemoteID")
    }

    private func persistVerified(
        _ theme: RemoteDockGalleryTheme,
        springBoardPID: Int32
    ) {
        let defaults = UserDefaults.standard
        let savedPID = defaults.integer(forKey: "eagle.auraStudio.activeSpringBoardPID")
        var flags = savedPID == Int(springBoardPID)
            ? EagleStoredThemeValues.flags(defaults.integer(forKey: "eagle.auraStudio.activeFlags")) & supportedFlags
            : 0
        flags |= dockFlag
        defaults.set(Int(flags), forKey: "eagle.auraStudio.activeFlags")
        defaults.set(Int(springBoardPID), forKey: "eagle.auraStudio.activeSpringBoardPID")
        defaults.set(35, forKey: "eagle.auraStudio.activeDockMode")
        defaults.set(0, forKey: "eagle.dockGallery.activeStyle")
        defaults.set(theme.id, forKey: "eagle.dockGallery.activeRemoteID")
        defaults.set(Int(theme.rgb.0), forKey: "eagle.auraStudio.activeDockRed")
        defaults.set(Int(theme.rgb.1), forKey: "eagle.auraStudio.activeDockGreen")
        defaults.set(Int(theme.rgb.2), forKey: "eagle.auraStudio.activeDockBlue")
    }

    private func clearVerifiedDock(springBoardPID: Int32? = nil) {
        let defaults = UserDefaults.standard
        var flags = EagleStoredThemeValues.flags(defaults.integer(forKey: "eagle.auraStudio.activeFlags")) & supportedFlags
        flags &= ~dockFlag
        defaults.set(Int(flags), forKey: "eagle.auraStudio.activeFlags")
        defaults.set(0, forKey: "eagle.auraStudio.activeDockMode")
        defaults.set(0, forKey: "eagle.dockGallery.activeStyle")
        defaults.removeObject(forKey: "eagle.dockGallery.activeRemoteID")
        if flags == 0 {
            defaults.set(0, forKey: "eagle.auraStudio.activeSpringBoardPID")
        } else if let springBoardPID {
            defaults.set(Int(springBoardPID), forKey: "eagle.auraStudio.activeSpringBoardPID")
        }
    }

    private func failure(en: String, es: String) -> DockGalleryApplyResult {
        DockGalleryApplyResult(
            succeeded: false,
            message: LaraL10n.text(en: en, es: es)
        )
    }

    nonisolated private static func readSpringBoardPID() -> Int32 {
        "SpringBoard".withCString { find_process_pid($0) }
    }
}

/// Transitional adapter: Eagle owns the call boundary while the existing
/// protected executor continues to perform the operation without changes.
@MainActor
private struct CurrentDockGalleryPort: EagleDockGalleryPort {
    func applyRemote(
        _ request: EagleDockGalleryApplyRequest
    ) async -> EagleDockGalleryOutcome {
        let result = await DockGalleryExecutor.shared.applyRemote(
            request.theme,
            directory: request.directory,
            intensity: request.intensity
        )
        return EagleDockGalleryOutcome(
            succeeded: result.succeeded,
            message: result.message
        )
    }

    func restore() async -> EagleDockGalleryOutcome {
        let result = await DockGalleryExecutor.shared.restore()
        return EagleDockGalleryOutcome(
            succeeded: result.succeeded,
            message: result.message
        )
    }
}

struct DockGalleryView: View {
    private typealias MediaFilter = EagleDockGalleryMediaFilter

    @ObservedObject private var manager = laramgr.shared
    @StateObject private var remoteGallery = EagleGalleryServices.dock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("eagle.dockGallery.selectedStyle")
    private var selectedRaw = DockGalleryStyle.bubblegum.rawValue
    @AppStorage("eagle.dockGallery.activeStyle") private var activeRaw = 0
    @AppStorage("eagle.auraStudio.activeFlags") private var activeFlagsRaw = 0
    @AppStorage("eagle.auraStudio.activeDockMode") private var activeDockModeRaw = 0
    @AppStorage("eagle.dockGallery.activeRemoteID") private var activeRemoteID = ""
    @AppStorage("eagle.dockGallery.glowIntensity") private var glowIntensity = 0.72
    @AppStorage("eagle.dockGallery.positionX") private var positionX = 0.0
    @AppStorage("eagle.dockGallery.positionY") private var positionY = 0.0
    @AppStorage("eagle.dockGallery.favoriteIDs") private var favoriteIDsJSON = "[]"
    @AppStorage("eagle.dockGallery.lastViewedStaticID") private var lastViewedStaticID = ""
    @AppStorage("eagle.dockGallery.lastViewedLiveID") private var lastViewedLiveID = ""
    @State private var isApplying = false
    @State private var session: EagleDockGallerySession = .init()
    @State private var needsNewVisitOnResume = false
    @State private var showAccessSetup = false

    private var selectedRemoteID: String {
        get { session.selectedRemoteID }
        nonmutating set { session.selectedRemoteID = newValue }
    }

    private var mediaFilter: MediaFilter {
        get { session.mediaFilter }
        nonmutating set { session.mediaFilter = newValue }
    }

    private var rememberedSelections: EagleDockGallerySelectionMemory {
        get { session.rememberedSelections }
        nonmutating set { session.rememberedSelections = newValue }
    }

    private var shuffledRemoteIDs: [String] {
        get { session.shuffledRemoteIDs }
        nonmutating set { session.shuffledRemoteIDs = newValue }
    }

    private var visitStarted: Bool {
        get { session.visitStarted }
        nonmutating set { session.visitStarted = newValue }
    }

    private var readyRemotePreviewID: String {
        get { session.readyRemotePreviewID }
        nonmutating set { session.readyRemotePreviewID = newValue }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                onlineCollection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        // The selected theme's Apply stays fixed at the bottom, in reach of the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let theme = selectedRemoteTheme {
                EagleApplyBar {
                    remoteActionButton(theme)
                }
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "Dock Gallery", es: "Galería Dock"))
        // Refresh in the navigation bar, as in Island Gallery.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await remoteGallery.load(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(remoteGallery.loading || isApplying)
                .accessibilityLabel(LaraL10n.text(en: "Refresh collection", es: "Actualizar colección"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAccessSetup) {
            NavigationStack {
                ScrollView {
                    LaraAccessView(compact: true) {
                        showAccessSetup = false
                    }
                    .padding(20)
                }
                .eagleScreenBackdrop()
                .navigationTitle(LaraL10n.text(en: "Prepare Eagle", es: "Preparar Eagle"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(LaraL10n.text(en: "Done", es: "Listo")) {
                            showAccessSetup = false
                        }
                    }
                }
            }
        }
        .onAppear {
            EagleDockGalleryLifecycle.appear(
                visitStarted: { visitStarted },
                beginVisit: { beginGalleryVisit() }
            )
            EagleDockGalleryStoredSelection.reconcile(
                selectedRaw: { selectedRaw },
                setSelectedRaw: { selectedRaw = $0 },
                hasVerifiedDock: { hasVerifiedDock },
                activeRaw: { activeRaw },
                setActiveRaw: { activeRaw = $0 },
                activeDockModeRaw: { activeDockModeRaw },
                setActiveDockModeRaw: { activeDockModeRaw = $0 },
                activeRemoteID: { activeRemoteID },
                setActiveRemoteID: { activeRemoteID = $0 }
            )
        }
        .onDisappear {
            EagleDockGalleryLifecycle.disappear(
                showAccessSetup: { showAccessSetup },
                setVisitStarted: { visitStarted = $0 }
            )
        }
        .onChange(of: scenePhase) { phase in
            EagleDockGalleryLifecycle.sceneChanged(
                phase == .background ? .background : (phase == .active ? .active : .other),
                visitStarted: { visitStarted },
                needsNewVisitOnResume: { needsNewVisitOnResume },
                setNeedsNewVisitOnResume: { needsNewVisitOnResume = $0 },
                showAccessSetup: { showAccessSetup },
                isApplying: { isApplying },
                downloadingID: { remoteGallery.downloadingID },
                beginVisit: { beginGalleryVisit() }
            )
        }
        .task {
            await remoteGallery.load()
            synchronizeRemoteSelection()
        }
        .onChange(of: remoteGallery.themes) { _ in
            synchronizeRemoteSelection()
        }
        .onChange(of: favoriteIDsJSON) { _ in
            synchronizeRemoteSelection()
        }
    }

    private func themeCard(_ style: DockGalleryStyle) -> some View {
        let active = hasVerifiedDock &&
            activeDockModeRaw == style.rawValue &&
            activeRaw == style.rawValue
        return VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)
                artworkPreview(style)
                    .id(style.rawValue)
                    .transition(.opacity)
                    .shadow(color: style.accent.opacity(0.95), radius: 18)
                    .padding(.horizontal, 8)
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.90 - Double(index) * 0.08))
                            .frame(width: 43, height: 43)
                            .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: style.rawValue)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title).font(.headline)
                    Text(style.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(style.accent)
                }
            }

            Button(role: active ? .destructive : nil) {
                active ? restore() : apply(style)
            } label: {
                HStack(spacing: 8) {
                    if isApplying {
                        ProgressView().tint(EagleVisualTheme.actionText)
                    } else {
                        Image(systemName: active
                            ? "arrow.counterclockwise"
                            : "sparkles")
                    }
                    Text(active
                        ? LaraL10n.text(en: "Remove", es: "Quitar")
                        : LaraL10n.text(
                            en: "Apply \(style.title)",
                            es: "Aplicar \(style.title)"
                        ))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(EagleApplyButtonStyle(fill: active ? .red : EagleVisualTheme.actionFill,
                                               text: active ? .white : EagleVisualTheme.actionText,
                                               busy: isApplying))
            .disabled(isApplying || !manager.dsready)
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    active ? style.accent : Color.primary.opacity(0.08),
                    lineWidth: active ? 2 : 1
                )
        }
    }

    @ViewBuilder
    private var onlineCollection: some View {
        if remoteGallery.loading && remoteGallery.themes.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text(LaraL10n.text(en: "Loading online collection…", es: "Cargando colección en línea…"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if let error = remoteGallery.errorMessage, remoteGallery.themes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(error).foregroundStyle(.secondary)
                Button(LaraL10n.text(en: "Try again", es: "Reintentar")) {
                    Task { await remoteGallery.load(force: true) }
                }
                .buttonStyle(.bordered)
            }
        } else if !remoteGallery.themes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                mediaFilterControl

                if let theme = selectedRemoteTheme {
                    remoteThemeCard(theme)
                    GalleryPositionControl(
                        x: $positionX,
                        y: $positionY,
                        disabled: isApplying || remoteGallery.downloadingID != nil
                    )
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: mediaFilter == .favorites ? "heart" : "photo")
                            .font(.title2)
                        Text(mediaFilter == .favorites
                            ? LaraL10n.text(en: "Save your favorites with ♡", es: "Guarda tus favoritos con ♡")
                            : LaraL10n.text(en: "No styles in this category yet.", es: "Aún no hay estilos en esta categoría."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
        }
    }

    private var glowIntensityControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(LaraL10n.text(en: "Shadow", es: "Sombra"), systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(glowIntensity <= 0.005
                    ? LaraL10n.text(en: "Off", es: "Sin sombra")
                    : "\(Int((glowIntensity * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $glowIntensity, in: 0...1, step: 0.01)
                .tint(.primary)
                .disabled(isApplying || remoteGallery.downloadingID != nil)
                .accessibilityLabel(LaraL10n.text(en: "Dock light intensity", es: "Intensidad de luz del Dock"))
        }
        .padding(.horizontal, 2)
    }

    private func remoteThemeCard(_ theme: RemoteDockGalleryTheme) -> some View {
        let active = hasVerifiedDock && activeRemoteID == theme.id &&
            (activeDockModeRaw == 35 || Self.remoteID(forLegacyMode: activeDockModeRaw) == theme.id)
        return VStack(alignment: .center, spacing: 14) {
            GeometryReader { proxy in
                let availableWidth = max(proxy.size.width - 16, 1)
                let actualDockWidth = max(UIScreen.main.bounds.width - 30, 250)
                let actualDockHeight: CGFloat = 102.333333
                let aspectRatio = actualDockWidth / actualDockHeight
                let dockHeight = min(proxy.size.height, availableWidth / aspectRatio)
                let dockWidth = min(availableWidth, dockHeight * aspectRatio)
                let intensity = CGFloat(min(max(glowIntensity, 0), 1))
                let lightScale = dockHeight / actualDockHeight
                let lightPadding = CGFloat(eagle_dock_gallery_glow_padding()) * lightScale

                ZStack {
                    if readyRemotePreviewID == theme.id,
                       let halo = eagle_dock_gallery_glow_image(
                           theme.rgb.0, theme.rgb.1, theme.rgb.2,
                           Double(actualDockWidth), Double(actualDockHeight)) {
                        Image(uiImage: halo)
                            .resizable()
                            .frame(width: dockWidth + 2 * lightPadding, height: dockHeight + 2 * lightPadding)
                            .opacity(Double(intensity))
                            .offset(
                                x: GalleryPosition.component(positionX) * lightScale,
                                y: GalleryPosition.component(positionY) * lightScale
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    LaraRemoteMediaPreview(
                        url: theme.presentationPreviewURL,
                        animated: theme.frameCount > 1,
                        contentMode: .fill,
                        showsRetry: true,
                        background: .clear,
                        presentationMotion: theme.frameCount == 1,
                        onReady: { ready in
                            EagleDockGalleryPreviewReadiness.update(
                                ready,
                                themeID: theme.id,
                                selectedThemeID: { selectedRemoteTheme?.id },
                                readyPreviewID: { readyRemotePreviewID },
                                setReadyPreviewID: { readyRemotePreviewID = $0 }
                            )
                        }
                    )
                    .id("dock-preview-\(theme.id)")
                    .transition(.opacity)
                    .frame(width: dockWidth, height: dockHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 40 * lightScale, style: .circular))
                    .offset(
                        x: GalleryPosition.component(positionX) * lightScale,
                        y: GalleryPosition.component(positionY) * lightScale
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: theme.id)

                    if readyRemotePreviewID == theme.id {
                        HStack(spacing: 14) {
                            ForEach(0..<4, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.90 - Double(index) * 0.08))
                                    .frame(width: 43, height: 43)
                                    .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                            }
                        }
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    }

                    EagleGalleryPreviewSheen(
                        active: readyRemotePreviewID == theme.id && !isApplying,
                        opacity: 0.095
                    )
                    .frame(width: dockWidth, height: dockHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 40 * lightScale, style: .circular))
                    .offset(
                        x: GalleryPosition.component(positionX) * lightScale,
                        y: GalleryPosition.component(positionY) * lightScale
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 212)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        animatedStepRemote(value.translation.width < 0 ? 1 : -1)
                    }
            )

            HStack(spacing: 8) {
                Text(theme.localizedTitle)
                    .font(.title3.bold())
                    .lineLimit(2)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(theme.color)
                }
                Spacer(minLength: 6)
                Button {
                    toggleFavorite(theme)
                } label: {
                    Image(systemName: favoriteIDs.contains(theme.id) ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(favoriteIDs.contains(theme.id) ? Color.pink : .primary)
                        .eagleSymbolPop(favoriteIDs.contains(theme.id))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(EaglePressableStyle(kind: .swatch))
                .disabled(isApplying || remoteGallery.downloadingID != nil)
                .accessibilityLabel(favoriteIDs.contains(theme.id)
                    ? LaraL10n.text(en: "Remove from favorites", es: "Quitar de favoritos")
                    : LaraL10n.text(en: "Add to favorites", es: "Añadir a favoritos"))
                .accessibilityValue(theme.localizedTitle)
            }

            HStack(spacing: 28) {
                remoteArrowButton(symbol: "chevron.left", step: -1)
                Text(remotePositionText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 54)
                remoteArrowButton(symbol: "chevron.right", step: 1)
            }
            .frame(maxWidth: .infinity)

            glowIntensityControl
        }
        .animation(.easeOut(duration: 0.16), value: glowIntensity)
    }

    private func remoteActionButton(_ theme: RemoteDockGalleryTheme) -> some View {
        let active = hasVerifiedDock && activeRemoteID == theme.id &&
            (activeDockModeRaw == 35 || Self.remoteID(forLegacyMode: activeDockModeRaw) == theme.id)
        let downloading = remoteGallery.downloadingID == theme.id
        return HStack(spacing: 10) {
            Button {
                if !manager.dsready {
                    showAccessSetup = true
                } else {
                    applyRemote(theme)
                }
            } label: {
                HStack(spacing: 8) {
                    if downloading || isApplying {
                        ProgressView().tint(EagleVisualTheme.actionText)
                    } else {
                        Image(systemName: !manager.dsready
                            ? "lock.shield.fill"
                            : (active ? "arrow.clockwise" : "arrow.down.circle.fill"))
                    }
                    Text(!manager.dsready
                        ? LaraL10n.text(en: "Prepare to apply", es: "Preparar para aplicar")
                        : (active
                            ? LaraL10n.text(en: "Reapply \(theme.localizedTitle)", es: "Reaplicar \(theme.localizedTitle)")
                            : LaraL10n.text(en: "Apply \(theme.localizedTitle)", es: "Aplicar \(theme.localizedTitle)")))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(EagleApplyButtonStyle(busy: downloading || isApplying))

            if active && manager.dsready {
                Button(role: .destructive) {
                    restore()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel(LaraL10n.text(
                    en: "Remove Dock theme",
                    es: "Quitar tema del Dock"
                ))
            }
        }
        .disabled(isApplying || remoteGallery.downloadingID != nil)
        .animation(.none, value: theme.id)
    }

    private var selectedRemoteTheme: RemoteDockGalleryTheme? {
        EagleDockGallerySelection.selected(in: visibleRemoteThemes, selectedID: selectedRemoteID)
    }

    private var visibleRemoteThemes: [RemoteDockGalleryTheme] {
        let favorites = favoriteIDs
        return EagleDockGalleryCollection.visible(
            themes: remoteGallery.themes,
            orderedIDs: shuffledRemoteIDs,
            filter: mediaFilter,
            favorites: favorites
        )
    }

    private var favoriteIDs: Set<String> {
        EagleDockGalleryFavorites.decode(favoriteIDsJSON)
    }

    private func toggleFavorite(_ theme: RemoteDockGalleryTheme) {
        EagleDockGalleryInteractions.toggleFavorite(
            theme,
            readFavorites: { favoriteIDs },
            writeFavoritesJSON: { favoriteIDsJSON = $0 },
            synchronize: { synchronizeRemoteSelection() },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }

    private func selectMediaFilter(_ filter: MediaFilter) {
        EagleDockGalleryInteractions.selectCategory(
            filter,
            readSession: { session },
            writeSession: { session = $0 },
            isApplying: { isApplying },
            downloadingID: { remoteGallery.downloadingID },
            selectedThemeID: { selectedRemoteTheme?.id },
            synchronize: { synchronizeRemoteSelection() },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }

    private func animatedSelectMediaFilter(_ filter: MediaFilter) {
        selectMediaFilter(filter)
    }

    private var mediaFilterControl: some View {
        GalleryFilterBar(
            items: MediaFilter.allCases.map {
                GalleryFilterItem(id: $0.rawValue, title: $0.title, icon: $0.icon)
            },
            selectedID: mediaFilter.rawValue,
            disabled: isApplying || remoteGallery.downloadingID != nil,
            accessibilityPrefix: "dock"
        ) { id in
            guard let filter = MediaFilter(rawValue: id) else { return }
            animatedSelectMediaFilter(filter)
        }
    }

    private func beginGalleryVisit() {
        EagleDockGalleryInteractions.beginVisit(
            readSession: { session },
            writeSession: { session = $0 },
            synchronize: { synchronizeRemoteSelection() }
        )
    }

    private func synchronizeRemoteSelection() {
        EagleDockGallerySynchronization.synchronize(
            catalog: { remoteGallery.themes },
            readSession: { session },
            writeSession: { session = $0 },
            shuffle: { $0.shuffled() },
            lastViewedStaticID: { lastViewedStaticID },
            lastViewedLiveID: { lastViewedLiveID },
            visibleThemes: { visibleRemoteThemes },
            rememberViewedTheme: { rememberViewedTheme() }
        )
    }

    private func rememberViewedTheme() {
        guard let lastViewed = EagleDockGallerySelection.lastViewed(selectedRemoteTheme) else { return }
        switch lastViewed {
        case .live(let id):
            lastViewedLiveID = id
        case .still(let id):
            lastViewedStaticID = id
        }
    }

    private var collectionHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.fill.on.rectangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(LaraL10n.text(en: "Choose your Dock", es: "Elige tu Dock"))
                    .font(.headline)
                Text(LaraL10n.text(
                    en: "\(remoteGallery.themes.count) styles available",
                    es: "\(remoteGallery.themes.count) estilos disponibles"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                Task { await remoteGallery.load(force: true) }
            } label: {
                // Turns while the collection refreshes (from the clock, so it really stops at the end).
                EagleAmbientTimeline(paused: !remoteGallery.loading) { context in
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .rotationEffect(.degrees(remoteGallery.loading
                            ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
                            : 0))
                }
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(EaglePressableStyle())
            .disabled(remoteGallery.loading)
            .accessibilityLabel(LaraL10n.text(en: "Refresh collection", es: "Actualizar colección"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // On its own opaque surface, like the filters below it, so it reads over the light top of the
        // backdrop as well as over the dark.
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var remotePositionText: String {
        let themes = visibleRemoteThemes
        let current = EagleDockGallerySelection.currentIndex(in: themes, selectedID: selectedRemoteID)
        return String(format: "%02d", current + 1) + " / " + String(format: "%02d", themes.count)
    }

    private func remoteArrowButton(symbol: String, step: Int) -> some View {
        Button {
            animatedStepRemote(step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(EaglePressableStyle())
        .disabled(isApplying || remoteGallery.downloadingID != nil || visibleRemoteThemes.count < 2)
        .accessibilityLabel(step < 0
            ? LaraL10n.text(en: "Previous theme", es: "Tema anterior")
            : LaraL10n.text(en: "Next theme", es: "Tema siguiente"))
    }

    private func stepRemote(_ step: Int) {
        EagleDockGalleryInteractions.step(
            step,
            readSession: { session },
            writeSession: { session = $0 },
            isApplying: { isApplying },
            downloadingID: { remoteGallery.downloadingID },
            visibleThemes: { visibleRemoteThemes },
            rememberViewedTheme: { rememberViewedTheme() },
            feedback: { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        )
    }

    private func animatedStepRemote(_ step: Int) {
        stepRemote(step)
    }

    @ViewBuilder
    private func artworkPreview(_ style: DockGalleryStyle) -> some View {
        if style.isAnimated {
            TimelineView(.animation(
                minimumInterval: 1.0 / 6.0,
                paused: reduceMotion
            )) { context in
                Image(reduceMotion ? style.assetName : style.previewAsset(at: context.date))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        } else {
            Image(style.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    // MARK: - Carousel

    private var currentStyle: DockGalleryStyle {
        DockGalleryStyle(rawValue: selectedRaw) ?? .bubblegum
    }

    private var hasVerifiedDock: Bool {
        EagleStoredThemeValues.flags(activeFlagsRaw) & (1 << 5) != 0
    }

    private var currentIndex: Int {
        DockGalleryStyle.allCases.firstIndex(of: currentStyle) ?? 0
    }

    private var carousel: some View {
        VStack(spacing: 16) {
            themeCard(currentStyle)

            navigationRow
        }
    }

    private var navigationRow: some View {
        HStack(spacing: 16) {
            arrowButton(symbol: "chevron.left", step: -1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(DockGalleryStyle.allCases) { style in
                    let isCurrent = style == currentStyle
                    Circle()
                        .fill(isCurrent ? Color.primary : Color.primary.opacity(0.22))
                        .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 8 : 6)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: currentStyle)

            Spacer(minLength: 8)

            arrowButton(symbol: "chevron.right", step: 1)
        }
        .padding(.horizontal, 4)
    }

    private func arrowButton(symbol: String, step delta: Int) -> some View {
        Button {
            step(delta)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(EaglePressableStyle())
        .disabled(isApplying)
        .accessibilityLabel(delta < 0
            ? LaraL10n.text(en: "Previous theme", es: "Tema anterior")
            : LaraL10n.text(en: "Next theme", es: "Tema siguiente"))
    }

    private func step(_ delta: Int) {
        let all = DockGalleryStyle.allCases
        guard !all.isEmpty else { return }
        let next = (currentIndex + delta + all.count) % all.count
        selectedRaw = all[next].rawValue
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func apply(_ style: DockGalleryStyle) {
        EagleDockGalleryBuiltInApplyFlow.start(
            style,
            isApplying: { isApplying },
            selectStyle: { selectedRaw = $0 },
            setApplying: { isApplying = $0 },
            intensity: { glowIntensity },
            apply: {
                let result = await DockGalleryExecutor.shared.apply($0, intensity: $1)
                return EagleDockGalleryOutcome(succeeded: result.succeeded, message: result.message)
            },
            successFeedback: { UINotificationFeedbackGenerator().notificationOccurred(.success) },
            notify: { EagleNotifications.shared.result($0, title: "Dock Gallery", message: $1) }
        )
    }

    private func applyRemote(_ theme: RemoteDockGalleryTheme) {
        EagleDockGalleryApplyFlow.start(
            theme,
            isApplying: { isApplying },
            downloadingID: { remoteGallery.downloadingID },
            intensity: { glowIntensity },
            setApplying: { isApplying = $0 },
            prepare: { try await remoteGallery.prepare($0) },
            apply: {
                await EagleDockGalleryCore(port: CurrentDockGalleryPort()).applyRemote($0)
            },
            successFeedback: { UINotificationFeedbackGenerator().notificationOccurred(.success) },
            notify: { EagleNotifications.shared.result($0, title: "Dock Gallery", message: $1) },
            preparationFailureMessage: {
                LaraL10n.text(
                    en: "The original theme package could not be downloaded or verified. Nothing changed.",
                    es: "No se pudo descargar o verificar el paquete original. Nada cambió."
                )
            }
        )
    }

    private func restore() {
        EagleDockGalleryRestoreFlow.start(
            isApplying: { isApplying },
            setApplying: { isApplying = $0 },
            restore: { await EagleDockGalleryCore(port: CurrentDockGalleryPort()).restore() },
            successFeedback: { UINotificationFeedbackGenerator().notificationOccurred(.success) },
            notify: { EagleNotifications.shared.result($0, title: "Dock Gallery", message: $1) }
        )
    }

    private static func remoteID(forLegacyMode mode: Int) -> String? {
        EagleDockGalleryStoredSelection.remoteID(forLegacyMode: mode)
    }
}
