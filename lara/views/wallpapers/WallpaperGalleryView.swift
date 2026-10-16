import SwiftUI
import Combine

private let nuggetWallpaperBaseURL = URL(
    string: "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/"
)!

enum WallpaperCatalogKind: String, CaseIterable, Identifiable {
    case community
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .community: return LaraL10n.text(en: "Community", es: "Comunidad")
        case .apple: return "Apple"
        }
    }

    var manifestURL: URL {
        let name = self == .community ? "wallpapers-custom.json" : "wallpapers-apple.json"
        return nuggetWallpaperBaseURL.appendingPathComponent(name)
    }
}

struct NuggetWallpaper: Decodable, Identifiable, Hashable {
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String?
    let contest: String?

    var id: String { url }

    var authorLine: String {
        guard let authors, !authors.isEmpty else {
            return LaraL10n.text(en: "Nugget collection", es: "Colección de Nugget")
        }
        return authors
    }

    var requiresIOS26: Bool {
        let details = "\(name) \(description ?? "") \(contest ?? "")".lowercased()
        return details.contains("ios 26")
    }

    var previewURL: URL? {
        URL(string: preview, relativeTo: nuggetWallpaperBaseURL)?.absoluteURL
    }

    var downloadURL: URL? {
        URL(string: url, relativeTo: nuggetWallpaperBaseURL)?.absoluteURL
    }
}

private enum EagleWallpaperFavorites {
    static let storageKey = "eagle.wallpapers.favoriteIDs"

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

enum CommunityWallpaperError: LocalizedError {
    case invalidResponse
    case invalidPackage
    case packageTooLarge
    case noDescriptors
    case tooManyDescriptors
    case requiresIOS26
    case unsupportedExtension

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return LaraL10n.text(
                en: "The catalog is unavailable right now. Check your connection and try again.",
                es: "No se pudo obtener el catálogo en este momento. Comprueba tu conexión e inténtalo otra vez."
            )
        case .invalidPackage:
            return LaraL10n.text(
                en: "This wallpaper package does not have a compatible structure.",
                es: "El archivo de este fondo no tiene una estructura compatible."
            )
        case .packageTooLarge:
            return LaraL10n.text(
                en: "This file is too large to process safely on your iPhone.",
                es: "El archivo supera el límite seguro de tamaño para procesarlo en el iPhone."
            )
        case .noDescriptors:
            return LaraL10n.text(
                en: "This package does not contain a wallpaper Eagle can install.",
                es: "Este paquete no contiene fondos que Eagle pueda instalar."
            )
        case .tooManyDescriptors:
            return LaraL10n.text(
                en: "This package contains too many wallpapers for one installation.",
                es: "El paquete contiene demasiados fondos para una sola instalación."
            )
        case .requiresIOS26:
            return LaraL10n.text(
                en: "This wallpaper requires iOS 26 because of the animations it uses.",
                es: "Este fondo requiere iOS 26 por las animaciones que utiliza."
            )
        case .unsupportedExtension:
            return LaraL10n.text(
                en: "This package uses a wallpaper category Eagle does not recognize yet.",
                es: "Este paquete usa una categoría de fondos que Eagle todavía no reconoce."
            )
        }
    }
}

private enum NuggetWallpaperService {
    static func fetch(_ kind: WallpaperCatalogKind, forceRefresh: Bool) async throws -> [NuggetWallpaper] {
        var request = URLRequest(url: kind.manifestURL)
        request.timeoutInterval = 30
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CommunityWallpaperError.invalidResponse
        }
        return try JSONDecoder().decode([NuggetWallpaper].self, from: data)
    }

    static func download(_ wallpaper: NuggetWallpaper) async throws -> Data {
        guard let url = wallpaper.downloadURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CommunityWallpaperError.invalidResponse
        }
        guard data.count <= TendiesInstaller.maximumCompressedSize else {
            throw CommunityWallpaperError.packageTooLarge
        }
        return data
    }
}

@MainActor
final class WallpaperCatalogManager: ObservableObject {
    static let shared = WallpaperCatalogManager()

