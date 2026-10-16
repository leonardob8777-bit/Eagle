import SwiftUI
import UIKit
import Combine

private struct HideSurfacesNotice: Identifiable {
    let id = UUID()
    let message: String
    var offersRespring = false
}

private final class EagleDockRecipeWork: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var mayContinue: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
}

private struct EagleDockBackgroundResult {
    let succeeded: Bool
    let message: String
    var offersRespring = false
}

@MainActor
private final class EagleDockBackgroundController: ObservableObject {
    static let shared = EagleDockBackgroundController()
    private let manager = laramgr.shared
    @Published private(set) var hidden = false
    @Published private(set) var needsRecovery = false
    private var operationInProgress = false
    private var work: EagleDockRecipeWork?
    private init() {}

    private var recipes: EagleDockRecipes {
        let raw = "\(devicemachine())-\(eagleSystemBuild() ?? "unknown")"
        let identity = raw.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return EagleDockRecipes(
            directory: EagleDockRecipes.systemDirectory,
            backupDirectory: URL.documents.appendingPathComponent("EagleDockBackgroundBackup"),
            identity: identity
        )
    }

    func setHidden(_ requested: Bool) async -> EagleDockBackgroundResult {
        guard !operationInProgress, !manager.fileopinprogress,
              !manager.dsrunning, !manager.rcrunning, !manager.vfsrunning, !manager.sbxrunning,
              UIApplication.shared.applicationState == .active else {
            return failure(en: "Wait for the current operation and return to Eagle.",
                           es: "Espera a que termine la operación y vuelve a Eagle.")
        }
        guard manager.dsready, manager.hasOffsets,
              (17...18).contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) else {
            return failure(en: "Prepare Eagle access first. Requires compatible iOS 17–18.",
                           es: "Prepara el acceso de Eagle. Requiere iOS 17–18 compatible.")
        }
        operationInProgress = true
        manager.fileopinprogress = true
        let token = EagleDockRecipeWork()
        work = token
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Dock recipes") { token.cancel() }
        defer {
            work = nil
            manager.fileopinprogress = false
            operationInProgress = false
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        let operationID = String(UUID().uuidString.prefix(8))
        globallogger.log("(eagle.dock.recipe) op=\(operationID) stage=prepare hidden=\(requested)")
        globallogger.flushToDisk()
        if !manager.vfsready {
            let ready: Bool = await withCheckedContinuation { continuation in
                manager.vfsinit { continuation.resume(returning: $0) }
            }
            guard ready else {
                return failure(en: "VFS preparation failed. Dock files were not changed.",
                               es: "Falló la preparación de VFS. No se cambiaron los archivos del Dock.")
            }
        }
        guard token.mayContinue, UIApplication.shared.applicationState == .active,
              manager.dsready, manager.vfsready else {
            return failure(en: "Dock update cancelled before writing.",
                           es: "Actualización del Dock cancelada antes de escribir.")
        }
        let engine = recipes
        let vfsManager = manager
        globallogger.log("(eagle.dock.recipe) op=\(operationID) stage=write.begin")
        globallogger.flushToDisk()
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result {
                    try engine.setHidden(requested, shouldContinue: { token.mayContinue }) { path, data in
                        // Use the public release's VFS primitive directly. Do
                        // not attempt an O_TRUNC sandbox write on system files.
                        vfsManager.vfsoverwritewithdata(target: path, data: data)
                    }
                }
                continuation.resume(returning: result)
            }
        }
        refreshDiskState()
        globallogger.log("(eagle.dock.recipe) op=\(operationID) stage=write.end result=\(result)")
        globallogger.flushToDisk()
        switch result {
        case .success:
            UserDefaults.standard.set(hidden, forKey: "eagle.dock.backgroundRecipeHidden")
            return EagleDockBackgroundResult(
                succeeded: true,
                message: LaraL10n.text(
                    en: "Dock files verified. Respring to refresh the system background.",
                    es: "Archivos del Dock verificados. Haz respring para actualizar el fondo del sistema."),
                offersRespring: true)
        case .failure(let error):
            return failure(en: "Dock update failed: \(error.localizedDescription)",
                           es: "No se pudo actualizar el Dock: \(error.localizedDescription)")
        }
    }

    private func failure(en: String, es: String) -> EagleDockBackgroundResult {
        EagleDockBackgroundResult(succeeded: false, message: LaraL10n.text(en: en, es: es))
    }

    private func refreshDiskState() {
        do {
            let state = try recipes.state()
            hidden = state == .hidden
            needsRecovery = state == .mixed
            UserDefaults.standard.set(hidden, forKey: "eagle.dock.backgroundRecipeHidden")
        } catch {
            hidden = false
            needsRecovery = true
        }
    }

    func reconcileProcessIdentity() {
        guard !operationInProgress, !manager.dsrunning, !manager.vfsrunning, !manager.rcrunning else { return }
        refreshDiskState()
    }

    func cancelPendingWork() { work?.cancel() }
}

