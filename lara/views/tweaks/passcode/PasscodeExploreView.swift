//
//  PasscodeExploreView.swift
//  lara
//
//  Created by neonmodder123 on 20/05/2026.
//

import SwiftUI

private enum EaglePasscodeFavorites {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(EaglePasscodeFavorites.storageKey)
    private var favoriteThemeIDsJSON = "[]"

    @State private var searchTerm = ""
    @State private var showsFavoritesOnly = false
    @State private var alertMessage: String?
    var onImport: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    private func handleDownload(_ theme: PasscodeGalleryTheme) async {
        do {
            try await gallery.downloadAndImport(theme)
            let dest = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(theme.name + ".passthm")
            onImport?(dest)
            dismiss()
        } catch { alertMessage = error.localizedDescription }
    }

    private var displayed: [PasscodeGalleryTheme] {
        var themes = gallery.themes
        if showsFavoritesOnly {
            let favorites = EaglePasscodeFavorites.decode(favoriteThemeIDsJSON)
            themes = themes.filter { favorites.contains($0.id) }
        }
        guard !searchTerm.isEmpty else { return themes }
        return themes.filter {
            "\($0.name) \($0.description) \($0.authorLine)".range(
                of: searchTerm,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) != nil
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 155), spacing: 12)]
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
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        let favoriteIDs = EaglePasscodeFavorites.decode(favoriteThemeIDsJSON)
                        ForEach(displayed) { theme in
                            PasscodeGalleryCard(
                                theme: theme,
                                previewURL: gallery.previewURL(for: theme),
                                isDownloading: gallery.isDownloading(theme),
                                isFavorite: favoriteIDs.contains(theme.id),
                                onToggleFavorite: { toggleFavorite(theme) }
                            ) { Task { await handleDownload(theme) } }
                        }
                    }
                }

                Link(
                    LaraL10n.text(
                        en: "Official Nugget collection",
                        es: "Colección oficial de Nugget"
                    ),
                    destination: URL(string: "https://github.com/SerStars/Nugget-Wallpapers")!
                )
                .font(.footnote.weight(.medium))
            }
            .padding(16)
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "Explore styles", es: "Explorar estilos"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchTerm,
            prompt: LaraL10n.text(en: "Search style or creator", es: "Buscar estilo o creador")
        )
        .refreshable { await gallery.loadThemes(forceRefresh: true) }
        .task { if gallery.themes.isEmpty { await gallery.loadThemes() } }
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
    }

    private var emptyTitle: String {
        if showsFavoritesOnly {
            return searchTerm.isEmpty
                ? LaraL10n.text(en: "No favorite styles yet", es: "Todavía no hay estilos favoritos")
                : LaraL10n.text(en: "No matching favorites", es: "No hay favoritos coincidentes")
        }
        return LaraL10n.text(en: "No styles found", es: "No encontramos estilos")
    }

    private var emptyMessage: String {
        if showsFavoritesOnly && searchTerm.isEmpty {
            return LaraL10n.text(
                en: "Tap the heart on a style to save it here.",
                es: "Toca el corazón de un estilo para guardarlo aquí."
            )
        }
        return LaraL10n.text(
            en: "Try another name or creator.",
            es: "Prueba con otro nombre o creador."
        )
    }

    private func toggleFavorite(_ theme: PasscodeGalleryTheme) {
        var favorites = EaglePasscodeFavorites.decode(favoriteThemeIDsJSON)
        if !favorites.insert(theme.id).inserted {
            favorites.remove(theme.id)
        }
        favoriteThemeIDsJSON = EaglePasscodeFavorites.encode(favorites)
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

private struct PasscodeGalleryCard: View {
    let theme: PasscodeGalleryTheme
    let previewURL: URL?
    let isDownloading: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LaraRemoteMediaPreview(
                url: previewURL,
                animated: false,
                contentMode: .fit,
                showsRetry: false
            )
            .frame(maxWidth: .infinity)
            .frame(height: 190)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        // Long names shrink a little before they are cut short.
                        Text(theme.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        Text(theme.authorLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? Color.pink : Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .accessibilityLabel(isFavorite
                        ? LaraL10n.text(en: "Remove from favorites", es: "Quitar de favoritos")
                        : LaraL10n.text(en: "Add to favorites", es: "Agregar a favoritos"))
                    .accessibilityValue(theme.name)
                }

                if !theme.description.isEmpty {
                    Text(theme.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(action: onDownload) {
                    HStack {
                        if isDownloading { ProgressView().controlSize(.small).tint(Color(uiColor: .systemBackground)) } else { Image(systemName: "arrow.down.circle") }
                        Text(LaraL10n.text(en: "Use style", es: "Usar estilo"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                // The contrasting colour on the black/white fill, grey while disabled.
                .eagleProminentLabel()
                .disabled(isDownloading)
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.05), lineWidth: 1)
        }
    }

}