    @Published private(set) var community: [NuggetWallpaper] = []
    @Published private(set) var apple: [NuggetWallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var installingID: String?
    @Published private(set) var resultMessage: String?
    @Published private(set) var didInstall = false

    func items(for kind: WallpaperCatalogKind) -> [NuggetWallpaper] {
        kind == .community ? community : apple
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let communityItems = NuggetWallpaperService.fetch(.community, forceRefresh: forceRefresh)
            async let appleItems = NuggetWallpaperService.fetch(.apple, forceRefresh: forceRefresh)
            let loaded = try await (communityItems, appleItems)
            community = loaded.0
            apple = loaded.1
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func install(_ wallpaper: NuggetWallpaper) async {
        guard installingID == nil else { return }
        guard laramgr.shared.sbxready else {
            resultMessage = LaraL10n.text(
                en: "Prepare Eagle before installing a wallpaper.",
                es: "Prepara el acceso de Eagle antes de instalar un fondo."
            )
            return
        }
        if wallpaper.requiresIOS26,
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            resultMessage = CommunityWallpaperError.requiresIOS26.localizedDescription
            return
        }

        installingID = wallpaper.id
        resultMessage = nil
        didInstall = false

        do {
            let data = try await NuggetWallpaperService.download(wallpaper)
            let result = try await Task.detached(priority: .userInitiated) {
                try TendiesInstaller.install(data: data)
            }.value
            let refreshed = PosterBoardWriter.refreshCollections()
            globallogger.log("(wallpaper) collection refresh requested, success=\(refreshed)")
            didInstall = true
            if result.installedCount == 0, result.existingCount > 0 {
                resultMessage = LaraL10n.text(
                    en: "\(wallpaper.name) is already imported. Open Wallpapers and select it; close Wallpapers from the app switcher if it does not appear immediately.",
                    es: "\(wallpaper.name) ya está importado. Abre Fondos y selecciónalo; si no aparece de inmediato, cierra Fondos desde el selector de apps."
                )
            } else if result.installedCount == 1 {
                resultMessage = LaraL10n.text(
                    en: "\(wallpaper.name) was imported and verified. Open Wallpapers and select it; close Wallpapers from the app switcher if it does not appear immediately.",
                    es: "\(wallpaper.name) se importó y verificó. Abre Fondos y selecciónalo; si no aparece de inmediato, cierra Fondos desde el selector de apps."
                )
            } else {
                resultMessage = LaraL10n.text(
                    en: "Imported and verified \(result.installedCount) wallpapers from \(wallpaper.name). Open Wallpapers and select one.",
                    es: "Se importaron y verificaron \(result.installedCount) fondos de \(wallpaper.name). Abre Fondos y selecciona uno."
                )
            }
        } catch {
            didInstall = false
            resultMessage = error.localizedDescription
        }
        installingID = nil
    }

    @discardableResult
    func openWallpaperPicker() -> Bool {
        let opened = "com.apple.PosterBoard".withCString { launch_app($0) } == 0
        globallogger.log("(wallpaper) PosterBoard launch success=\(opened)")
        if !opened {
            didInstall = false
            resultMessage = LaraL10n.text(
                en: "Eagle imported the wallpaper, but Wallpapers could not be opened. Open Wallpapers manually and select the new item.",
                es: "Eagle importó el fondo, pero no pudo abrir Fondos. Abre Fondos manualmente y selecciona el elemento nuevo."
            )
        }
        return opened
    }

    func clearResult() {
        resultMessage = nil
        didInstall = false
    }
}

struct WallpaperGalleryView: View {
    @ObservedObject private var gallery = WallpaperCatalogManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(EagleWallpaperFavorites.storageKey)
    private var favoriteIDsJSON = "[]"

