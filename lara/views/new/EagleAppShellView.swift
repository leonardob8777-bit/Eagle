import SwiftUI
import SafariServices

private enum EagleAppSection {
    case access
    case customize
}

struct EagleAppShellView: View {
    @ObservedObject private var sceneManager = EagleSceneManager.shared
    @State private var selectedSection = EagleAppSection.customize
    /// Observed so the tab titles and contents change language at once, like the rest of the app.
    @AppStorage(LaraLanguage.storageKey) private var language = LaraLanguage.english

    private let shellBackground = Color(uiColor: .systemGroupedBackground)

    var body: some View {
        TabView(selection: $selectedSection) {
            EagleBeta10AccessView()
                // Rebuilt in the new language at once (cards that hold no language state otherwise
                // keep their old text until reopened). The tab itself stays where it is.
                .id(language)
                .environment(\.laraMediaPreviewsEnabled, selectedSection == .access)
                .environment(\.eagleTabIsCurrent, selectedSection == .access)
                .tabItem {
                    Label(LaraL10n.text(en: "Access", es: "Acceso"), systemImage: "lock.shield.fill")
                }
                .tag(EagleAppSection.access)

            LaraHomeView()
                .id(language)
                .environment(\.laraMediaPreviewsEnabled, selectedSection == .customize)
                .environment(\.eagleTabIsCurrent, selectedSection == .customize)
                .tabItem {
                    Label(LaraL10n.text(en: "Customize", es: "Personalizar"), systemImage: "sparkles")
                }
                .tag(EagleAppSection.customize)
        }
        .tint(.primary)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(shellBackground.ignoresSafeArea())
        // A light tick when switching tabs, like a system picker.
        .onChange(of: selectedSection) { _ in UISelectionFeedbackGenerator().selectionChanged() }
        .onAppear {
            // The screens land as soon as Eagle opens. With the welcome on top this happens out of sight,
            // so when it opens they are already in place and nothing lands afterwards.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { EagleArrival.shared.arrive() }
        }
        .eagleNotice(item: $sceneManager.notice, title: "Eagle Scenes") { $0.message }
        .overlay {
            if sceneManager.isApplying {
                EagleBlockingProgress(
                    title: LaraL10n.text(
                        en: "Applying Scene safely",
                        es: "Aplicando Scene de forma segura"
                    ),
                    progress: sceneManager.progress
                )
            }
        }
    }

}

/// Eagle's official Telegram channel.
enum EagleLinks {
    static let telegram = URL(string: "https://t.me/LBsignapp")!
}

/// Opens a link (Telegram) in Safari inside Eagle, tinted Telegram blue.
struct TelegramSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(red: 0.15, green: 0.62, blue: 0.87, alpha: 1)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct EagleBeta10AccessView: View {
    @ObservedObject private var mgr = laramgr.shared
    @ObservedObject private var sceneManager = EagleSceneManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(LaraLanguage.storageKey) private var language = LaraLanguage.english
    @State private var showingSettings = false
    @State private var showingTelegram = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    accessHeader
                        .eagleArrival(0)

