import SwiftUI

struct LaraHomeView: View {
    @ObservedObject private var mgr = laramgr.shared
    @AppStorage(LaraLanguage.storageKey) private var language = LaraLanguage.english
    @AppStorage("eagle.home.homeLabelColor.beta10Seen")
    private var hasSeenHomeLabelColorBeta10 = false
    @AppStorage("eagle.home.islandGallery.galleryStabilitySeen")
    private var hasSeenIslandGallery = false
    @AppStorage("eagle.home.dockGallery.galleryStabilitySeen")
    private var hasSeenDockGallery = false
    @AppStorage("eagle.home.hideSurfaces.galleryStabilitySeen")
    private var hasSeenHideSurfaces = false
    @State private var toolSearchQuery = ""
    @FocusState private var isToolSearchFocused: Bool
    @AppStorage(EagleReleaseChannel.storageKey)
    private var channelRaw = EagleReleaseChannel.stable.rawValue
    @State private var pendingDowngrade: EagleReleaseChannel?
    @State private var flashChannel: EagleReleaseChannel?
    @State private var flashLevel: Double = 0
    @State private var showingSettings = false
    @State private var showingLaboratory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                        .eagleArrival(0)
                    channelSelector
                        .eagleArrival(1)
                    if EagleFeaturePolicy.allows(.advancedSystemTools, channel: currentChannel) {
                        laboratoryTools
                            .eagleArrival(2)
                    }

                    if normalizedToolQuery.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            NavigationLink(destination: auraStudioDestination) {
                                AuraStudioHeroCard(
                                    title: "Aura Studio",
                                    subtitle: LaraL10n.text(
                                        en: "Dynamic Island neon, rainbow, and glow.",
                                        es: "Neón, arcoíris y brillo para Dynamic Island."
                                    )
                                )
                            }
                            .buttonStyle(EaglePressableStyle())
                            .eagleScrollDepth()

