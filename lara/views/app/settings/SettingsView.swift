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

    private var laboratoryIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "testtube.2")
                    .font(.title2.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LaraL10n.text(en: "System laboratory", es: "Laboratorio del sistema"))
                        .font(.headline)
                    Text("Kernelcache · Offsets · RemoteCall")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                laboratoryStatus(
                    LaraL10n.text(en: "Access", es: "Acceso"),
                    ready: mgr.dsready
                )
                laboratoryStatus(
                    LaraL10n.text(en: "Offsets", es: "Offsets"),
                    ready: mgr.hasOffsets
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private func laboratoryStatus(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ready ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private var developerCard: some View {
        Link(destination: URL(string: "https://github.com/leonardob8777-bit")!) {
            HStack(spacing: 14) {
                Image("LeonardoAvatar")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Leonardo")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(LaraL10n.text(en: "Creator of Eagle", es: "Creador de Eagle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption2.weight(.semibold))
                        Text("@leonardob8777-bit")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LaraL10n.text(
            en: "Leonardo, creator of Eagle. Opens GitHub profile.",
            es: "Leonardo, creador de Eagle. Abre el perfil de GitHub."
        ))
        .accessibilityAddTraits(.isLink)
    }

    var body: some View {
        NavigationStack {
            List {
                if destination == .preferences {
                Section {
                    developerCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 14, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    Picker(
                        LaraL10n.text(en: "Appearance", es: "Apariencia"),
                        selection: $appearanceModeRaw
                    ) {
                        ForEach(EagleAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel(LaraL10n.text(en: "Appearance", es: "Apariencia"))
                } header: {
                    HeaderLabel(
                        text: LaraL10n.text(en: "Appearance", es: "Apariencia"),
                        icon: "circle.lefthalf.filled"
                    )
                } footer: {
                    Text(LaraL10n.text(
                        en: "Dark is the recommended Eagle experience. Light and System remain available.",
                        es: "Oscuro es la experiencia recomendada de Eagle. Claro y Sistema siguen disponibles."
                    ))
                }

                Section(header: HeaderLabel(
                    text: LaraL10n.text(en: "About", es: "Acerca de"),
                    icon: "info.circle"
                )) {
                    AppInfoCell()
                    NavigationLink(
                        LaraL10n.text(en: "Credits", es: "Créditos"),
                        destination: CreditsView()
                    )
                }

                Section {
                    NavigationLink(destination: EagleCompatibilityCenterView()) {
                        Label(
                            LaraL10n.text(en: "Compatibility", es: "Compatibilidad"),
                            systemImage: "checkmark.shield.fill"
                        )
                    }
                    LabeledContent(
                        LaraL10n.text(en: "Feature channel", es: "Canal de funciones"),
                        value: channel.title
                    )
                } header: {
                    HeaderLabel(
                        text: LaraL10n.text(en: "Availability", es: "Disponibilidad"),
                        icon: "slider.horizontal.3"
                    )
                } footer: {
                    if !advancedToolsAllowed {
                        Text(LaraL10n.text(
                            en: "Kernelcache and RemoteCall controls require the Laboratory channel.",
                            es: "Los controles de Kernelcache y RemoteCall requieren el canal Laboratorio."
                        ))
                    }
                }
                } else {
                    Section {
                        laboratoryIntro
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if !advancedToolsAllowed {
                        Section {
                            Text(LaraL10n.text(
                                en: "Choose the Laboratory channel on Customize to use these tools.",
                                es: "Elige el canal Laboratorio en Personalizar para usar estas herramientas."
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if destination == .laboratory && advancedToolsAllowed {
                    Section(header: HeaderLabel(text: "Exploit", icon: "ant")) {
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
                    .accessibilityLabel(LaraL10n.text(
                        en: "Access method",
                        es: "Método de acceso"
                    ))
                    .onChange(of: selectedMethod) { newValue in
                        EaglePreferenceMigration.persistAccessMethod(newValue.rawValue)
                    }
                    
                    NavigationLink("Modify Offsets", destination: OffsetManagementView())
                    }
                }
                
                // kernelcache
                if destination == .laboratory && advancedToolsAllowed {
                    Section {
                    if !mgr.hasOffsets {
                        // this does not need to be here any longer, but i'll keep it here anyways.
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
                            if dlingkcache {
                                HStack {
                                    Text("Fetching Kernelcache...")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Text("Fetch Kernelcache")
                            }
                        }
                        .disabled(dlingkcache || !mgr.dsready)
                               
                        LabeledContent(content: {
                            Button(action: {
                                showkcachetips.toggle()
                            }) {
                                Image(systemName: "info.circle")
                            }
                        }) {
                            Button("Import Kernelcache", action: {
                                guard !importingkcache else { return }
                                showkcacheimport = true
                            })
                            .disabled(dlingkcache || importingkcache)
                        }
                    } else {
                        Button("Remove Kernelcache", action: {
                            Alertinator.shared.alert(title: "Clear Kernelcache Data?", body: "This will delete all kernelcache data and remove saved offsets. You will have to refetch the data to use Eagle again.", actionLabel: "Confirm", action: {
                                clearKcacheData()
                            })
                        })
                        .foregroundColor(.red)
                    }
                } header: {
                    HeaderLabel(text: "Kernelcache", icon: "cpu")
                } footer: {
                    if (!mgr.hasOffsets && (!mgr.dsready || (!mgr.vfsready && !mgr.sbxready))) {
                        Text("NOTE: You will have to click \"Run Exploit\" before you can fetch kernelcache.\n\nDeleting and refetching kernelcache may fix some issues. Try doing this before opening a GitHub issue or asking for support in our [Discord](https://discord.gg/gw8PcRF3Jr) server.")
                    } else {
                        Text("Deleting and refetching kernelcache may fix some issues. Try doing this before opening a GitHub issue or asking for support in our [Discord](https://discord.gg/gw8PcRF3Jr) server.")
                    }
                }
                }
                
                // tips
                if destination == .laboratory && advancedToolsAllowed && showkcachetips {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("How to obtain a kernelcache (macOS)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 2)

                            Text("1. Download the IPSW tool for your device.")
                            Link("https://github.com/blacktop/ipsw/releases",
                                 destination: URL(string: "https://github.com/blacktop/ipsw/releases")!)
                            
                            Text("2. Extract the archive.")
                            Text("3. Open Terminal.")
                            Text("4. Navigate to the extracted folder:")
                            Text("cd /path/to/ipsw_3.1.671_something_something/")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("5. Extract the kernel:")
                            Text("./ipsw extract --kernel [drag your ipsw here]")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("6. Get the kernelcache file.")
                            Text("7. Transfer the kernelcache to your iCloud or iPhone.")
                            Text("8. Tap the button above and select the kernelcache, for example kernelcache.release.iPhone14,3.")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                }
                
                if destination == .preferences {
                Section(header: HeaderLabel(text: LaraL10n.text(en: "App", es: "App"), icon: "gearshape"), footer: Text(LaraL10n.text(
                    en: "If keep alive is enabled, the app will continue running even if it is minimized.",
                    es: "Si Mantener activa está encendido, la app sigue funcionando aunque la minimices."
                ))) {
                    Toggle(LaraL10n.text(en: "Keep Alive", es: "Mantener activa"), isOn: $keepAlive)
                        .onChange(of: keepAlive) { _ in
                            if keepAlive {
                                if !kaenabled { toggleka() }
                            } else {
                                if kaenabled { toggleka() }
                            }
                        }
                    Toggle("Disable Log Dividers", isOn: $loggerNoBS)
                        .onChange(of: loggerNoBS) { disabled in
                            EaglePreferenceMigration.persistDisableLogDividers(disabled)
                        }
                }
                
                if advancedToolsAllowed {
                    Section(header: HeaderLabel(text: "File Manager", icon: "folder"), footer: Text("Display Mode lets you change the way app folders get displayed in the file manager.")) {
                    Picker("Display Mode", selection: $selectedFMAppsDisplayMode) {
                        ForEach(fmAppsDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Recursive Search in File Manager", isOn: $fmRecursiveSearch)
                    Toggle("Show File Manager in Tabs", isOn: $showFMInTabs)
                    }
                }
                }
                
                #if !DISABLE_REMOTECALL
                if destination == .laboratory && advancedToolsAllowed {
                    Section(header: HeaderLabel(text: "RemoteCall", icon: "syringe")) {
                    Toggle("Stash KRW primitives", isOn: $stashKRW)
                        .onChange(of: stashKRW) { enabled in
                            if enabled && isIOS16() {
                                Alertinator.shared.alert(
                                    title: "iOS 16 Warning",
                                    body: "Saving KRW on iOS 16 is currently unstable. If it fails, manually stash KRW a few more times."
                                )
                            }
                        }
                    if isIOS16() {
                        Toggle("Keep SpringBoard RemoteCall alive in background", isOn: $keepSpringBoardRemoteCallAliveIOS16)
                        Text("Warning: If Eagle exits while RemoteCall is active, SpringBoard may respring.")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.red)

                        Button {
                            guard !stashingKRWNow else { return }
                            stashingKRWNow = true
                            mgr.stashKRWToLaunchd { success in
                                stashingKRWNow = false
                                if success {
                                    Alertinator.shared.alert(
                                        title: "KRW Stashed",
                                        body: "KRW primitives were successfully stashed to launchd."
                                    )
                                } else {
                                    let error = mgr.rcLastError ?? "Please try manually stashing KRW a few more times."
                                    Alertinator.shared.alert(
                                        title: "Failed to Stash KRW",
                                        body: error
                                    )
                                }
                            }
                        } label: {
                            if stashingKRWNow {
                                HStack {
                                    Text("Stashing KRW to launchd...")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Text("Stash KRW to launchd now")
                            }
                        }
                        .disabled(!mgr.dsready || mgr.rcrunning || stashingKRWNow)
                    }
                    Toggle("Allow >10 dock icons", isOn: $rcDockUnlimited)
                    }
                }
                #endif
            }
            .navigationTitle(destination == .laboratory
                ? LaraL10n.text(en: "Laboratory Tools", es: "Herramientas de Laboratorio")
                : LaraL10n.text(en: "Settings", es: "Ajustes"))
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