    @AppStorage("eagle.wallpapers.category")
    private var category: WallpaperCatalogKind = .community
    @State private var searchText = ""
    @State private var showsFavoritesOnly = false

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        if horizontalSizeClass == .regular || verticalSizeClass == .compact {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ]
        }
        return [GridItem(.adaptive(minimum: 170), spacing: 12)]
    }

    private var displayedItems: [NuggetWallpaper] {
        let currentMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        var items = gallery.items(for: category).filter {
            currentMajorVersion >= 26 || !$0.requiresIOS26
        }
        if showsFavoritesOnly {
            let favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
            items = items.filter { favoriteIDs.contains($0.id) }
        }
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description ?? "").lowercased().contains(query) ||
            $0.authorLine.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("Colección", selection: $category) {
                    ForEach(WallpaperCatalogKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if !mgr.sbxready {
                    LaraAccessView(compact: true)
                }

                if gallery.isLoading && gallery.items(for: category).isEmpty {
                    loadingView
                } else if let error = gallery.errorMessage,
                          gallery.items(for: category).isEmpty {
                    errorView(error)
                } else if displayedItems.isEmpty {
                    emptyView
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        let favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
                        ForEach(displayedItems) { wallpaper in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    CommunityWallpaperDetail(wallpaper: wallpaper)
                                } label: {
                                    CommunityWallpaperCard(wallpaper: wallpaper)
                                }
                                .buttonStyle(EaglePressableStyle())

                                favoriteButton(
                                    for: wallpaper,
                                    favorite: favoriteIDs.contains(wallpaper.id)
                                )
                                    .padding(6)
                            }
                        }
                    }
                }

                Link(
                    "Catálogo oficial de Nugget Wallpapers",
                    destination: URL(string: "https://github.com/SerStars/Nugget-Wallpapers")!
                )
                .font(.footnote.weight(.medium))
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .searchable(
            text: $searchText,
            prompt: LaraL10n.text(en: "Search wallpaper or creator", es: "Buscar fondo o creador")
        )
        .refreshable { await gallery.load(forceRefresh: true) }
        .task {
            if gallery.community.isEmpty || gallery.apple.isEmpty {
                await gallery.load()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showsFavoritesOnly.toggle()
                } label: {
                    Image(systemName: showsFavoritesOnly ? "heart.fill" : "heart")
                }
                .accessibilityLabel(showsFavoritesOnly
                    ? LaraL10n.text(en: "Show all wallpapers", es: "Mostrar todos los fondos")
                    : LaraL10n.text(en: "Show favorite wallpapers", es: "Mostrar fondos favoritos"))
                .accessibilityValue(showsFavoritesOnly
                    ? LaraL10n.text(en: "Favorites only", es: "Solo favoritos")
                    : LaraL10n.text(en: "All wallpapers", es: "Todos los fondos"))
            }
        }
    }

    private func toggleFavorite(_ wallpaper: NuggetWallpaper) {
        var favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
        if !favoriteIDs.insert(wallpaper.id).inserted {
            favoriteIDs.remove(wallpaper.id)
        }
        favoriteIDsJSON = EagleWallpaperFavorites.encode(favoriteIDs)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func favoriteButton(
        for wallpaper: NuggetWallpaper,
        favorite: Bool
    ) -> some View {
        return Button {
            toggleFavorite(wallpaper)
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .font(.body.weight(.semibold))
                .foregroundStyle(favorite ? Color.pink : Color.primary)
                .eagleSymbolPop(favorite)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(EaglePressableStyle(kind: .swatch))
        .accessibilityLabel(favorite
            ? LaraL10n.text(en: "Remove from favorites", es: "Quitar de favoritos")
            : LaraL10n.text(en: "Add to favorites", es: "Agregar a favoritos"))
        .accessibilityValue(wallpaper.name)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                EagleRainbowSpinner(size: 22)
                Text("Cargando la colección…")
                    .font(.headline)
            }
            Text("Buscando fondos y preparando sus vistas previas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No pudimos cargar la colección", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Intentar de nuevo") {
                Task { await gallery.load(forceRefresh: true) }
            }
            .buttonStyle(.borderedProminent)
            // The contrasting colour on the black/white fill, grey while disabled.
            .eagleProminentLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.14), lineWidth: 1)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: showsFavoritesOnly ? "heart.slash" : "sparkles.rectangle.stack")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyTitle: String {
        if showsFavoritesOnly {
            return searchText.isEmpty
                ? LaraL10n.text(
                    en: "No favorites in this collection",
                    es: "No hay favoritos en esta colección"
                )
                : LaraL10n.text(
                    en: "No matching favorites",
                    es: "No hay favoritos coincidentes"
                )
        }
        return LaraL10n.text(en: "No results", es: "Sin resultados")
    }

    private var emptyMessage: String {
        if showsFavoritesOnly && searchText.isEmpty {
            return LaraL10n.text(
                en: "Tap the heart on a wallpaper to save it here.",
                es: "Toca el corazón de un fondo para guardarlo aquí."
            )
        }
        return LaraL10n.text(
            en: "Try another name or creator.",
            es: "Prueba con otro nombre o creador."
        )
    }
}