                            VStack(alignment: .leading, spacing: 10) {
                                Text(LaraL10n.text(en: "Customize one part", es: "Personalizar una parte"))
                                    .font(.headline)
                                    .eagleBackdropText()
                                    .padding(.horizontal, 2)
                                    .accessibilityAddTraits(.isHeader)

                                VStack(spacing: 0) {
                                    NavigationLink(destination: islandGalleryDestination) {
                                        LaraToolRow(
                                            title: LaraL10n.text(en: "Island Gallery", es: "Galería Island"),
                                            subtitle: LaraL10n.text(
                                                en: "Photo styles with intense halos",
                                                es: "Estilos fotográficos con halos intensos"
                                            ),
                                            systemImage: "capsule.fill",
                                            accent: Color(red: 0.69, green: 0.32, blue: 0.87),
                                            badge: hasSeenIslandGallery ? nil : LaraL10n.text(en: "NEW", es: "NUEVO")
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: dockGalleryDestination) {
                                        LaraToolRow(
                                            title: LaraL10n.text(en: "Dock Gallery", es: "Galería Dock"),
                                            subtitle: LaraL10n.text(
                                                en: "Artwork behind your Dock apps",
                                                es: "Arte detrás de las apps del Dock"
                                            ),
                                            systemImage: "dock.rectangle",
                                            accent: Color(red: 1.00, green: 0.18, blue: 0.62),
                                            badge: hasSeenDockGallery ? nil : LaraL10n.text(en: "NEW", es: "NUEVO")
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: hideSurfacesDestination) {
                                        LaraToolRow(
                                            title: "Hide Dock + Island",
                                            subtitle: LaraL10n.text(en: "System visibility", es: "Visibilidad del sistema"),
                                            systemImage: "eye.slash.fill",
                                            accent: .indigo,
                                            badge: hasSeenHideSurfaces ? nil : LaraL10n.text(en: "NEW", es: "NUEVO")
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: AnimatedWallpapersView()) {
                                    LaraToolRow(
                                        title: LaraL10n.text(en: "Wallpapers", es: "Fondos"),
                                        subtitle: LaraL10n.text(en: "Explore or create", es: "Explora o crea"),
                                        systemImage: "photo.on.rectangle.angled",
                                        accent: Color(red: 0.34, green: 0.31, blue: 0.88)
                                    )
                                }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: PasscodeView(mgr: mgr)) {
                                        LaraToolRow(
                                            title: LaraL10n.text(en: "Passcode", es: "Código"),
                                            subtitle: LaraL10n.text(en: "Unlock key styles", es: "Números de desbloqueo"),
                                            systemImage: "circle.grid.3x3.fill",
                                            accent: Color(red: 0.56, green: 0.28, blue: 0.72)
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: CardView()) {
                                        LaraToolRow(
                                            title: LaraL10n.text(en: "Cards", es: "Tarjetas"),
                                            subtitle: LaraL10n.text(en: "Wallet design", es: "Diseño de Wallet"),
                                            systemImage: "creditcard.fill",
                                            accent: Color(red: 0.08, green: 0.48, blue: 0.52)
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: DockCustomizerView()) {
                                        LaraToolRow(
                                            title: "Dock",
                                            subtitle: LaraL10n.text(en: "Fit up to six apps", es: "Hasta seis apps"),
                                            systemImage: "dock.rectangle",
                                            accent: Color(red: 0.12, green: 0.46, blue: 0.86)
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    NavigationLink(destination: homeLabelColorDestination) {
                                        LaraToolRow(
                                            title: LaraL10n.text(en: "App Name Color", es: "Color de nombres"),
                                            subtitle: LaraL10n.text(
                                                en: "Solid Home Screen text colors · Advanced",
                                                es: "Colores sólidos para los textos de Inicio · Avanzado"
                                            ),
                                            systemImage: "textformat",
                                            accent: Color(red: 0.36, green: 0.30, blue: 0.88),
                                            badge: hasSeenHomeLabelColorBeta10 ? nil : LaraL10n.text(en: "NEW", es: "NUEVO")
                                        )
                                    }

                                    Divider().padding(.leading, 65)

                                    LaraToolRow(
                                        title: LaraL10n.text(en: "Icon Studio", es: "Icon Studio"),
                                        subtitle: LaraL10n.text(
                                            en: "Themes and custom shapes",
                                            es: "Temas y formas personalizadas"
                                        ),
                                        systemImage: "square.grid.2x2.fill",
                                        accent: Color(red: 0.18, green: 0.60, blue: 0.42),
                                        badge: LaraL10n.text(en: "SOON", es: "PRÓXIMAMENTE"),
                                        badgeIsMuted: true,
                                        showsDisclosureIndicator: false
                                    )
                                    .opacity(0.62)
                                    .accessibilityHint(LaraL10n.text(
                                        en: "Icon Studio is coming soon",
                                        es: "Icon Studio estará disponible próximamente"
                                    ))
                                }
                                .buttonStyle(EaglePressableStyle(kind: .row))
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
                                }
                            }

                            NavigationLink(destination: CompleteStylesView()) {
                                LaraFeatureCard(
                                    title: LaraL10n.text(en: "Styles", es: "Estilos"),
                                    subtitle: LaraL10n.text(
                                        en: "A complete look for your wallpaper, passcode, and card.",
                                        es: "Un aspecto completo para el fondo, el código y tu tarjeta."
                                    ),
                                    systemImage: "sparkles",
                                    accent: Color(red: 0.33, green: 0.25, blue: 0.82),
                                    artwork: .styles
                                )
                            }
                            .buttonStyle(EaglePressableStyle())
                            .eagleScrollDepth()
                        }
                        .eagleArrival(3)
                    } else {
                        toolSearchResults
                            // Results slide in and out as the query changes instead of jumping.
                            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: filteredToolRoutes)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
                // Starting or clearing a search crossfades between the tools and the results.
                .animation(.easeInOut(duration: 0.22), value: normalizedToolQuery.isEmpty)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(EagleBackdrop().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .eagleRootNavigationBar()
            .eagleStatusBarVeil()
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(mgr)
            }
            .sheet(isPresented: $showingLaboratory) {
                LaboratoryToolsView()
                    .environmentObject(mgr)
            }
            .alert(
                LaraL10n.text(en: "You'll lose features", es: "Perderás funciones"),
                isPresented: Binding(
                    get: { pendingDowngrade != nil },
                    set: { if !$0 { pendingDowngrade = nil } }
                ),
                presenting: pendingDowngrade
            ) { target in
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        channelRaw = target.rawValue
                    }
                    flashChannelActivation(target)
                    pendingDowngrade = nil
                } label: {
                    Text(LaraL10n.text(en: "Switch anyway", es: "Cambiar igualmente"))
                }
                Button(role: .cancel) {
                    pendingDowngrade = nil
                } label: {
                    Text(LaraL10n.text(en: "Cancel", es: "Cancelar"))
                }
            } message: { target in
                Text(downgradeMessage(for: target))
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        EagleHeaderBar(language: $language) {
            showingSettings = true
        }
    }

    private var laboratoryTools: some View {
        Button { showingLaboratory = true } label: {
            LaraToolRow(
                title: LaraL10n.text(en: "Laboratory tools", es: "Herramientas de Laboratorio"),
                subtitle: "Kernelcache · RemoteCall",
                systemImage: "testtube.2",
                accent: .primary
            )
        }
        .buttonStyle(EaglePressableStyle(kind: .row))
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("laboratory-tools")
    }

    private var eagleTitle: some View {
        EagleWordmark()
    }

    private var headerBadges: some View {
        VStack(alignment: .trailing, spacing: 8) {
            languageBadge
            readinessBadge
        }
    }

    private var languageBadge: some View {
        Menu {
            Picker(
                LaraL10n.text(en: "Language", es: "Idioma"),
                selection: $language
            ) {
                ForEach(LaraLanguage.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.primary)
                Text(language.shortName)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .tint(.primary)
        .accessibilityLabel(LaraL10n.text(en: "Language", es: "Idioma"))
        .accessibilityValue(language.displayName)
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

    private var currentChannel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: channelRaw)
    }

    // Three equal, full-width segments (Stable / Advanced / Laboratory) that
    // replace the old search bar. The visual shell only flips the stored
    // channel and warns on a downgrade — the deeper feature handling lives
    // elsewhere.
    private var channelSelector: some View {
        HStack(spacing: 6) {
            ForEach(EagleReleaseChannel.allCases) { channel in
                channelButton(channel)
            }
        }
        .padding(6)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LaraL10n.text(en: "Feature channel", es: "Canal de funciones"))
    }

    private func channelButton(_ channel: EagleReleaseChannel) -> some View {
        let isSelected = currentChannel == channel
        return Button {
            selectChannel(channel)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: channelIcon(channel))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(channelIconColor(channel))
                Text(channel.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(
                isSelected
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
                    : AnyShapeStyle(Color.primary)
            )
            .background(
                isSelected ? Color.primary : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                // Green confirmation flash that fades out on selection.
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.green.opacity(
                        0.55 * (flashChannel == channel ? flashLevel : 0)
                    ))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(EaglePressableStyle())
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(channel.title)
        .accessibilityValue(
            isSelected ? LaraL10n.text(en: "Active", es: "Activo") : ""
        )
        .accessibilityHint(channel.explanation)
    }

    private func channelIcon(_ channel: EagleReleaseChannel) -> String {
        switch channel {
        case .stable: return "checkmark.shield.fill"     // safe, proven
        case .beta: return "bolt.fill"                    // advanced, more power
        case .experimental: return "testtube.2"           // laboratory, experimental
        }
    }

    /// Each channel keeps its own accent so the icon reads as that function's
    /// colour, whether the pill is selected (white) or not (dark).
    private func channelIconColor(_ channel: EagleReleaseChannel) -> Color {
        switch channel {
        case .stable: return Color(red: 0.10, green: 0.72, blue: 0.30)       // vivid green
        case .beta: return Color(red: 1.00, green: 0.48, blue: 0.00)         // vivid amber
        case .experimental: return Color(red: 0.55, green: 0.22, blue: 1.00) // vivid purple
        }
    }

    private func selectChannel(_ channel: EagleReleaseChannel) {
        guard channel != currentChannel else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if channel.level < currentChannel.level {
            pendingDowngrade = channel
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                channelRaw = channel.rawValue
            }
            flashChannelActivation(channel)
        }
    }

    private func flashChannelActivation(_ channel: EagleReleaseChannel) {
        flashChannel = channel
        flashLevel = 1
        withAnimation(.easeOut(duration: 0.6)) {
            flashLevel = 0
        }
    }

    private func lostFeatures(switchingTo target: EagleReleaseChannel) -> [EagleProductFeature] {
        let stillAvailable = Set(EagleFeaturePolicy.availableFeatures(channel: target))
        return EagleFeaturePolicy
            .availableFeatures(channel: currentChannel)
            .filter { !stillAvailable.contains($0) }
    }

    private func downgradeMessage(for target: EagleReleaseChannel) -> String {
        let names = lostFeatures(switchingTo: target)
            .map(\.title)
            .joined(separator: ", ")
        return LaraL10n.text(
            en: "Switching to \(target.title) makes these features unavailable: \(names). Existing visual effects are not removed automatically; restore them normally or respring. You can get the features back by moving up a level again.",
            es: "Cambiar a \(target.title) deja estas funciones no disponibles: \(names). Los efectos visuales existentes no se eliminan automáticamente; restáuralos normalmente o haz respring. Puedes recuperar las funciones volviendo a subir de nivel."
        )
    }

    private var normalizedToolQuery: String {
        toolSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableToolRoutes: [LaraHomeToolRoute] {
        LaraHomeToolRoute.allCases.filter { route in
            switch route {
            case .auraStudio, .completeStyles, .wallpapers,
                    .homeLabelColor, .cards, .passcode, .icons, .dock,
                    .islandGallery, .dockGallery, .hideSurfaces:
                return true
            case .advancedSettings:
                return EagleFeaturePolicy.allows(.advancedSystemTools, channel: currentChannel)
            case .eagleSystem:
                return false
            }
        }
    }

    private var filteredToolRoutes: [LaraHomeToolRoute] {
        guard !normalizedToolQuery.isEmpty else { return [] }
        return availableToolRoutes.filter { route in
            let searchableText = "\(route.title) \(route.subtitle) \(route.keywords)"
            return searchableText.range(
                of: normalizedToolQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) != nil
        }
    }

    private var toolSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                LaraL10n.text(en: "Search tools", es: "Buscar herramientas"),
                text: $toolSearchQuery
            )
            .focused($isToolSearchFocused)
            .submitLabel(.search)
            .onSubmit {
                isToolSearchFocused = false
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 44)
            .accessibilityLabel(LaraL10n.text(
                en: "Search tools",
                es: "Buscar herramientas"
            ))
            .accessibilityHint(LaraL10n.text(
                en: "Searches every customization tool.",
                es: "Busca en todas las herramientas de personalización."
            ))

            if !toolSearchQuery.isEmpty {
                Button {
                    toolSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(EaglePressableStyle(kind: .swatch))
                .accessibilityLabel(LaraL10n.text(
                    en: "Clear search",
                    es: "Limpiar búsqueda"
                ))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, toolSearchQuery.isEmpty ? 14 : 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var toolSearchResults: some View {
        if filteredToolRoutes.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(LaraL10n.text(
                    en: "No matching tools",
                    es: "No hay herramientas coincidentes"
                ))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(LaraL10n.text(
                    en: "Try another customization name.",
                    es: "Prueba otro nombre de personalización."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .padding(.horizontal, 18)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 0) {
                ForEach(filteredToolRoutes) { route in
                    searchResult(for: route)
                    if route != filteredToolRoutes.last {
                        Divider().padding(.leading, 65)
                    }
                }
            }
            .buttonStyle(EaglePressableStyle(kind: .row))
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func searchResult(for route: LaraHomeToolRoute) -> some View {
        if route == .advancedSettings {
            Button { showingSettings = true } label: { toolSearchRow(for: route) }
        } else if route == .icons {
            toolSearchRow(for: route)
                .opacity(0.62)
                .accessibilityHint(LaraL10n.text(
                    en: "Icon Studio is coming soon",
                    es: "Icon Studio estará disponible próximamente"
                ))
        } else {
            NavigationLink {
                toolDestination(for: route)
            } label: {
                toolSearchRow(for: route)
            }
            .accessibilityHint(LaraL10n.text(
                en: "Opens \(route.title)",
                es: "Abre \(route.title)"
            ))
        }
    }

    private func toolSearchRow(for route: LaraHomeToolRoute) -> some View {
        LaraToolRow(
            title: route.title,
            subtitle: route.subtitle,
            systemImage: route.systemImage,
            accent: route.accent,
            badge: route == .icons
                ? LaraL10n.text(en: "SOON", es: "PRÓXIMAMENTE")
                : ((route == .islandGallery && !hasSeenIslandGallery) ||
                   (route == .dockGallery && !hasSeenDockGallery) ||
                   (route == .hideSurfaces && !hasSeenHideSurfaces) ||
                   (route == .homeLabelColor && !hasSeenHomeLabelColorBeta10)
                    ? LaraL10n.text(en: "NEW", es: "NUEVO") : nil),
            badgeIsMuted: route == .icons,
            showsDisclosureIndicator: route != .icons
        )
    }

    @ViewBuilder
    private func toolDestination(for route: LaraHomeToolRoute) -> some View {
        switch route {
        case .completeStyles:
            CompleteStylesView()
        case .eagleSystem:
            EagleSystemView()
        case .wallpapers:
            AnimatedWallpapersView()
        case .homeLabelColor:
            homeLabelColorDestination
        case .cards:
            CardView()
        case .passcode:
            PasscodeView(mgr: mgr)
        case .icons:
            DarkBoardView()
        case .dock:
            DockCustomizerView()
        case .islandGallery:
            islandGalleryDestination
        case .dockGallery:
            dockGalleryDestination
        case .hideSurfaces:
            hideSurfacesDestination
        case .advancedSettings:
            SettingsView().environmentObject(mgr)
        case .auraStudio:
            auraStudioDestination
        }
    }

    private var auraStudioDestination: some View {
        AuraStudioView()
    }

    private var hideSurfacesDestination: some View {
        HideDockIslandView()
            .onAppear { hasSeenHideSurfaces = true }
    }

    private var homeLabelColorDestination: some View {
        HomeLabelColorView()
            .onAppear {
                hasSeenHomeLabelColorBeta10 = true
            }
    }

    private var islandGalleryDestination: some View {
        IslandGalleryView()
            .onAppear {
                hasSeenIslandGallery = true
            }
    }

    private var dockGalleryDestination: some View {
        DockGalleryView()
            .onAppear {
                hasSeenDockGallery = true
            }
    }

}

private enum LaraHomeToolRoute: String, CaseIterable, Identifiable {
    case auraStudio
    case completeStyles
    case eagleSystem
    case wallpapers
    case homeLabelColor
    case cards
    case passcode
    case dock
    case islandGallery
    case dockGallery
    case hideSurfaces
    case advancedSettings
    case icons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completeStyles: return LaraL10n.text(en: "Styles", es: "Estilos")
        case .eagleSystem: return "Eagle System"
        case .wallpapers: return LaraL10n.text(en: "Wallpapers", es: "Fondos")
        case .homeLabelColor:
            return LaraL10n.text(en: "App Name Color", es: "Color de nombres")
        case .cards: return LaraL10n.text(en: "Cards", es: "Tarjetas")
        case .passcode: return LaraL10n.text(en: "Passcode", es: "Código")
        case .icons: return "Icon Studio"
        case .dock: return "Dock"
        case .islandGallery:
            return LaraL10n.text(en: "Island Gallery", es: "Galería Island")
        case .dockGallery:
            return LaraL10n.text(en: "Dock Gallery", es: "Galería Dock")
        case .hideSurfaces:
            return "Hide Dock + Island"
        case .advancedSettings:
            return LaraL10n.text(en: "Advanced system tools", es: "Herramientas avanzadas")
        case .auraStudio: return "Aura Studio"
        }
    }

    var subtitle: String {
        switch self {
        case .hideSurfaces:
            return LaraL10n.text(en: "System visibility", es: "Visibilidad del sistema")
        case .completeStyles:
            return LaraL10n.text(en: "Complete visual styles", es: "Estilos visuales completos")
        case .eagleSystem:
            return LaraL10n.text(en: "Guardian and recovery", es: "Guardian y recuperación")
        case .wallpapers:
            return LaraL10n.text(en: "Explore or create", es: "Explora o crea")
        case .homeLabelColor:
            return LaraL10n.text(
                en: "Solid Home Screen text colors · Advanced",
                es: "Colores sólidos para los textos de Inicio · Avanzado"
            )
        case .cards:
            return LaraL10n.text(en: "Wallet design", es: "Diseño de Wallet")
        case .passcode:
            return LaraL10n.text(en: "Unlock key styles", es: "Números de desbloqueo")
        case .icons:
            return LaraL10n.text(en: "Themes and Android shapes", es: "Temas y formas Android")
        case .dock:
            return LaraL10n.text(en: "Fit up to six apps", es: "Hasta seis apps")
        case .islandGallery:
            return LaraL10n.text(en: "Live and static Island themes", es: "Temas Island Live y estáticos")
        case .dockGallery:
            return LaraL10n.text(
                en: "Artwork behind your Dock apps",
                es: "Arte detrás de las apps del Dock"
            )
        case .advancedSettings:
            return LaraL10n.text(en: "Expert controls", es: "Controles expertos")
        case .auraStudio:
            return LaraL10n.text(en: "System neon controls", es: "Controles de neón del sistema")
        }
    }

    var systemImage: String {
        switch self {
        case .hideSurfaces: return "eye.slash.fill"
        case .completeStyles: return "sparkles"
        case .eagleSystem: return "checkmark.shield.fill"
        case .wallpapers: return "photo.on.rectangle.angled"
        case .homeLabelColor: return "textformat"
        case .cards: return "creditcard.fill"
        case .passcode: return "circle.grid.3x3.fill"
        case .icons: return "square.grid.2x2.fill"
        case .dock: return "dock.rectangle"
        case .islandGallery: return "capsule.fill"
        case .dockGallery: return "dock.rectangle"
        case .advancedSettings: return "wrench.and.screwdriver.fill"
        case .auraStudio: return "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .hideSurfaces: return .indigo
        case .completeStyles: return Color(red: 0.33, green: 0.25, blue: 0.82)
        case .eagleSystem: return .indigo
        case .wallpapers: return Color(red: 0.34, green: 0.31, blue: 0.88)
        case .homeLabelColor: return Color(red: 0.36, green: 0.30, blue: 0.88)
        case .cards: return Color(red: 0.08, green: 0.48, blue: 0.52)
        case .passcode: return Color(red: 0.56, green: 0.28, blue: 0.72)
        case .icons: return Color(red: 0.18, green: 0.60, blue: 0.42)
        case .dock: return Color(red: 0.12, green: 0.46, blue: 0.86)
        case .islandGallery: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .dockGallery: return Color(red: 1.00, green: 0.18, blue: 0.62)
        case .advancedSettings: return .orange
        case .auraStudio: return Color(red: 0.10, green: 0.78, blue: 1.00)
        }
    }

    var keywords: String {
        switch self {
        case .hideSurfaces: return "hide dock island ocultar isla fondo background visibility visibilidad"
        case .completeStyles: return "style styles estilo estilos complete completo visual"
        case .eagleSystem: return "system sistema guardian recovery recuperación"
        case .wallpapers: return "wallpaper wallpapers fondo fondos creator creador gallery galería"
        case .homeLabelColor:
            return "text color label labels name names texto color nombre nombres home inicio solid sólido"
        case .cards: return "card cards tarjeta tarjetas wallet"
        case .passcode: return "passcode code código unlock desbloqueo key keys números"
        case .icons: return "icon icons icono iconos theme themes tema temas android shape formas"
        case .dock: return "dock apps icons iconos capacity capacidad"
        case .islandGallery:
            return "island isla gallery galería live static saves themes temas shadow sombra"
        case .dockGallery:
            return "dock gallery galería art arte photo foto theme tema apps"
        case .advancedSettings: return "advanced avanzado settings ajustes expert experto kernelcache laboratory laboratorio lab remotecall"
        case .auraStudio: return "aura neon neón island isla dock glow"
        }
    }
}

private struct LaraFeatureCard: View {
    enum Artwork {
        case aura
        case styles
        case wallpaper
        case card
        case passcode
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let artwork: Artwork
    let badge: String?

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        artwork: Artwork,
        badge: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.artwork = artwork
        self.badge = badge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                accent.opacity(0.12)

                switch artwork {
                case .aura:
                    auraArtwork
                case .styles:
                    stylesArtwork
                case .wallpaper:
                    wallpaperArtwork
                case .card:
                    cardArtwork
                case .passcode:
                    passcodeArtwork
                }
            }
            .frame(height: 154)
            .clipped()
            .accessibilityHidden(true)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                EagleNewBadge(text: badge)
                    .padding(12)
                    .accessibilityLabel(LaraL10n.text(en: "New", es: "Nuevo"))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }

    private var auraArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.11, green: 0.05, blue: 0.24), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Capsule(style: .continuous)
                .stroke(Color.purple.opacity(0.20), lineWidth: 15)
                .frame(width: 164, height: 58)
                .blur(radius: 13)

            Capsule(style: .continuous)
                .fill(Color.black)
                .frame(width: 154, height: 49)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [.cyan, .blue, .purple, .pink, .orange, .cyan],
                                center: .center
                            ),
                            lineWidth: 3.5
                        )
                }
                .shadow(color: .cyan.opacity(0.52), radius: 11)
                .shadow(color: .pink.opacity(0.34), radius: 20)
        }
    }

    private var stylesArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.72), accent, Color.indigo.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 138)
                .overlay(alignment: .top) {
                    VStack(spacing: 1) {
                        Text("9:41")
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                        HStack(spacing: 5) {
                            ForEach(1..<4) { number in
                                Circle()
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Text("\(number)")
                                            .font(.system(size: 6, weight: .bold))
                                    }
                            }
                        }
                        .padding(.top, 15)
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                }
                .rotationEffect(.degrees(-5))

            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.9), accent, Color.cyan.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 150, height: 94)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.primary)
                        .padding(14)
                }
                .rotationEffect(.degrees(5))
                .offset(x: 72, y: 30)
                .shadow(color: accent.opacity(0.25), radius: 16, y: 8)
        }
        .offset(x: -28)
    }

    private var wallpaperArtwork: some View {
        HStack(spacing: -22) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(accent.opacity(0.35))
                .frame(width: 92, height: 126)
                .rotationEffect(.degrees(-8))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(accent)
                .frame(width: 96, height: 132)
                .overlay(alignment: .top) {
                    VStack(spacing: 1) {
                        Text("9:41")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("jueves, 13 de agosto")
                            .font(.system(size: 6, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 22)
                }
                .shadow(color: accent.opacity(0.25), radius: 18, y: 10)
        }
    }

    private var cardArtwork: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(accent)
            .frame(width: 220, height: 132)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 34) {
                    Image(systemName: "wave.3.right")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack {
                        Text("•••• 4242")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Spacer()
                        Image(systemName: "apple.logo")
                            .foregroundStyle(.primary)
                    }
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(18)
            }
            .rotationEffect(.degrees(-3))
            .shadow(color: accent.opacity(0.25), radius: 18, y: 10)
    }

    private var passcodeArtwork: some View {
        VStack(spacing: 9) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(1..<4, id: \.self) { column in
                        let number = row * 3 + column
                        Circle()
                            .fill(accent.opacity(number.isMultiple(of: 2) ? 0.82 : 1))
                            .frame(width: 35, height: 35)
                            .overlay {
                                Text("\(number)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                    }
                }
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .rotationEffect(.degrees(2))
        .shadow(color: accent.opacity(0.22), radius: 18, y: 10)
    }
}

private struct AuraStudioHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var neonOnScreen = false

    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            neonCapsule

            VStack(alignment: .leading, spacing: -2) {
                Text("Aura")
                Text("Studio")
            }
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(auraBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(EagleVisualTheme.surfaceBorder(for: colorScheme), lineWidth: 1)
        }
        .eagleSurfaceShadow(cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }

    private var auraBackground: some View {
        ZStack {
            // Same neutral system surface as every other card — no more purple.
            Color(uiColor: .secondarySystemGroupedBackground)

            // A soft aurora gathered on the left, behind the dynamic-island
            // preview, so the island reads with some colour and style without
            // repainting the whole card.
            auroraGlow
        }
    }

    private var auroraGlow: some View {
        ZStack {
            auroraBlob(Color(red: 0.28, green: 0.82, blue: 1.00), size: 165,
                       x: -128, y: -16, opacity: colorScheme == .dark ? 0.34 : 0.20)
            auroraBlob(Color(red: 0.60, green: 0.42, blue: 1.00), size: 150,
                       x: -74, y: 20, opacity: colorScheme == .dark ? 0.30 : 0.17)
            auroraBlob(Color(red: 1.00, green: 0.44, blue: 0.74), size: 135,
                       x: -158, y: 26, opacity: colorScheme == .dark ? 0.26 : 0.15)
            auroraBlob(Color(red: 0.35, green: 0.95, blue: 0.72), size: 120,
                       x: -104, y: 34, opacity: colorScheme == .dark ? 0.22 : 0.13)
        }
        // The card's full size, flattened into one image: the four large blurs are rendered once and
        // kept, instead of being composed again on every frame of the turning neon ring above them.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .drawingGroup()
        .allowsHitTesting(false)
    }

    private func auroraBlob(
        _ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
            .blur(radius: 42)
            .opacity(opacity)
    }

    /// The neon ring turns at 60 frames a second (at 30 its edge stepped visibly) and stops while the
    /// card is off screen. Only the coloured ring is redrawn each frame: the glow and the capsule do not
    /// depend on the turn (the shadows follow the ring's shape, not its colours), so they are drawn
    /// once, outside the clock, instead of re-blurring two shadows every frame. Looks the same.
    private var neonCapsule: some View {
        ZStack {
            Capsule(style: .continuous)
                .stroke(Color.purple.opacity(0.30), lineWidth: 15)
                .frame(width: 128, height: 48)
                .blur(radius: 14)

            // The capsule with the ring's exact outline, and its glow.
            Capsule(style: .continuous)
                .fill(Color.black)
                .frame(width: 122, height: 44)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.black, lineWidth: 3)
                }
                .shadow(color: .cyan.opacity(0.5), radius: 10)
                .shadow(color: .pink.opacity(0.36), radius: 16)

            // The colours are painted once and only turned (a transform, nearly free to draw); turning
            // the gradient about the centre is exactly what changing its angle did.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || !neonOnScreen)) { context in
                let cycles = context.date.timeIntervalSinceReferenceDate / 5.2
                let angle = reduceMotion ? 0 : (cycles - floor(cycles)) * 360
                AngularGradient(
                    colors: [.cyan, .blue, .purple, .pink, .orange, .cyan],
                    center: .center
                )
                // Big enough that, turning, it always covers the capsule's ends (half-diagonal ≈ 66 pt).
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(angle))
                .frame(width: 122, height: 44)
                .mask {
                    Capsule(style: .continuous)
                        .stroke(lineWidth: 3)
                        .frame(width: 122, height: 44)
                }
            }
        }
        .frame(width: 138, height: 96)
        .onAppear { neonOnScreen = true }
        .onDisappear { neonOnScreen = false }
        .accessibilityHidden(true)
    }
}

