//
//  SettingsView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum method: String, CaseIterable {
    case vfs = "VFS"
    case sbx = "SBX"
    case hybrid = "Hybrid"
}

enum fmAppsDisplayMode: String, CaseIterable {
    case UUID = "UUID"
    case bundleID = "Bundle ID"
    case appName = "App Name"
}

enum logsdisplaymode: String, CaseIterable {
    case tabs = "In Tabs"
    case toolbar = "In Toolbar"
    case content = "Directly in ContentView"
}

/// Subtle press feedback for custom card-style buttons (e.g. the developer card).
/// Honors Reduce Motion by dropping the scale transform and animation.
private struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: configuration.isPressed
            )
    }
}

enum SettingsDestination {
    case preferences
    case laboratory
}

struct LaboratoryToolsView: View {
    var body: some View {
        SettingsView(destination: .laboratory)
    }
}

struct SettingsView: View {
    var destination: SettingsDestination = .preferences
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var mgr: laramgr
    @AppStorage(EagleReleaseChannel.storageKey)
    private var channelRaw = EagleReleaseChannel.stable.rawValue
    @AppStorage(EagleAppearanceMode.storageKey)
    private var appearanceModeRaw = EagleAppearanceMode.dark.rawValue
    
    @AppStorage(EaglePreferenceKeys.accessMethod) private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepAlive: Bool = false
    @AppStorage("stashKRW") private var stashKRW: Bool = false
    @AppStorage("keepSpringBoardRemoteCallAliveIOS16") private var keepSpringBoardRemoteCallAliveIOS16: Bool = false
    
    @State private var dlingkcache: Bool = false
    @State private var showkcacheimport: Bool = false
    @State private var importingkcache: Bool = false
    @State private var showkcachetips: Bool = false
    @State private var stashingKRWNow: Bool = false
    
    @AppStorage(EaglePreferenceKeys.disableLogDividers) private var loggerNoBS: Bool = true
    
    @AppStorage("showFMInTabs") private var showFMInTabs: Bool = true
    @AppStorage("selectedFMAppsDisplayMode") private var selectedFMAppsDisplayMode: fmAppsDisplayMode = .appName
    @AppStorage("fmRecursiveSearch") private var fmRecursiveSearch: Bool = false
    
    @AppStorage("rcDockUnlimited") private var rcDockUnlimited: Bool = false