private struct CommunityWallpaperCard: View {
    let wallpaper: NuggetWallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LaraRemoteMediaPreview(
                url: wallpaper.previewURL,
                animated: false,
                contentMode: .fill,
                showsRetry: false
            )
            .frame(maxWidth: .infinity)
            .frame(height: 205)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(wallpaper.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(wallpaper.authorLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if wallpaper.requiresIOS26 {
                    Text("iOS 26")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct CommunityWallpaperDetail: View {
    let wallpaper: NuggetWallpaper

    @ObservedObject private var gallery = WallpaperCatalogManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @AppStorage(EagleWallpaperFavorites.storageKey)
    private var favoriteIDsJSON = "[]"

    private var isInstalling: Bool {
        gallery.installingID == wallpaper.id
    }

    private var isIncompatible: Bool {
        wallpaper.requiresIOS26 && ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26
    }

    private var isFavorite: Bool {
        EagleWallpaperFavorites.decode(favoriteIDsJSON).contains(wallpaper.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let previewURL = wallpaper.previewURL {
                    LaraRemoteMediaPreview(
                        url: previewURL,
                        animated: true,
                        contentMode: .fit,
                        showsRetry: true,
                        background: .black
                    )
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(wallpaper.name)
                        .font(.title2.bold())
                    Text(wallpaper.authorLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let description = wallpaper.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    if let contest = wallpaper.contest, !contest.isEmpty {
                        Text(contest)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                if isIncompatible {
                    Label("Requiere iOS 26", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Text("Los fondos y sus vistas previas pertenecen a sus respectivos creadores. Eagle instala una copia local y no modifica otros fondos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        // "Add to Wallpapers" stays fixed at the bottom; Prepare takes its place until Eagle is ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: mgr.sbxready) {
                Button {
                    Task { await gallery.install(wallpaper) }
                } label: {
                    HStack {
                        if isInstalling {
                            ProgressView().tint(EagleVisualTheme.actionText)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(isInstalling
                            ? LaraL10n.text(en: "Downloading and installing…", es: "Descargando e instalando…")
                            : LaraL10n.text(en: "Add to Wallpapers", es: "Agregar a Fondos"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EagleApplyButtonStyle(busy: isInstalling))
                .disabled(!mgr.sbxready || gallery.installingID != nil || isIncompatible)
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("Vista previa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    var favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
                    if !favoriteIDs.insert(wallpaper.id).inserted {
                        favoriteIDs.remove(wallpaper.id)
                    }
                    favoriteIDsJSON = EagleWallpaperFavorites.encode(favoriteIDs)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Color.pink : Color.primary)
                }
                .accessibilityLabel(isFavorite
                    ? LaraL10n.text(en: "Remove from favorites", es: "Quitar de favoritos")
                    : LaraL10n.text(en: "Add to favorites", es: "Agregar a favoritos"))
                .accessibilityValue(wallpaper.name)
            }
        }
        .onChange(of: gallery.resultMessage) { value in
            guard let value else { return }
            let installed = gallery.didInstall
            EagleNotifications.shared.show(title: LaraL10n.text(en: "Wallpapers", es: "Fondos"),
                message: value, kind: installed ? .success : .error,
                actionTitle: installed ? LaraL10n.text(en: "Open Wallpapers", es: "Abrir Fondos") : nil,
                action: installed ? { gallery.openWallpaperPicker() } : nil)
            gallery.clearResult()
        }
    }
}

nonisolated struct TendiesInstallResult: Sendable {
    let installedCount: Int
    let existingCount: Int
    let installedDestinations: [URL]
}

nonisolated private struct TendiesDescriptor: Sendable {
    let url: URL
    let extensionIdentifier: String
}

nonisolated enum TendiesInstaller {
    static let maximumCompressedSize = 120 * 1024 * 1024
    private static let maximumExpandedSize: UInt64 = 1_200 * 1024 * 1024
    private static let maximumDescriptors = 64

    static func install(data: Data) throws -> TendiesInstallResult {
        guard data.count <= maximumCompressedSize else {
            throw CommunityWallpaperError.packageTooLarge
        }

        let archive = try ZipArchive(data: data)
        let expandedSize = archive.entries.reduce(UInt64(0)) { partial, entry in
            partial.addingReportingOverflow(entry.uncompressedSize).overflow
                ? UInt64.max
                : partial + entry.uncompressedSize
        }
        guard expandedSize <= maximumExpandedSize else {
            throw CommunityWallpaperError.packageTooLarge
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("EagleTendies-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try extract(archive, to: root)
        let descriptors = try findDescriptors(in: root)
        log("(wallpaper) found \(descriptors.count) installable descriptor(s)")
        guard !descriptors.isEmpty else { throw CommunityWallpaperError.noDescriptors }
        guard descriptors.count <= maximumDescriptors else {
            throw CommunityWallpaperError.tooManyDescriptors
        }

        var installed: [URL] = []
        var existingCount = 0
        do {
            for descriptor in descriptors {
                log(
                    "(wallpaper) preparing \(descriptor.url.lastPathComponent) for \(descriptor.extensionIdentifier)"
                )
                // Pocket Poster randomizes every imported descriptor,
                // including descriptors packaged under Container/. Keeping a
                // packaged identity makes PosterBoard treat a freshly copied
                // item as an already-known poster and it may never appear in
                // Collections.
                try randomize(descriptor: descriptor.url)
                let result = try PosterBoardWriter.install(
                    descriptor: descriptor.url,
                    extensionIdentifier: descriptor.extensionIdentifier,
                    preserveDescriptorName: false
                )
                log(
                    "(wallpaper) verified descriptor at \(result.destination.lastPathComponent), created=\(result.wasCreated)"
                )
                if result.wasCreated {
                    installed.append(result.destination)
                } else {
                    existingCount += 1
                }
            }
            return TendiesInstallResult(
                installedCount: installed.count,
                existingCount: existingCount,
                installedDestinations: installed
            )
        } catch {
            for destination in installed {
                try? fm.removeItem(at: destination)
            }
            throw error
        }
    }

    private static func extract(_ archive: ZipArchive, to root: URL) throws {
        let fm = FileManager.default
        var extractedFiles = 0

        for entry in archive.entries {
            let normalized = entry.path.replacingOccurrences(of: "\\", with: "/")
            let archiveComponents = normalized.split(separator: "/", omittingEmptySubsequences: true)
            if archiveComponents.contains(where: { $0.caseInsensitiveCompare("__MACOSX") == .orderedSame }) ||
                archiveComponents.last?.hasPrefix("._") == true ||
                archiveComponents.last == ".DS_Store" {
                continue
            }

            // Build the destination one validated relative component at a time.
            // A second string-prefix check used to reject every valid entry on
            // device because iOS represented the temporary container through
            // different /var and /private/var aliases.
            let components = archiveComponents.filter { $0 != "." }
            guard !components.isEmpty,
                  !normalized.hasPrefix("/"),
                  !normalized.contains("\0"),
                  !components.contains("..") else {
                log("(wallpaper) ignored unsafe archive entry: \(entry.path)")
                continue
            }

            var output = root
            for component in components {
                output.appendPathComponent(String(component), isDirectory: false)
            }

            if entry.isDirectory {
                try fm.createDirectory(at: output, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try archive.extract(entry).write(to: output, options: .atomic)
                extractedFiles += 1
            }
        }

        log("(wallpaper) extracted \(extractedFiles) files into the temporary package")
    }

    private static func findDescriptors(in root: URL) throws -> [TendiesDescriptor] {
        let markerName = "com.apple.posterkit.provider.descriptor.identifier"
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CommunityWallpaperError.invalidPackage
        }

        var descriptors: [TendiesDescriptor] = []
        for case let file as URL in enumerator {
            let descriptor: URL
            if file.lastPathComponent == markerName {
                descriptor = file.deletingLastPathComponent()
            } else if file.lastPathComponent.caseInsensitiveCompare("versions") == .orderedSame,
                      (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                // Older community packages do not always include the descriptor
                // identifier marker. Nugget recognizes them from the descriptor
                // directory and its versions folder, so Lara must do the same.
                let candidate = file.deletingLastPathComponent()
                guard candidate.deletingLastPathComponent().lastPathComponent
                    .lowercased().contains("descriptor") else { continue }
                descriptor = candidate
            } else {
                continue
            }

            let versions = descriptor.appendingPathComponent("versions", isDirectory: true)
            var versionsIsDirectory: ObjCBool = false
            guard fm.fileExists(atPath: versions.path, isDirectory: &versionsIsDirectory),
                  versionsIsDirectory.boolValue else { continue }

            let relativeComponents = descriptor.pathComponents.dropFirst(root.pathComponents.count)
            let extensionIdentifier = try posterExtension(for: Array(relativeComponents))

            if !descriptors.contains(where: { $0.url == descriptor }) {
                descriptors.append(TendiesDescriptor(
                    url: descriptor,
                    extensionIdentifier: extensionIdentifier
                ))
            }
        }
        return descriptors
    }

    private static func posterExtension(for pathComponents: [String]) throws -> String {
        if let extensionsIndex = pathComponents.firstIndex(where: { $0.caseInsensitiveCompare("Extensions") == .orderedSame }),
           pathComponents.indices.contains(extensionsIndex + 1) {
            let identifier = pathComponents[extensionsIndex + 1]
            guard [
                PosterBoardWriter.collectionsExtension,
                PosterBoardWriter.mercuryExtension,
                PosterBoardWriter.photosExtension
            ].contains(identifier) else {
                throw CommunityWallpaperError.unsupportedExtension
            }
            return identifier
        }

        let descriptorFolder = pathComponents
            .dropLast()
            .last(where: { $0.lowercased().contains("descriptor") })?
            .lowercased() ?? "descriptors"
        if descriptorFolder.contains("mercury") {
            return PosterBoardWriter.mercuryExtension
        }
        if descriptorFolder.contains("video") || descriptorFolder.contains("photos") {
            return PosterBoardWriter.photosExtension
        }
        return PosterBoardWriter.collectionsExtension
    }

    private static func randomize(descriptor: URL) throws {
        let identifier = Int.random(in: 10_000...99_999)
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: descriptor,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var plistUpdates: [(url: URL, data: Data)] = []
        for case let file as URL in enumerator {
            do {
                switch file.lastPathComponent {
                case "com.apple.posterkit.provider.contents.userInfo":
                    let data = try updatedPlistData(at: file) { plist in
                        _ = replaceValue(
                            forKey: "wallpaperRepresentingIdentifier",
                            with: identifier,
                            in: &plist
                        )
                    }
                    plistUpdates.append((file, data))
                case "Wallpaper.plist":
                    let data = try updatedPlistData(at: file) { plist in
                        plist["identifier"] = identifier
                    }
                    plistUpdates.append((file, data))
                default:
                    continue
                }
            } catch {
                // Pocket Poster tolerates opaque legacy metadata one file at a
                // time, but still assigns the descriptor a fresh top-level
                // identity. Aborting here leaves PosterBoard seeing a duplicate
                // and the newly imported wallpaper can remain invisible.
                log(
                    "(wallpaper) skipped legacy identity field in \(file.lastPathComponent): \(error.localizedDescription)"
                )
                continue
            }
        }

        for update in plistUpdates {
            try update.data.write(to: update.url, options: .atomic)
        }
        try Data("\(identifier)".utf8).write(
            to: descriptor.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"),
            options: .atomic
        )
    }

    private static func updatedPlistData(
        at url: URL,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any] else {
            throw CommunityWallpaperError.invalidPackage
        }
        mutate(&plist)
        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: format == .openStep ? .xml : format,
            options: 0
        )
    }

    @discardableResult
    private static func replaceValue(
        forKey key: String,
        with value: Any,
        in dictionary: inout [String: Any]
    ) -> Bool {
        var replaced = false
        for currentKey in Array(dictionary.keys) {
            if currentKey == key {
                dictionary[currentKey] = value
                replaced = true
            } else if var nested = dictionary[currentKey] as? [String: Any],
                      replaceValue(forKey: key, with: value, in: &nested) {
                dictionary[currentKey] = nested
                replaced = true
            }
        }
        return replaced
    }

    private static func log(_ message: String) {
        Task { @MainActor in
            globallogger.log(message)
        }
    }
}