struct HideDockIslandView: View {
    @ObservedObject private var mgr = laramgr.shared
    @StateObject private var dockBackgroundController = EagleDockBackgroundController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var notice: HideSurfacesNotice?
    @State private var systemIslandSuppressed = false
    @State private var isReadingSystemIslandSetting = false
    @State private var isUpdatingDockBackground = false
    @State private var isUpdatingIslandSetting = false
    @State private var islandReadFailed = false
    @State private var showAccess = false
    private let springBoardPreferencesPath =
        "/var/Managed Preferences/mobile/com.apple.springboard.plist"
    private let suppressSystemIslandKey = "SBSuppressDynamicIslandCompletely"
    private var busy: Bool { isUpdatingDockBackground || isUpdatingIslandSetting }
    private var islandSupported: Bool {
        EagleDynamicIslandCompatibility.current.canAttemptLiveIslandAura
    }
    private var dockSupported: Bool {
        (17...18).contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                systemIslandCard
                if dockBackgroundController.needsRecovery {
                    Button(LaraL10n.text(en: "Restore Dock", es: "Restaurar Dock")) {
                        updateDockBackgroundVisibility(false)
                    }
                    .disabled(!mgr.dsready || !mgr.hasOffsets)
                }
                if !mgr.dsready {
                    Button { showAccess = true } label: {
                        Label(LaraL10n.text(en: "Prepare Eagle", es: "Preparar Eagle"),
                              systemImage: "lock.shield.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    // The contrasting colour on the black/white fill, grey while disabled.
                    .eagleProminentLabel()
                }
                if islandReadFailed {
                    Button(LaraL10n.text(en: "Retry Island status", es: "Reintentar estado de Island")) {
                        readSystemIslandSetting()
                    }
                }
                if busy { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(20)
            .disabled(busy)
        }
        .eagleScreenBackdrop()
        .navigationTitle("Hide Dock + Island")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .sheet(isPresented: $showAccess) {
            NavigationStack {
                ScrollView { LaraAccessView(compact: true) { showAccess = false }.padding(20) }
                    .navigationTitle(LaraL10n.text(en: "Prepare Eagle", es: "Preparar Eagle"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(LaraL10n.text(en: "Done", es: "Listo")) { showAccess = false }
                        }
                    }
            }
        }
        .onChange(of: notice?.id) { _ in
            guard let value = notice, !value.offersRespring else { return }
            EagleNotifications.shared.show(title: "Hide Dock + Island", message: value.message)
            notice = nil
        }
        .alert(item: Binding(get: { notice?.offersRespring == true ? notice : nil }, set: { notice = $0 })) { notice in
            if notice.offersRespring {
                return Alert(title: Text("Hide Dock + Island"), message: Text(notice.message),
                    primaryButton: .default(Text(LaraL10n.text(en: "Respring now", es: "Respring ahora"))) {
                        mgr.respring()
                    }, secondaryButton: .cancel(Text(LaraL10n.text(en: "Later", es: "Después"))))
            }
            return Alert(title: Text("Hide Dock + Island"), message: Text(notice.message),
                         dismissButton: .default(Text("OK")))
        }
        .onAppear { refreshState() }
        .onChange(of: mgr.sbxready) { _ in refreshState() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshState() }
            else { dockBackgroundController.cancelPendingWork() }
        }
    }

    private func refreshState() {
        guard !busy else { return }
        reconcileDockBackgroundState()
        readSystemIslandSetting()
    }

    private var systemIslandCard: some View {
        VStack(spacing: 0) {
            systemIslandRow

            Divider()
                .padding(.leading, 62)

            dockBackgroundRow
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var systemIslandRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(LaraL10n.text(
                    en: "Hide system Island",
                    es: "Ocultar Island del sistema"
                ))
                .font(.subheadline.weight(.semibold))
                Text(!islandSupported
                     ? LaraL10n.text(en: "Unavailable on this device", es: "No disponible en este dispositivo")
                     : mgr.sbxready
                     ? LaraL10n.text(en: "Requires respring", es: "Requiere respring")
                     : LaraL10n.text(en: "Prepare access first", es: "Prepara el acceso primero"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { systemIslandSuppressed },
                set: updateSystemIslandSuppression
            ))
            .labelsHidden()
            .accessibilityLabel(LaraL10n.text(en: "Hide system Island", es: "Ocultar Island del sistema"))
            .disabled(
                !islandSupported || islandReadFailed || !mgr.sbxready || isReadingSystemIslandSetting ||
                isUpdatingIslandSetting || isUpdatingDockBackground
            )
        }
        .padding(14)
    }

    private var dockBackgroundRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(LaraL10n.text(
                    en: "Hide Dock background",
                    es: "Ocultar fondo del Dock"
                ))
                .font(.subheadline.weight(.semibold))
                Text(!dockSupported
                     ? LaraL10n.text(en: "Requires iOS 17–18", es: "Requiere iOS 17–18")
                     : mgr.dsready
                     ? LaraL10n.text(en: "Requires respring", es: "Requiere respring")
                     : LaraL10n.text(en: "Prepare access first", es: "Prepara el acceso primero"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isUpdatingDockBackground {
                ProgressView()
                    .accessibilityLabel(LaraL10n.text(en: "Updating Dock", es: "Actualizando Dock"))
            }

            Toggle("", isOn: Binding(
                get: { dockBackgroundController.hidden },
                set: updateDockBackgroundVisibility
            ))
            .labelsHidden()
            .accessibilityLabel(LaraL10n.text(en: "Hide Dock background", es: "Ocultar fondo del Dock"))
            .disabled(
                !dockSupported || !mgr.dsready || !mgr.hasOffsets || mgr.dsrunning || mgr.rcrunning ||
                mgr.vfsrunning || mgr.fileopinprogress || scenePhase != .active ||
                isUpdatingIslandSetting || isUpdatingDockBackground
            )
        }
        .padding(14)
    }

    private func updateDockBackgroundVisibility(_ enabled: Bool) {
        guard !isUpdatingIslandSetting, !isUpdatingDockBackground else { return }
        guard mgr.dsready else {
            notice = HideSurfacesNotice(message: LaraL10n.text(
                en: "Prepare Eagle access before changing the Dock background.",
                es: "Prepara el acceso de Eagle antes de cambiar el fondo del Dock."
            ))
            return
        }

        isUpdatingDockBackground = true
        Task { @MainActor in
            let result = await EagleDockBackgroundController.shared.setHidden(enabled)
            isUpdatingDockBackground = false
            if result.succeeded {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if result.offersRespring {
                notice = HideSurfacesNotice(message: result.message, offersRespring: true)
            } else {
                EagleNotifications.shared.result(result.succeeded, title: "Hide Dock", message: result.message)
            }
        }
    }

    private func reconcileDockBackgroundState() {
        dockBackgroundController.reconcileProcessIdentity()
    }

    private func readSystemIslandSetting() {
        islandReadFailed = false
        guard mgr.sbxready else {
            systemIslandSuppressed = false
            return
        }
        // Lara treats an absent SpringBoard preferences domain as the
        // setting's normal default (`false`). Some devices have never created
        // this plist, so opening this screen must not show an error alert.
        guard FileManager.default.fileExists(
            atPath: springBoardPreferencesPath
        ) else {
            systemIslandSuppressed = false
            return
        }
        isReadingSystemIslandSetting = true
        defer { isReadingSystemIslandSetting = false }
        let result = mgr.getplistvalue(
            path: springBoardPreferencesPath,
            key: suppressSystemIslandKey
        )
        guard result.ok else {
            systemIslandSuppressed = false
            if !result.message.hasPrefix("key ") {
                islandReadFailed = true
                notice = HideSurfacesNotice(message: result.message)
            }
            return
        }
        guard let value = plistBoolean(result.value) else {
            islandReadFailed = true
            systemIslandSuppressed = false
            notice = HideSurfacesNotice(message: LaraL10n.text(
                en: "Could not read \(suppressSystemIslandKey) as a Boolean value.",
                es: "No se pudo leer \(suppressSystemIslandKey) como un valor booleano."
            ))
            return
        }
        systemIslandSuppressed = value
    }

    private func updateSystemIslandSuppression(_ enabled: Bool) {
        guard !busy, !isReadingSystemIslandSetting, !islandReadFailed,
              islandSupported, UIApplication.shared.applicationState == .active else { return }
        isUpdatingIslandSetting = true
        defer { isUpdatingIslandSetting = false }
        guard mgr.sbxready else {
            systemIslandSuppressed = false
            notice = HideSurfacesNotice(message: LaraL10n.text(
                en: "Prepare Eagle access before changing the system Island setting.",
                es: "Prepara el acceso de Eagle antes de cambiar el ajuste de la Island del sistema."
            ))
            return
        }
        if !enabled,
           !FileManager.default.fileExists(atPath: springBoardPreferencesPath) {
            // Missing domain already means the original system behavior. Do
            // not create an empty protected plist merely to switch it off.
            systemIslandSuppressed = false
            return
        }
        let previousValue = systemIslandSuppressed
        // Snapshot the stored value (including an absent key) before writing.
        let original = mgr.getplistvalue(path: springBoardPreferencesPath, key: suppressSystemIslandKey)
        guard original.ok || original.message.hasPrefix("key ") ||
                !FileManager.default.fileExists(atPath: springBoardPreferencesPath) else {
            islandReadFailed = true
            notice = HideSurfacesNotice(message: original.message)
            return
        }
        guard original.value == nil || plistBoolean(original.value) != nil else {
            islandReadFailed = true
            notice = HideSurfacesNotice(message: LaraL10n.text(
                en: "The stored Island setting is invalid. Nothing changed.",
                es: "El ajuste guardado de Island no es válido. Nada cambió."))
            return
        }
        let result = mgr.setplistvalue(
            path: springBoardPreferencesPath,
            key: (suppressSystemIslandKey, enabled ? true : nil),
            force: true
        )
        let verification = mgr.getplistvalue(
            path: springBoardPreferencesPath,
            key: suppressSystemIslandKey
        )
        let verified: Bool
        if verification.ok, let storedValue = plistBoolean(verification.value) {
            verified = storedValue == enabled
        } else {
            verified = !enabled &&
                (!FileManager.default.fileExists(atPath: springBoardPreferencesPath) ||
                 (verification.value == nil && verification.message.hasPrefix("key ")))
        }
        guard result.ok && verified else {
            let rollback = mgr.setplistvalue(path: springBoardPreferencesPath,
                key: (suppressSystemIslandKey, original.value), force: true)
            let restored = mgr.getplistvalue(path: springBoardPreferencesPath, key: suppressSystemIslandKey)
            let rollbackVerified = rollback.ok && (original.value == nil
                ? (!restored.ok && restored.message.hasPrefix("key "))
                : (restored.ok && plistBoolean(restored.value) == plistBoolean(original.value)))
            islandReadFailed = !rollbackVerified
            systemIslandSuppressed = previousValue
            notice = HideSurfacesNotice(message: rollbackVerified
                ? LaraL10n.text(en: "The change failed. The previous setting was restored.",
                               es: "El cambio falló. Se restauró el ajuste anterior.")
                : LaraL10n.text(en: "The Island setting could not be verified. Retry its status before another change.",
                               es: "No se pudo verificar el ajuste de Island. Reintenta su estado antes de otro cambio."))
            return
        }

        systemIslandSuppressed = enabled

        notice = HideSurfacesNotice(message: LaraL10n.text(
            en: enabled
                ? "The system Island will be hidden after a respring. To complete the change, manually restart your iPhone once more after the respring. Your Aura profile is unchanged."
                : "The system Island will return after a respring. To complete the change, manually restart your iPhone once more after the respring. Your Aura profile is unchanged.",
            es: enabled
                ? "La Island del sistema se ocultará después de un respring. Para completar el cambio, reinicia manualmente tu iPhone una vez más después del respring. Tu perfil Aura no cambió."
                : "La Island del sistema volverá después de un respring. Para completar el cambio, reinicia manualmente tu iPhone una vez más después del respring. Tu perfil Aura no cambió."
        ), offersRespring: true)
    }

    private func plistBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

}