    private var channel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: channelRaw)
    }

    private var advancedToolsAllowed: Bool {
        EagleFeaturePolicy.allows(.advancedSystemTools, channel: channel)
    }

    @AppStorage(LaraLanguage.storageKey) private var language = LaraLanguage.english
    @State private var showingTelegram = false
    @AppStorage(EagleBackdrop.storageKey) private var backdropEnabled = true

    private var discordFooter: Text {
        Text(LocalizedStringKey(LaraL10n.text(
            en: "Deleting and fetching the kernelcache again may fix some issues. Try this before asking for help on [Discord](https://discord.gg/gw8PcRF3Jr).",
            es: "Borrar y volver a obtener el kernelcache puede resolver algunos problemas. Pruébalo antes de pedir ayuda en [Discord](https://discord.gg/gw8PcRF3Jr)."
        )))
    }

    /// Eagle and its creator in one card: the app with its version, then the link to Leonardo's GitHub.
    private var identityCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppIcon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.appName)
                        .font(.title3.weight(.semibold))
                    Text(LaraL10n.text(
                        en: "Version \(AppInfo.appVersion) (\(AppInfo.appBuild))",
                        es: "Versión \(AppInfo.appVersion) (\(AppInfo.appBuild))"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)

            Divider().padding(.leading, 16)

            Link(destination: URL(string: "https://github.com/leonardob8777-bit")!) {
                HStack(spacing: 12) {
                    Image("LeonardoAvatar")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LaraL10n.text(en: "Made by Leonardo", es: "Hecho por Leonardo"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("@leonardob8777-bit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LaraL10n.text(
                en: "Leonardo, creator of Eagle. Opens GitHub profile.",
                es: "Leonardo, creador de Eagle. Abre el perfil de GitHub."
            ))
            .accessibilityAddTraits(.isLink)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var laboratoryIntro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: "testtube.2", size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LaraL10n.text(en: "System laboratory", es: "Laboratorio del sistema"))
                        .font(.headline)
                    Text("Kernelcache · Offsets · RemoteCall")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                laboratoryStatus(LaraL10n.text(en: "Access", es: "Acceso"), ready: mgr.dsready)
                laboratoryStatus("Offsets", ready: mgr.hasOffsets)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func laboratoryStatus(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ready ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.primary : Color.secondary)
            Text(ready
                 ? LaraL10n.text(en: "Ready", es: "Listo")
                 : LaraL10n.text(en: "Not ready", es: "Sin preparar"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    var body: some View {
        NavigationStack {
            List {
                if destination == .preferences {
                    preferencesSections
                } else {
                    laboratorySections
                }
            }
            // Settings and Laboratory Tools are always pure black, whatever the app's appearance.
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(Color.black, for: .navigationBar)
            .navigationTitle(destination == .laboratory
                ? LaraL10n.text(en: "Laboratory Tools", es: "Herramientas de Laboratorio")
                : LaraL10n.text(en: "Settings", es: "Ajustes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(LaraL10n.text(en: "Close", es: "Cerrar"))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingTelegram) {
                TelegramSafariView(url: EagleLinks.telegram)
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showkcacheimport, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importingkcache = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        var ok = false
                        let shouldStopAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if shouldStopAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        let fm = FileManager.default
                        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let dest = docs.appendingPathComponent("kernelcache")
                            do {
                                if fm.fileExists(atPath: dest.path) {
                                    try fm.removeItem(at: dest)
                                }
                                try fm.copyItem(at: url, to: dest)
                                ok = dlkcache()
                            } catch {
                                print("failed to import kernelcache: \(error)")
                                ok = false
                            }
                        }
                        DispatchQueue.main.async {
                            mgr.hasOffsets = ok
                            importingkcache = false
                        }
                    }
                case .failure:
                    break
                }
            }
        }
        // Applies to this sheet only, not to the rest of Eagle.
        .preferredColorScheme(.dark)
    }

    // MARK: - Settings

    @ViewBuilder
    private var preferencesSections: some View {
        Section {
            identityCard
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
        }

        Section {
            Picker(selection: $language) {
                ForEach(LaraLanguage.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            } label: {
                SettingsRowLabel(LaraL10n.text(en: "Language", es: "Idioma"), systemImage: "globe")
            }
            .pickerStyle(.menu)

            Picker(selection: $appearanceModeRaw) {
                ForEach(EagleAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                SettingsRowLabel(LaraL10n.text(en: "Appearance", es: "Apariencia"), systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)

            // The Eagle background, moved here from Access. From a sheet there is no switch on the
            // screen to open the circle from, so the background simply fades in or out.
            Toggle(isOn: Binding(
                get: { backdropEnabled },
                set: { on in
                    EagleBackdrop.toggleOrigin = nil
                    withAnimation(.easeInOut(duration: EagleBackdrop.toggleDuration)) { backdropEnabled = on }
                }
            )) {
                SettingsRowLabel(LaraL10n.text(en: "Eagle background", es: "Fondo Eagle"), systemImage: "photo.fill.on.rectangle.fill")
            }

            Toggle(isOn: $keepAlive) {
                SettingsRowLabel(LaraL10n.text(en: "Keep Alive", es: "Mantener activa"), systemImage: "bolt.fill")
            }
            .onChange(of: keepAlive) { _ in
                if keepAlive {
                    if !kaenabled { toggleka() }
                } else {
                    if kaenabled { toggleka() }
                }
            }
        } header: {
            Text(LaraL10n.text(en: "General", es: "General"))
        } footer: {
            Text(LaraL10n.text(
                en: "Keep Alive lets Eagle keep working while it is in the background.",
                es: "Mantener activa permite que Eagle siga funcionando en segundo plano."
            ))
        }

        Section {
            NavigationLink(destination: EagleCompatibilityCenterView()) {
                SettingsRowLabel(LaraL10n.text(en: "Compatibility", es: "Compatibilidad"), systemImage: "checkmark.shield.fill")
            }
            LabeledContent {
                Text(channel.title)
            } label: {
                SettingsRowLabel(LaraL10n.text(en: "Feature channel", es: "Canal de funciones"), systemImage: "slider.horizontal.3")
            }
            NavigationLink(destination: CreditsView()) {
                SettingsRowLabel(LaraL10n.text(en: "Credits", es: "Créditos"), systemImage: "heart.fill")
            }
        } header: {
            Text("Eagle")
        } footer: {
            if !advancedToolsAllowed {
                Text(LaraL10n.text(
                    en: "Kernelcache and RemoteCall controls require the Laboratory channel.",
                    es: "Los controles de Kernelcache y RemoteCall requieren el canal Laboratorio."
                ))
            }
        }

        Section {
            Toggle(isOn: $loggerNoBS) {
                SettingsRowLabel(LaraL10n.text(en: "Hide log dividers", es: "Ocultar separadores del registro"), systemImage: "text.alignleft")
            }
            .onChange(of: loggerNoBS) { disabled in
                EaglePreferenceMigration.persistDisableLogDividers(disabled)
            }

            if advancedToolsAllowed {
                Picker(selection: $selectedFMAppsDisplayMode) {
                    ForEach(fmAppsDisplayMode.allCases, id: \.self) { mode in
                        Text(fileManagerModeTitle(mode)).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(LaraL10n.text(en: "App folders shown as", es: "Carpetas de apps como"), systemImage: "folder.fill")
                }
                .pickerStyle(.menu)
                Toggle(isOn: $fmRecursiveSearch) {
                    SettingsRowLabel(LaraL10n.text(en: "Search inside folders", es: "Buscar dentro de carpetas"), systemImage: "magnifyingglass")
                }
                Toggle(isOn: $showFMInTabs) {
                    SettingsRowLabel(LaraL10n.text(en: "File Manager in tabs", es: "Archivos en las pestañas"), systemImage: "rectangle.split.3x1.fill")
                }
            }
        } header: {
            Text(LaraL10n.text(en: "Advanced", es: "Avanzado"))
        }

        // The same Telegram button as the welcome, closing the list.
        Section {
            EagleTelegramButton { showingTelegram = true }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
        }
    }

    private func fileManagerModeTitle(_ mode: fmAppsDisplayMode) -> String {
        switch mode {
        case .UUID: return "UUID"
        case .bundleID: return "Bundle ID"
        case .appName: return LaraL10n.text(en: "App name", es: "Nombre de la app")
        }
    }

    // MARK: - Laboratory

    @ViewBuilder
    private var laboratorySections: some View {
        Section {
            laboratoryIntro
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
        }

        if !advancedToolsAllowed {
            Section {
                Label(
                    LaraL10n.text(
                        en: "Choose the Laboratory channel on Customize to use these tools.",
                        es: "Elige el canal Laboratorio en Personalizar para usar estas herramientas."
                    ),
                    systemImage: "lock.fill"
                )
                .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Picker(
                    LaraL10n.text(en: "Access method", es: "Método de acceso"),
                    selection: $selectedMethod
                ) {
                    ForEach(method.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(LaraL10n.text(en: "Access method", es: "Método de acceso"))
                .onChange(of: selectedMethod) { newValue in
                    EaglePreferenceMigration.persistAccessMethod(newValue.rawValue)
                }

                NavigationLink(destination: OffsetManagementView()) {
                    SettingsRowLabel(LaraL10n.text(en: "Modify offsets", es: "Modificar offsets"), systemImage: "list.number")
                }
            } header: {
                Text(LaraL10n.text(en: "Access", es: "Acceso"))
            }

            Section {
                if !mgr.hasOffsets {
                    Button {
                        guard !dlingkcache else { return }
                        dlingkcache = true

                        DispatchQueue.global(qos: .userInitiated).async {
                            let fetched = fetchkcache()

                            if fetched {
                                let dlkc = dlkcache()
                                DispatchQueue.main.async {
                                    mgr.hasOffsets = dlkc
                                    dlingkcache = false
                                }
                                return
                            }

                            DispatchQueue.main.async {
                                mgr.hasOffsets = false
                                dlingkcache = false
                            }
                        }
                    } label: {
                        HStack {
                            SettingsRowLabel(
                                dlingkcache
                                    ? LaraL10n.text(en: "Fetching kernelcache…", es: "Obteniendo kernelcache…")
                                    : LaraL10n.text(en: "Fetch kernelcache", es: "Obtener kernelcache"),
                                systemImage: "arrow.down.circle.fill"
                            )
                            Spacer()
                            if dlingkcache { ProgressView() }
                        }
                    }
                    .disabled(dlingkcache || !mgr.dsready)

                    Button {
                        guard !importingkcache else { return }
                        showkcacheimport = true
                    } label: {
                        HStack {
                            SettingsRowLabel(
                                importingkcache
                                    ? LaraL10n.text(en: "Importing kernelcache…", es: "Importando kernelcache…")
                                    : LaraL10n.text(en: "Import kernelcache", es: "Importar kernelcache"),
                                systemImage: "square.and.arrow.down.fill"
                            )
                            Spacer()
                            if importingkcache { ProgressView() }
                        }
                    }
                    .disabled(dlingkcache || importingkcache)

                    DisclosureGroup(isExpanded: $showkcachetips) {
                        kernelcacheSteps
                    } label: {
                        SettingsRowLabel(LaraL10n.text(en: "How to get a kernelcache", es: "Cómo obtener un kernelcache"), systemImage: "questionmark.circle.fill")
                    }
                } else {
                    Button(role: .destructive) {
                        Alertinator.shared.alert(
                            title: LaraL10n.text(en: "Clear kernelcache data?", es: "¿Borrar los datos del kernelcache?"),
                            body: LaraL10n.text(
                                en: "This deletes all kernelcache data and saved offsets. You will need to fetch them again to use Eagle.",
                                es: "Se borran todos los datos del kernelcache y los offsets guardados. Tendrás que obtenerlos de nuevo para usar Eagle."
                            ),
                            actionLabel: LaraL10n.text(en: "Delete", es: "Borrar"),
                            action: { clearKcacheData() }
                        )
                    } label: {
                        SettingsRowLabel(LaraL10n.text(en: "Remove kernelcache", es: "Quitar kernelcache"), systemImage: "trash.fill")
                    }
                }
            } header: {
                Text("Kernelcache")
            } footer: {
                if !mgr.hasOffsets && (!mgr.dsready || (!mgr.vfsready && !mgr.sbxready)) {
                    Text(LaraL10n.text(
                        en: "Prepare Eagle before fetching the kernelcache.",
                        es: "Prepara Eagle antes de obtener el kernelcache."
                    )) + Text("\n\n") + discordFooter
                } else {
                    discordFooter
                }
            }

            #if !DISABLE_REMOTECALL
            Section {
                Toggle(isOn: $stashKRW) {
                    SettingsRowLabel(LaraL10n.text(en: "Stash KRW primitives", es: "Guardar primitivas KRW"), systemImage: "archivebox.fill")
                }
                .onChange(of: stashKRW) { enabled in
                    if enabled && isIOS16() {
                        Alertinator.shared.alert(
                            title: LaraL10n.text(en: "iOS 16 warning", es: "Aviso para iOS 16"),
                            body: LaraL10n.text(
                                en: "Saving KRW on iOS 16 is currently unstable. If it fails, stash KRW manually a few more times.",
                                es: "Guardar KRW en iOS 16 todavía es inestable. Si falla, guárdalo manualmente unas cuantas veces más."
                            )
                        )
                    }
                }

                if isIOS16() {
                    Toggle(isOn: $keepSpringBoardRemoteCallAliveIOS16) {
                        SettingsRowLabel(LaraL10n.text(en: "Keep SpringBoard RemoteCall alive", es: "Mantener RemoteCall de SpringBoard"), systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Button {
                        guard !stashingKRWNow else { return }
                        stashingKRWNow = true
                        mgr.stashKRWToLaunchd { success in
                            stashingKRWNow = false
                            if success {
                                Alertinator.shared.alert(
                                    title: LaraL10n.text(en: "KRW stashed", es: "KRW guardado"),
                                    body: LaraL10n.text(
                                        en: "KRW primitives were stashed to launchd.",
                                        es: "Las primitivas KRW se guardaron en launchd."
                                    )
                                )
                            } else {
                                let error = mgr.rcLastError ?? LaraL10n.text(
                                    en: "Try stashing KRW manually a few more times.",
                                    es: "Intenta guardar KRW manualmente unas cuantas veces más."
                                )
                                Alertinator.shared.alert(
                                    title: LaraL10n.text(en: "Could not stash KRW", es: "No se pudo guardar KRW"),
                                    body: error
                                )
                            }
                        }
                    } label: {
                        HStack {
                            SettingsRowLabel(
                                stashingKRWNow
                                    ? LaraL10n.text(en: "Stashing KRW to launchd…", es: "Guardando KRW en launchd…")
                                    : LaraL10n.text(en: "Stash KRW to launchd now", es: "Guardar KRW en launchd ahora"),
                                systemImage: "tray.and.arrow.down.fill"
                            )
                            Spacer()
                            if stashingKRWNow { ProgressView() }
                        }
                    }
                    .disabled(!mgr.dsready || mgr.rcrunning || stashingKRWNow)
                }

                Toggle(isOn: $rcDockUnlimited) {
                    SettingsRowLabel(LaraL10n.text(en: "Allow more than 10 Dock icons", es: "Permitir más de 10 iconos en el Dock"), systemImage: "dock.rectangle")
                }
            } header: {
                Text("RemoteCall")
            } footer: {
                if isIOS16() {
                    Text(LaraL10n.text(
                        en: "If Eagle closes while RemoteCall is active, SpringBoard may respring.",
                        es: "Si Eagle se cierra con RemoteCall activo, SpringBoard puede hacer respring."
                    ))
                    .foregroundStyle(.orange)
                }
            }
            #endif
        }
    }

    private var kernelcacheSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LaraL10n.text(en: "On a Mac:", es: "En un Mac:"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Text(LaraL10n.text(en: "1. Download the IPSW tool.", es: "1. Descarga la herramienta IPSW."))
            Link("github.com/blacktop/ipsw/releases",
                 destination: URL(string: "https://github.com/blacktop/ipsw/releases")!)
            Text(LaraL10n.text(en: "2. Extract it and open Terminal in that folder.", es: "2. Descomprímela y abre Terminal en esa carpeta."))
            Text(LaraL10n.text(en: "3. Extract the kernel:", es: "3. Extrae el kernel:"))
            Text("./ipsw extract --kernel [ipsw]")
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
            Text(LaraL10n.text(
                en: "4. Send the kernelcache file to your iPhone (for example via iCloud) and choose it with Import kernelcache.",
                es: "4. Pasa el archivo kernelcache al iPhone (por ejemplo con iCloud) y elígelo con Importar kernelcache."
            ))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func clearKcacheData() {
        let fm = FileManager.default
        
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_path")
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_size")
        
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let kernelcacheDocPath = docsPath.appendingPathComponent("kernelcache")
        
        do {
            if fm.fileExists(atPath: kernelcacheDocPath.path) {
                try fm.removeItem(at: kernelcacheDocPath)
                mgr.logmsg("Deleted kernelcache from Documents")
            }
        } catch {
            mgr.logmsg("Failed to delete kernelcache: \(error.localizedDescription)")
        }
        
        let tempPath = NSTemporaryDirectory()
        let tempFiles = ["kernelcache.release.ipad", "kernelcache.release.iphone", "kernelcache.release.ipad3", "kernelcache.release.iphone14,3"]
        
        for file in tempFiles {
            let path = tempPath + file
            do {
                if fm.fileExists(atPath: path) {
                    try fm.removeItem(atPath: path)
                    mgr.logmsg("Deleted temp kernelcache: \(file)")
                }
            } catch {
                mgr.logmsg("Failed to delete \(file): \(error.localizedDescription)")
            }
        }
        
        mgr.logmsg("Kernelcache data cleared")
        mgr.hasOffsets = false
    }
}

/// An iOS Settings-style row: a small icon tile and the title.
private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage)
            Text(title)
                .foregroundStyle(.primary)
        }
    }
}

/// Flat tile with the symbol in black or white, like Eagle's own mark.
private struct SettingsIcon: View {
    let systemImage: String
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}