private struct LaraToolRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var badge: String? = nil
    /// Keep SOON visually quieter than the monochrome NEW badge.
    var badgeIsMuted: Bool = false
    var badgeCount: Int? = nil
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                // Symbols such as "textformat" are redrawn per language (格式 in Chinese); the row
                // icons keep their Latin design in every language.
                .environment(\.locale, Locale(identifier: "en"))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .eagleArrivalBounce()
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            if let badgeCount {
                EagleCountBadge(count: badgeCount)
            } else if let badge {
                if badgeIsMuted {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 20)
                        .background(Color.primary.opacity(0.10), in: Capsule())
                        .accessibilityHidden(true)
                } else {
                    EagleNewBadge(text: badge)
                        .accessibilityHidden(true)
                }
            }
            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            badgeCount != nil
                ? LaraL10n.text(
                    en: "\(subtitle). \(badgeCount ?? 0) features",
                    es: "\(subtitle). \(badgeCount ?? 0) funciones"
                )
                : (badge == nil ? subtitle : "\(subtitle). \(badge ?? "")")
        )
    }
}

/// A small notification-style badge: a bell followed by the number of features
/// available inside that entry.
struct EagleCountBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill")
                .font(.system(size: 9, weight: .bold))
                .eagleArrivalBounce(delay: 0.6)
            Text("\(count)")
                .font(.system(size: 11, weight: .heavy))
                .contentTransition(.numericText())
        }
        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        .padding(.horizontal, 8)
        .frame(minHeight: 20)
        .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
        .accessibilityHidden(true)
    }
}