                    if sceneManager.hasPendingShortcut {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                LaraL10n.text(en: "Scene waiting", es: "Scene en espera"),
                                systemImage: "bolt.shield.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(.primary)

                            LaraAccessView(compact: true) {
                                sceneManager.applyPendingShortcutIfNeeded()
                            }
                        }
                        .eagleArrival(1)
                    } else {
                        LaraAccessView(compact: false) {
                            sceneManager.applyPendingShortcutIfNeeded()
                        }
                        .eagleArrival(1)
                        .eagleScrollDepth()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(LaraL10n.text(en: "Prepare report", es: "Reporte de Preparar"))
                            .font(.headline)
                            .eagleBackdropText()
                            .padding(.horizontal, 2)
                            .accessibilityAddTraits(.isHeader)
                        EaglePrepareCrashReportCard()
                    }
                    .eagleArrival(2)
                    .eagleScrollDepth()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(LaraL10n.text(en: "Access tools", es: "Herramientas de acceso"))
                            .font(.headline)
                            .eagleBackdropText()
                            .padding(.horizontal, 2)
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            NavigationLink(destination: EagleCompatibilityCenterView()) {
                                accessRow(
                                    title: LaraL10n.text(en: "Compatibility", es: "Compatibilidad"),
                                    subtitle: LaraL10n.text(
                                        en: "Device support and reports",
                                        es: "Compatibilidad y reportes"
                                    ),
                                    systemImage: "checkmark.shield.fill",
                                    accent: .blue
                                )
                            }

                            Divider().padding(.leading, 65)

                            NavigationLink(destination: EagleSystemView()) {
                                accessRow(
                                    title: "Eagle System",
                                    subtitle: LaraL10n.text(
                                        en: "Guardian and recovery",
                                        es: "Guardian y recuperación"
                                    ),
                                    systemImage: "shield.lefthalf.filled",
                                    accent: .indigo
                                )
                            }
                        }
                        .buttonStyle(EaglePressableStyle(kind: .row))
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(EagleVisualTheme.surfaceBorder(for: colorScheme), lineWidth: 1)
                        }
                        .eagleSurfaceShadow(cornerRadius: 22)
                    }
                    .eagleArrival(3)
                    .eagleScrollDepth()

                    telegramCard
                        .eagleArrival(4)
                        .eagleScrollDepth()

                    trustNote
                        .eagleArrival(5)
                        .eagleScrollDepth()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(EagleBackdrop().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .eagleRootNavigationBar()
            .eagleStatusBarVeil()
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(mgr)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var accessHeader: some View {
        EagleHeaderBar(language: $language, showsBackdropToggle: true) {
            showingSettings = true
        }
    }

    private var deviceModelName: String {
        let full = EagleDynamicIslandCompatibility.current.displayModel
        if let cut = full.range(of: " (") {
            return String(full[..<cut.lowerBound])
        }
        return full
    }

    private var iosVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0
            ? "\(v.majorVersion).\(v.minorVersion)"
            : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var readinessBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mgr.sbxready ? Color.green : Color.secondary.opacity(0.32))
                .frame(width: 8, height: 8)
            Text(mgr.sbxready
                ? "\(deviceModelName) · iOS \(iosVersionString)"
                : LaraL10n.text(en: "Not identified", es: "No identificado"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            mgr.sbxready
                ? LaraL10n.text(
                    en: "Identified: \(deviceModelName), iOS \(iosVersionString)",
                    es: "Identificado: \(deviceModelName), iOS \(iosVersionString)"
                )
                : LaraL10n.text(en: "Not identified", es: "No identificado")
        )
    }

    private func accessRow(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .eagleArrivalBounce(delay: 0.5)
                .frame(width: 38, height: 38)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var telegramCard: some View {
        Button {
            showingTelegram = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.24, green: 0.70, blue: 0.90),
                                    Color(red: 0.11, green: 0.52, blue: 0.79),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: -1, y: 1)
                }
                .frame(width: 54, height: 54)

                Text(LaraL10n.text(en: "Text me", es: "Escríbeme"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .eagleRainbowSweep()

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(EaglePressableStyle(kind: .row))
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(EagleVisualTheme.surfaceBorder(for: colorScheme), lineWidth: 1)
        }
        .eagleSurfaceShadow(cornerRadius: 22)
        .sheet(isPresented: $showingTelegram) {
            TelegramSafariView(url: EagleLinks.telegram)
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LaraL10n.text(en: "Text me", es: "Escríbeme"))
        .accessibilityAddTraits(.isButton)
    }

    private var trustNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.primary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(LaraL10n.text(en: "You stay in control", es: "Tú mantienes el control"))
                    .font(.subheadline.weight(.semibold))
                Text(LaraL10n.text(
                    en: "Preparation starts only when you press Prepare iPhone.",
                    es: "La preparación comienza solo cuando pulsas Preparar iPhone."
                ))
                .font(.footnote)
                .foregroundStyle(EagleVisualTheme.secondaryText(for: colorScheme))
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}
