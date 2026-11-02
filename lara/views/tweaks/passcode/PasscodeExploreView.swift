//
//  PasscodeExploreView.swift
//  lara
//
//  Created by neonmodder123 on 20/05/2026.
//

import SwiftUI
import WebKit

enum EaglePasscodeFavorites {
    static let storageKey = "eagle.passcode.favoriteThemeIDs"

    static func decode(_ value: String) -> Set<String> {
        guard let data = value.data(using: .utf8),
              let identifiers = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(identifiers)
    }

    static func encode(_ identifiers: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(identifiers.sorted()),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return value
    }
}

struct PasscodeExploreView: View {
    @ObservedObject var mgr: laramgr
    @ObservedObject private var gallery = PasscodeGalleryManager.shared
    @ObservedObject private var likes = EagleLikes.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(EaglePasscodeFavorites.storageKey)
    private var favoriteThemeIDsJSON = "[]"

    @State private var searchTerm = ""
    @State private var showsFavoritesOnly = false
    @State private var alertMessage: String?
    @State private var openedTheme: PasscodeGalleryTheme?
    var onImport: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    private func handleDownload(_ theme: PasscodeGalleryTheme) async {
        do {
            let dest = try await gallery.downloadAndImport(theme)
            onImport?(dest)
            dismiss()
        } catch { alertMessage = error.localizedDescription }
    }

    private var displayed: [PasscodeGalleryTheme] {
        // Most liked first.
        var themes = likes.sortedByLikes(gallery.themes, .passcode, id: \.id)
        if showsFavoritesOnly {
            let favorites = EaglePasscodeFavorites.decode(favoriteThemeIDsJSON)
            themes = themes.filter { favorites.contains($0.id) }
        }
        guard !searchTerm.isEmpty else { return themes }
        return themes.filter {
            "\($0.name) \($0.displayName) \($0.authorLine)".range(
                of: searchTerm,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) != nil
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if gallery.isLoading && gallery.themes.isEmpty {
                    loadingView
                } else if let error = gallery.loadError, gallery.themes.isEmpty {
                    errorView(error)
                } else if displayed.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "circle.grid.3x3")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(emptyTitle)
                            .font(.headline)
                        Text(emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 50)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 22) {
                        let favoriteIDs = EaglePasscodeFavorites.decode(favoriteThemeIDsJSON)
                        let hotID = likes.hottest(.passcode, among: displayed.map(\.id))
                        ForEach(displayed) { theme in
                            PasscodeGalleryCard(
                                theme: theme,
                                previewURL: gallery.previewURL(for: theme),
                                isDownloading: gallery.isDownloading(theme),
                                isFavorite: favoriteIDs.contains(theme.id),
                                isHot: theme.id == hotID,
                                onToggleFavorite: { toggleFavorite(theme) },
                                onOpen: { openedTheme = theme }
                            )
                        }
                    }
                }

            }
            .padding(16)
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "Passcode styles", es: "Estilos de código"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchTerm,
            prompt: LaraL10n.text(en: "Search style or creator", es: "Buscar estilo o creador")
        )
        .refreshable { await gallery.loadThemes(forceRefresh: true) }
        .task { if gallery.themes.isEmpty { await gallery.loadThemes() } }
        .task {
            await EagleLikes.shared.refresh(.passcode, favorites: EaglePasscodeFavorites.decode(favoriteThemeIDsJSON))
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showsFavoritesOnly.toggle()
                } label: {
                    Image(systemName: showsFavoritesOnly ? "heart.fill" : "heart")
                }
                .accessibilityLabel(showsFavoritesOnly
                    ? LaraL10n.text(en: "Show all styles", es: "Mostrar todos los estilos")
                    : LaraL10n.text(en: "Show favorite styles", es: "Mostrar estilos favoritos"))
                .accessibilityValue(showsFavoritesOnly
                    ? LaraL10n.text(en: "Favorites only", es: "Solo favoritos")
                    : LaraL10n.text(en: "All styles", es: "Todos los estilos"))
            }
        }
        .eagleStatus($alertMessage, title: LaraL10n.text(en: "Passcode styles", es: "Estilos del código"))
        .sheet(item: $openedTheme) { theme in
            PasscodeStyleSheet(theme: theme, gallery: gallery) {
                Task { await handleDownload(theme) }
            }
        }
    }

    private var emptyTitle: String {
        if showsFavoritesOnly {
            return searchTerm.isEmpty
                ? LaraL10n.text(en: "No favorite styles yet", es: "Todavía no hay estilos favoritos")
                : LaraL10n.text(en: "No matching favorites", es: "No hay favoritos coincidentes")
        }
        return searchTerm.isEmpty
            ? LaraL10n.text(en: "Eagle styles are coming soon", es: "Pronto habrá estilos Eagle")
            : LaraL10n.text(en: "No styles found", es: "No encontramos estilos")
    }

    private var emptyMessage: String {
        if showsFavoritesOnly && searchTerm.isEmpty {
            return LaraL10n.text(
                en: "Tap the heart on a style to save it here.",
                es: "Toca el corazón de un estilo para guardarlo aquí."
            )
        }
        return searchTerm.isEmpty
            ? LaraL10n.text(en: "New styles will appear here when published.", es: "Los estilos nuevos aparecerán aquí al publicarse.")
            : LaraL10n.text(en: "Try another name or creator.", es: "Prueba con otro nombre o creador.")
    }

    private func toggleFavorite(_ theme: PasscodeGalleryTheme) {
        var favorites = EaglePasscodeFavorites.decode(favoriteThemeIDsJSON)
        let liked = favorites.insert(theme.id).inserted
        if !liked {
            favorites.remove(theme.id)
        }
        favoriteThemeIDsJSON = EaglePasscodeFavorites.encode(favorites)
        EagleLikes.shared.setLiked(.passcode, theme.id, liked: liked)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(LaraL10n.text(en: "Loading styles…", es: "Cargando estilos…"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LaraL10n.text(
                en: "Styles could not be loaded",
                es: "No se pudieron cargar los estilos"
            ))
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(LaraL10n.text(en: "Try Again", es: "Intentar de nuevo")) {
                Task { await gallery.loadThemes(forceRefresh: true) }
            }
            .buttonStyle(.borderedProminent)
            // The contrasting colour on the black/white fill, grey while disabled.
            .eagleProminentLabel()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A complete iPhone at the screen's own proportions (1170 × 2532): the screen content fills the
/// display, inside a thin black bezel whose corners follow the width. Used wherever Eagle shows a
/// wallpaper or passcode capture, so they are never cropped and nothing is laid over them.
struct EagleDeviceFrame<Screen: View>: View {
    @ViewBuilder let screen: () -> Screen

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let bezel = max(2, width * 0.022)
            let outer = width * 0.15
            screen()
                .frame(width: width - bezel * 2, height: proxy.size.height - bezel * 2)
                .clipShape(RoundedRectangle(cornerRadius: outer - bezel, style: .continuous))
                .padding(bezel)
                .background(Color.black, in: RoundedRectangle(cornerRadius: outer, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: outer, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .aspectRatio(1170.0 / 2532.0, contentMode: .fit)
    }
}

private struct PasscodeGalleryCard: View {
    let theme: PasscodeGalleryTheme
    let previewURL: URL?
    let isDownloading: Bool
    let isFavorite: Bool
    let isHot: Bool
    let onToggleFavorite: () -> Void
    let onOpen: () -> Void

    var body: some View {
        // The style itself is the card; Use and the matching wallpaper live in its sheet.
        PasscodeStyleThumbnail(
            theme: theme,
            previewURL: previewURL,
            isDownloading: isDownloading,
            isFavorite: isFavorite,
            isHot: isHot,
            onLike: onToggleFavorite,
            onOpen: onOpen
        )
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(
                    isFavorite
                        ? LaraL10n.text(en: "Remove like", es: "Quitar me gusta")
                        : LaraL10n.text(en: "Like", es: "Me gusta"),
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }
}

/// A style's lock-screen capture as a complete iPhone, with its name underneath: tapped to open the
/// style, with its like button and the HOT tag on the artwork. Shared by the gallery grid and the
/// row of styles on the Passcode screen.
struct PasscodeStyleThumbnail: View {
    let theme: PasscodeGalleryTheme
    let previewURL: URL?
    var isDownloading = false
    var isFavorite = false
    var isSelected = false
    var isHot = false
    var onLike: (() -> Void)? = nil
    let onOpen: () -> Void
    @ObservedObject private var newItems = EagleNewItems.shared

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onOpen) {
                EagleDeviceFrame {
                    LaraRemoteMediaPreview(
                        url: previewURL,
                        animated: false,
                        contentMode: .fill,
                        showsRetry: false
                    )
                    .overlay {
                        if isDownloading {
                            ZStack {
                                Color.black.opacity(0.5)
                                ProgressView().tint(.white)
                            }
                        }
                    }
                }
            }
            .buttonStyle(EaglePressableStyle())
            .accessibilityLabel(theme.displayName)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(Color.white, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if isHot {
                        EagleHotBadge()
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                    if newItems.isNew(.passcode, theme.id) {
                        EagleNewBadge()
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 9)
            }
            .overlay(alignment: .bottomTrailing) {
                if let onLike {
                    EagleLikeButton(kind: .passcode, id: theme.id, isLiked: isFavorite, action: onLike)
                        .padding(2)
                }
            }

            Text(theme.displayName)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .eagleBackdropText()
        }
    }
}

/// One style, up close: its live animation (or capture) on a complete iPhone, its name with the
/// matching wallpaper beside it, and Use at the bottom. Opened from the gallery and from the Passcode
/// screen's row of styles.
struct PasscodeStyleSheet: View {
    let theme: PasscodeGalleryTheme
    @ObservedObject var gallery: PasscodeGalleryManager
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mgr = laramgr.shared
    @State private var html: String?
    @AppStorage(EaglePasscodeFavorites.storageKey) private var favoritesJSON = "[]"

    private var isLiked: Bool {
        EaglePasscodeFavorites.decode(favoritesJSON).contains(theme.id)
    }

    private func toggleLike() {
        var favorites = EaglePasscodeFavorites.decode(favoritesJSON)
        let liked = favorites.insert(theme.id).inserted
        if !liked {
            favorites.remove(theme.id)
        }
        favoritesJSON = EaglePasscodeFavorites.encode(favorites)
        EagleLikes.shared.setLiked(.passcode, theme.id, liked: liked)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    EagleDeviceFrame {
                        if let html {
                            EaglePasscodeHTMLPreview(html: html)
                        } else {
                            LaraRemoteMediaPreview(
                                url: gallery.previewURL(for: theme),
                                animated: false,
                                contentMode: .fill,
                                showsRetry: false
                            )
                        }
                    }
                    .frame(maxWidth: 240)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.displayName)
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                            Text(theme.canInstall
                                ? theme.authorLine
                                : LaraL10n.text(en: "Preview only for now", es: "Por ahora, solo vista previa"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        EagleLikeButton(kind: .passcode, id: theme.id, isLiked: isLiked, onArtwork: false) {
                            toggleLike()
                        }
                        if let wallpaperID = theme.wallpaperID {
                            NavigationLink {
                                WallpaperGalleryView(matchingWallpaperID: wallpaperID)
                                    .navigationTitle(LaraL10n.text(en: "Matching wallpaper", es: "Fondo a juego"))
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                Image(systemName: "photo")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1) }
                            }
                            .buttonStyle(EaglePressableStyle(kind: .swatch))
                            .accessibilityLabel(LaraL10n.text(en: "Matching wallpaper", es: "Fondo a juego"))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Prepare takes the place of Use style until the iPhone is ready.
                if theme.canInstall {
                    EagleApplyBar(ready: mgr.sbxready) {
                        Button {
                            dismiss()
                            onUse()
                        } label: {
                            Text(LaraL10n.text(en: "Use style", es: "Usar estilo"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(EagleApplyButtonStyle(busy: gallery.isDownloading(theme)))
                        .disabled(gallery.isDownloading(theme))
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(LaraL10n.text(en: "Close", es: "Cerrar"))
                }
            }
            .task {
                guard theme.hasAnimatedPreview, html == nil else { return }
                html = try? await gallery.animatedPreviewHTML(for: theme)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Opened: no longer news.
        .onAppear { EagleNewItems.shared.markSeen(.passcode, theme.id) }
    }
}

private struct EaglePasscodeHTMLPreview: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        web.isUserInteractionEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedHTML: String?
    }
}
