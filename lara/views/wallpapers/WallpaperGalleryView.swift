import SwiftUI
import Combine
import CryptoKit
import AVKit

private let eagleGalleryBaseURL = URL(
    string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/"
)!

private let eagleWallpaperCatalogURL = eagleGalleryBaseURL
    .appendingPathComponent("catalogs/wallpaper-v1.json")

struct EagleWallpaper: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    /// The name in each interface language ("en", "es", "zh-Hans", "ru", "vi"); English, then `name`, when one is missing.
    let names: [String: String]?
    let url: String
    let preview: String
    let stillPreview: String?
    let motionPreview: String?
    let isBundled: Bool
    let foregroundPreview: String?
    let foregroundSha256: String?
    let foregroundByteCount: Int?
    let sha256: String
    let byteCount: Int
    let minimumIOSMajor: Int
    let authors: String?
    let contest: String?
    /// "personal" for Leonardo's own collection, shown in its own section.
    let collection: String?
    /// False for the passcode styles' companion wallpapers: kept for "Matching wallpaper", left out of
    /// the gallery itself.
    let listed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, names, description, url, preview, stillPreview, motionPreview, isBundled, foregroundPreview
        case foregroundSha256, foregroundByteCount, sha256, byteCount
        case minimumIOSMajor, authors, contest, collection, listed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        names = try container.decodeIfPresent([String: String].self, forKey: .names)
        url = try container.decode(String.self, forKey: .url)
        preview = try container.decode(String.self, forKey: .preview)
        stillPreview = try container.decodeIfPresent(String.self, forKey: .stillPreview)
        motionPreview = try container.decodeIfPresent(String.self, forKey: .motionPreview)
        isBundled = try container.decodeIfPresent(Bool.self, forKey: .isBundled) ?? false
        foregroundPreview = try container.decodeIfPresent(String.self, forKey: .foregroundPreview)
        foregroundSha256 = try container.decodeIfPresent(String.self, forKey: .foregroundSha256)
        foregroundByteCount = try container.decodeIfPresent(Int.self, forKey: .foregroundByteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        minimumIOSMajor = try container.decodeIfPresent(Int.self, forKey: .minimumIOSMajor) ?? 17
        authors = try container.decodeIfPresent(String.self, forKey: .authors)
        contest = try container.decodeIfPresent(String.self, forKey: .contest)
        collection = try container.decodeIfPresent(String.self, forKey: .collection)
        listed = try container.decodeIfPresent(Bool.self, forKey: .listed) ?? true
    }

    var isPersonal: Bool {
        isBundled || collection == "personal"
    }

    var displayName: String {
        if let localized = names?[LaraL10n.language.rawValue], !localized.isEmpty { return localized }
        // A language the catalog does not cover yet reads the English name, not the Spanish `name`.
        if LaraL10n.language != .spanish, let english = names?["en"], !english.isEmpty { return english }
        return name
    }

    var authorLine: String {
        // The personal collection is named in the interface language.
        if isPersonal {
            return LaraL10n.text(en: "Personal collection", es: "Colección personal")
        }
        guard let authors, !authors.isEmpty else {
            return "Eagle"
        }
        return authors
    }

    var isCompatibleWithCurrentIOS: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= minimumIOSMajor
    }

    var previewURL: URL? {
        if isBundled { return bundledURL(preview) }
        return URL(string: preview, relativeTo: eagleGalleryBaseURL)?.absoluteURL
    }

    var stillPreviewURL: URL? {
        stillPreview.flatMap { isBundled ? bundledURL($0) : URL(string: $0, relativeTo: eagleGalleryBaseURL)?.absoluteURL }
    }

    var motionPreviewURL: URL? {
        motionPreview.flatMap { isBundled ? bundledURL($0) : URL(string: $0, relativeTo: eagleGalleryBaseURL)?.absoluteURL }
    }

    var foregroundPreviewURL: URL? {
        foregroundPreview.flatMap { URL(string: $0, relativeTo: eagleGalleryBaseURL)?.absoluteURL }
    }

    var downloadURL: URL? {
        if isBundled { return bundledURL(url) }
        return URL(string: url, relativeTo: eagleGalleryBaseURL)?.absoluteURL
    }

    private func bundledURL(_ name: String) -> URL? {
        guard !name.isEmpty,
              name == (name as NSString).lastPathComponent,
              name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) }),
              let root = Bundle.main.resourceURL else { return nil }
        let resource = root.appendingPathComponent("EaglePrivateWallpapers", isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: resource.path) ? resource : nil
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

enum EagleWallpaperError: LocalizedError {
    case invalidResponse
    case invalidPackage
    case packageTooLarge
    case packageIntegrity
    case noDescriptors
    case tooManyDescriptors
    case requiresIOS(Int)
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
        case .packageIntegrity:
            return LaraL10n.text(
                en: "The downloaded wallpaper does not match the published package.",
                es: "El fondo descargado no coincide con el paquete publicado."
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
        case .requiresIOS(let major):
            return LaraL10n.text(
                en: "This wallpaper requires iOS \(major).",
                es: "Este fondo requiere iOS \(major)."
            )
        case .unsupportedExtension:
            return LaraL10n.text(
                en: "This package uses a wallpaper category Eagle does not recognize yet.",
                es: "Este paquete usa una categoría de fondos que Eagle todavía no reconoce."
            )
        }
    }
}

private enum EagleWallpaperService {
    static func fetch(forceRefresh: Bool) async throws -> [EagleWallpaper] {
        let bundled = try bundledWallpapers()
        do {
            let remote = try await fetchRemote(forceRefresh: forceRefresh)
            let localIDs = Set(bundled.map(\.id))
            return bundled + remote.filter { !localIDs.contains($0.id) }
        } catch {
            if !bundled.isEmpty { return bundled }
            throw error
        }
    }

    private static func bundledWallpapers() throws -> [EagleWallpaper] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json",
                                        subdirectory: "EaglePrivateWallpapers") else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 1024 * 1024 else { throw EagleWallpaperError.invalidPackage }
        struct Manifest: Decodable {
            let schemaVersion: Int
            let wallpapers: [EagleWallpaper]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.wallpapers.count <= 64,
              Set(manifest.wallpapers.map(\.id)).count == manifest.wallpapers.count,
              manifest.wallpapers.allSatisfy({ item in
                  item.isBundled && !item.id.isEmpty &&
                  item.id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }) &&
                  item.byteCount > 0 && item.byteCount <= TendiesInstaller.maximumCompressedSize &&
                  (16...26).contains(item.minimumIOSMajor) &&
                  item.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil &&
                  item.downloadURL?.isFileURL == true &&
                  item.previewURL?.isFileURL == true &&
                  item.stillPreviewURL?.isFileURL == true &&
                  item.motionPreviewURL?.isFileURL == true
              }) else { throw EagleWallpaperError.invalidPackage }
        return manifest.wallpapers
    }

    /// Still and motion previews may only come from Eagle-Gallery's wallpaper previews.
    private static func isGalleryPreview(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "raw.githubusercontent.com" &&
            url.path.hasPrefix("/leonardob8777-bit/Eagle-Gallery/main/previews/wallpapers/")
    }

    private static func fetchRemote(forceRefresh: Bool) async throws -> [EagleWallpaper] {
        var request = URLRequest(url: eagleWallpaperCatalogURL)
        request.timeoutInterval = 30
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EagleWallpaperError.invalidResponse
        }
        guard data.count <= 1024 * 1024 else { throw EagleWallpaperError.invalidResponse }
        struct Manifest: Decodable {
            let schemaVersion: Int
            let wallpapers: [EagleWallpaper]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1,
              manifest.wallpapers.count <= 1000,
              Set(manifest.wallpapers.map(\.id)).count == manifest.wallpapers.count,
              manifest.wallpapers.allSatisfy({ item in
                  !item.id.isEmpty &&
                  item.id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }) &&
                  item.byteCount > 0 && item.byteCount <= TendiesInstaller.maximumCompressedSize &&
                  (16...26).contains(item.minimumIOSMajor) &&
                  item.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil &&
                  !item.isBundled && item.downloadURL?.scheme == "https" && item.previewURL?.scheme == "https" &&
                  (item.stillPreview == nil || isGalleryPreview(item.stillPreviewURL)) &&
                  (item.motionPreview == nil || isGalleryPreview(item.motionPreviewURL)) &&
                  ((item.foregroundPreview == nil && item.foregroundSha256 == nil && item.foregroundByteCount == nil) ||
                   (item.foregroundPreviewURL?.scheme == "https" &&
                    item.foregroundPreviewURL?.host == "raw.githubusercontent.com" &&
                    item.foregroundPreviewURL?.path.hasPrefix("/leonardob8777-bit/Eagle-Gallery/main/previews/wallpapers/foreground/") == true &&
                    item.foregroundByteCount.map { $0 > 0 && $0 <= 20 * 1024 * 1024 } == true &&
                    item.foregroundSha256?.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil))
              }) else { throw EagleWallpaperError.invalidResponse }
        return manifest.wallpapers
    }

    static func download(_ wallpaper: EagleWallpaper) async throws -> Data {
        guard let url = wallpaper.downloadURL else { throw URLError(.badURL) }
        let data: Data
        if wallpaper.isBundled {
            guard url.isFileURL else { throw EagleWallpaperError.invalidPackage }
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            let (downloaded, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw EagleWallpaperError.invalidResponse
            }
            data = downloaded
        }
        guard data.count == wallpaper.byteCount,
              data.count <= TendiesInstaller.maximumCompressedSize,
              Data(SHA256.hash(data: data)).map({ String(format: "%02x", $0) }).joined() == wallpaper.sha256.lowercased() else {
            throw EagleWallpaperError.packageIntegrity
        }
        return data
    }
}

@MainActor
final class WallpaperCatalogManager: ObservableObject {
    static let shared = WallpaperCatalogManager()

    @Published private(set) var wallpapers: [EagleWallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var installingID: String?
    @Published private(set) var resultMessage: String?
    @Published private(set) var didInstall = false

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            wallpapers = try await EagleWallpaperService.fetch(forceRefresh: forceRefresh)
            EagleNewItems.shared.observe(.wallpaper, ids: wallpapers.filter(\.listed).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func install(_ wallpaper: EagleWallpaper) async {
        guard installingID == nil else { return }
        // Prepared access, or PosterBoard's saved UUID (Coconut's way, no preparing each time).
        let prepared = laramgr.shared.sbxready
        guard prepared || EaglePosterBoardUUID.allowsInstallWithoutPreparing else {
            resultMessage = LaraL10n.text(
                en: "Prepare Eagle before installing a wallpaper.",
                es: "Prepara el acceso de Eagle antes de instalar un fondo."
            )
            return
        }
        if !wallpaper.isCompatibleWithCurrentIOS {
            resultMessage = EagleWallpaperError.requiresIOS(wallpaper.minimumIOSMajor).localizedDescription
            return
        }

        installingID = wallpaper.id
        resultMessage = nil
        didInstall = false

        do {
            let data = try await EagleWallpaperService.download(wallpaper)
            let result = try await Task.detached(priority: .userInitiated) {
                try TendiesInstaller.install(data: data)
            }.value
            // Coconut never refreshes collections or changes the language; Eagle keeps its refresh
            // only on the prepared route, where it can write PosterBoard's preferences.
            if prepared {
                let refreshed = PosterBoardWriter.refreshCollections()
                globallogger.log("(wallpaper) collection refresh requested, success=\(refreshed)")
            }
            didInstall = true
            if !prepared {
                // Saved-UUID route: the copy cannot be read back, so no "verified" claim (as Coconut).
                resultMessage = LaraL10n.text(
                    en: "Eagle sent \(wallpaper.displayName) to Wallpapers. If it is not there yet, close Wallpapers from the app switcher and look in Collections.",
                    es: "Eagle envió \(wallpaper.displayName) a Fondos. Si todavía no aparece, cierra Fondos desde el selector de apps y búscalo en Colecciones."
                )
            } else if result.installedCount == 0, result.existingCount > 0 {
                resultMessage = LaraL10n.text(
                    en: "\(wallpaper.displayName) is already imported. Open Wallpapers and select it; close Wallpapers from the app switcher if it does not appear immediately.",
                    es: "\(wallpaper.displayName) ya está importado. Abre Fondos y selecciónalo; si no aparece de inmediato, cierra Fondos desde el selector de apps."
                )
            } else if result.installedCount == 1 {
                resultMessage = LaraL10n.text(
                    en: "\(wallpaper.displayName) was imported and verified. Open Wallpapers and select it; close Wallpapers from the app switcher if it does not appear immediately.",
                    es: "\(wallpaper.displayName) se importó y verificó. Abre Fondos y selecciónalo; si no aparece de inmediato, cierra Fondos desde el selector de apps."
                )
            } else {
                resultMessage = LaraL10n.text(
                    en: "Imported and verified \(result.installedCount) wallpapers from \(wallpaper.displayName). Open Wallpapers and select one.",
                    es: "Se importaron y verificaron \(result.installedCount) fondos de \(wallpaper.displayName). Abre Fondos y selecciona uno."
                )
            }
        } catch {
            didInstall = false
            resultMessage = error.localizedDescription
        }
        installingID = nil
        // Read now: the screen shows and clears the result while this waits.
        if didInstall {
            // Like Coconut: let the move settle, then open the wallpaper gallery.
            try? await Task.sleep(nanoseconds: 350_000_000)
            openWallpaperPicker()
        }
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
    let matchingWallpaperID: String?
    @ObservedObject private var gallery = WallpaperCatalogManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @ObservedObject private var likes = EagleLikes.shared
    @ObservedObject private var newItems = EagleNewItems.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(EagleWallpaperFavorites.storageKey)
    private var favoriteIDsJSON = "[]"

    @State private var searchText = ""
    @State private var showsFavoritesOnly = false

    init(matchingWallpaperID: String? = nil) {
        self.matchingWallpaperID = matchingWallpaperID
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        }
        if horizontalSizeClass == .regular || verticalSizeClass == .compact {
            return [GridItem(.adaptive(minimum: 130), spacing: 14)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
    }

    private var displayedItems: [EagleWallpaper] {
        var items = gallery.wallpapers.filter(\.isCompatibleWithCurrentIOS)
        if let matchingWallpaperID {
            items = items.filter { $0.id == matchingWallpaperID }
        } else {
            items = items.filter(\.listed)
        }
        if showsFavoritesOnly {
            let favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
            items = items.filter { favoriteIDs.contains($0.id) }
        }
        // Most liked first, in every section and in search results.
        items = likes.sortedByLikes(items, .wallpaper, id: \.id)
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query) ||
            ($0.description ?? "").lowercased().contains(query) ||
            $0.authorLine.lowercased().contains(query)
        }
    }

    /// The plain catalogue (no search, no favourites filter, not a single matching wallpaper) is laid
    /// out as a showcase: one featured wallpaper, then the personal collection and Eagle's gallery.
    private var showsShowcase: Bool {
        matchingWallpaperID == nil && !showsFavoritesOnly && searchText.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if gallery.isLoading && gallery.wallpapers.isEmpty {
                    loadingView
                } else if let error = gallery.errorMessage,
                          gallery.wallpapers.isEmpty {
                    errorView(error)
                } else if displayedItems.isEmpty {
                    emptyView
                } else if showsShowcase {
                    showcase
                } else {
                    grid(displayedItems)
                }
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
            if gallery.wallpapers.isEmpty {
                await gallery.load()
            }
        }
        .task {
            await EagleLikes.shared.refresh(.wallpaper, favorites: EagleWallpaperFavorites.decode(favoriteIDsJSON))
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

    @ViewBuilder
    private var showcase: some View {
        let items = displayedItems
        let personal = items.filter(\.isPersonal)
        let eagle = items.filter { !$0.isPersonal }

        if !personal.isEmpty {
            section(LaraL10n.text(en: "Personal collection", es: "Colección personal"), personal)
        }
        if !eagle.isEmpty {
            section(LaraL10n.text(en: "Eagle Gallery", es: "Galería Eagle"), eagle)
        }
    }

    private func section(_ title: String, _ items: [EagleWallpaper]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(items.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .eagleBackdropText()
            .padding(.horizontal, 4)
            grid(items)
        }
    }

    private func grid(_ items: [EagleWallpaper]) -> some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
            let favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
            // One HOT tag for the whole gallery: the most liked wallpaper on screen.
            let hotID = likes.hottest(.wallpaper, among: displayedItems.map(\.id))
            ForEach(items) { wallpaper in
                let favorite = favoriteIDs.contains(wallpaper.id)
                VStack(spacing: 8) {
                    NavigationLink {
                        EagleWallpaperDetail(wallpaper: wallpaper)
                    } label: {
                        EaglePhoneFrame(wallpaper: wallpaper)
                    }
                    .buttonStyle(EaglePressableStyle())
                    .contextMenu {
                        Button {
                            toggleFavorite(wallpaper)
                        } label: {
                            Label(
                                favorite
                                    ? LaraL10n.text(en: "Remove like", es: "Quitar me gusta")
                                    : LaraL10n.text(en: "Like", es: "Me gusta"),
                                systemImage: favorite ? "heart.slash" : "heart"
                            )
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if wallpaper.id == hotID {
                                EagleHotBadge()
                                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                            if newItems.isNew(.wallpaper, wallpaper.id) {
                                EagleNewBadge()
                            }
                        }
                        .padding(.top, 10)
                        .padding(.leading, 9)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        EagleLikeButton(kind: .wallpaper, id: wallpaper.id, isLiked: favorite) {
                            toggleFavorite(wallpaper)
                        }
                        .padding(2)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hotID)

                    Text(wallpaper.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .eagleBackdropText()
                }
            }
        }
    }

    private func toggleFavorite(_ wallpaper: EagleWallpaper) {
        var favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
        let liked = favoriteIDs.insert(wallpaper.id).inserted
        if !liked {
            favoriteIDs.remove(wallpaper.id)
        }
        favoriteIDsJSON = EagleWallpaperFavorites.encode(favoriteIDs)
        EagleLikes.shared.setLiked(.wallpaper, wallpaper.id, liked: liked)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                    en: "No favorite wallpapers yet",
                    es: "Todavía no hay fondos favoritos"
                )
                : LaraL10n.text(
                    en: "No matching favorites",
                    es: "No hay favoritos coincidentes"
                )
        }
        return searchText.isEmpty
            ? LaraL10n.text(en: "Eagle wallpapers are coming soon", es: "Pronto habrá fondos Eagle")
            : LaraL10n.text(en: "No results", es: "Sin resultados")
    }

    private var emptyMessage: String {
        if showsFavoritesOnly && searchText.isEmpty {
            return LaraL10n.text(
                en: "Tap the heart on a wallpaper to save it here.",
                es: "Toca el corazón de un fondo para guardarlo aquí."
            )
        }
        return searchText.isEmpty
            ? LaraL10n.text(en: "New wallpapers will appear here when published.", es: "Los fondos nuevos aparecerán aquí al publicarse.")
            : LaraL10n.text(en: "Try another name or creator.", es: "Prueba con otro nombre o creador.")
    }
}

private struct EagleWallpaperArtwork: View {
    let wallpaper: EagleWallpaper
    let contentMode: ContentMode
    var animated = false

    var body: some View {
        ZStack {
            // Thumbnails use the light still image; the animated preview (a few MB) only when the
            // wallpaper is open.
            LaraRemoteMediaPreview(
                url: animated ? wallpaper.previewURL : (wallpaper.stillPreviewURL ?? wallpaper.previewURL),
                animated: animated,
                contentMode: contentMode,
                showsRetry: false
            )
            if let foregroundURL = wallpaper.foregroundPreviewURL {
                AsyncImage(url: foregroundURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: contentMode)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// The previews are whole lock-screen captures (clock, island and all), so they are shown as a
/// complete iPhone at the screen's own proportions: never cropped, nothing laid over them.
private struct EaglePhoneFrame: View {
    let wallpaper: EagleWallpaper
    var animated = false

    var body: some View {
        EagleDeviceFrame {
            EagleWallpaperArtwork(wallpaper: wallpaper, contentMode: .fill, animated: animated)
        }
    }
}

private struct EagleWallpaperDetail: View {
    let wallpaper: EagleWallpaper

    @ObservedObject private var gallery = WallpaperCatalogManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @AppStorage(EagleWallpaperFavorites.storageKey)
    private var favoriteIDsJSON = "[]"
    /// Observed so Add appears as soon as PosterBoard's UUID is saved.
    @AppStorage(EaglePosterBoardUUID.storageKey) private var savedPosterBoardUUID = ""
    @State private var isPreparingDownload = false

    /// Prepared access, or PosterBoard's saved UUID: Prepare is only needed while neither exists.
    private var canInstall: Bool {
        mgr.sbxready || (!savedPosterBoardUUID.isEmpty && EaglePosterBoardUUID.allowsInstallWithoutPreparing)
    }
    @State private var shareImage: EagleWallpaperShareImage?

    private var isInstalling: Bool {
        gallery.installingID == wallpaper.id
    }

    private var isIncompatible: Bool {
        !wallpaper.isCompatibleWithCurrentIOS
    }

    private var isFavorite: Bool {
        EagleWallpaperFavorites.decode(favoriteIDsJSON).contains(wallpaper.id)
    }

    var body: some View {
        content
            // Opened: no longer news.
            .onAppear { EagleNewItems.shared.markSeen(.wallpaper, wallpaper.id) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if wallpaper.previewURL != nil {
                    EaglePhoneFrame(wallpaper: wallpaper, animated: true)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }

                // Name on the left, the two secondary actions as small round buttons on the right.
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wallpaper.displayName)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                        Text(wallpaper.contest.flatMap { $0.isEmpty ? nil : $0 } ?? wallpaper.authorLine)
                            .font(.footnote.weight(.medium))
                            .opacity(0.6)
                            .lineLimit(1)
                    }
                    .eagleBackdropText()

                    Spacer(minLength: 8)

                    EagleLikeButton(kind: .wallpaper, id: wallpaper.id, isLiked: isFavorite, onArtwork: false) {
                        toggleLike()
                    }

                    if let movie = wallpaper.motionPreviewURL {
                        NavigationLink {
                            EagleWallpaperVideoPreview(url: movie, title: wallpaper.displayName)
                        } label: {
                            EagleRoundAction(systemImage: "play.fill")
                        }
                        .buttonStyle(EaglePressableStyle(kind: .swatch))
                        .accessibilityLabel(LaraL10n.text(en: "Watch video preview", es: "Ver video de muestra"))
                    }

                    Button {
                        Task { await downloadImageForSharing() }
                    } label: {
                        EagleRoundAction(systemImage: "arrow.down.to.line", busy: isPreparingDownload)
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .disabled(isPreparingDownload)
                    .accessibilityLabel(LaraL10n.text(en: "Save or share image", es: "Guardar o compartir imagen"))
                }
                .padding(.horizontal, 4)

                if isIncompatible {
                    Label(
                        LaraL10n.text(
                            en: "Requires iOS \(wallpaper.minimumIOSMajor)",
                            es: "Requiere iOS \(wallpaper.minimumIOSMajor)"
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        // "Add to Wallpapers" stays fixed at the bottom; Prepare takes its place until Eagle is ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: canInstall) {
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
                .disabled(!canInstall || gallery.installingID != nil || isIncompatible)
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: gallery.resultMessage) { value in
            guard let value else { return }
            let installed = gallery.didInstall
            EagleNotifications.shared.show(title: LaraL10n.text(en: "Wallpapers", es: "Fondos"),
                message: value, kind: installed ? .success : .error,
                actionTitle: installed ? LaraL10n.text(en: "Open Wallpapers", es: "Abrir Fondos") : nil,
                action: installed ? { gallery.openWallpaperPicker() } : nil)
            gallery.clearResult()
        }
        .sheet(item: $shareImage) { item in
            EagleWallpaperShareSheet(url: item.url)
        }
    }

    private func toggleLike() {
        var favoriteIDs = EagleWallpaperFavorites.decode(favoriteIDsJSON)
        let liked = favoriteIDs.insert(wallpaper.id).inserted
        if !liked {
            favoriteIDs.remove(wallpaper.id)
        }
        favoriteIDsJSON = EagleWallpaperFavorites.encode(favoriteIDs)
        EagleLikes.shared.setLiked(.wallpaper, wallpaper.id, liked: liked)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor
    private func downloadImageForSharing() async {
        guard !isPreparingDownload else { return }
        isPreparingDownload = true
        defer { isPreparingDownload = false }
        do {
            // The still image when there is one: the preview itself may be an animated GIF.
            guard let url = wallpaper.stillPreviewURL ?? wallpaper.previewURL else {
                throw URLError(.badURL)
            }
            if wallpaper.isBundled {
                guard url.isFileURL else { throw URLError(.badURL) }
            } else {
                guard url.scheme == "https",
                      url.host == "raw.githubusercontent.com",
                      url.path.hasPrefix("/leonardob8777-bit/Eagle-Gallery/main/previews/wallpapers/") else {
                    throw URLError(.badURL)
                }
            }
            let backgroundData = try await downloadPNG(from: url)
            guard let background = UIImage(data: backgroundData) else {
                throw EagleWallpaperError.invalidResponse
            }
            var imageData = backgroundData
            if let foregroundURL = wallpaper.foregroundPreviewURL {
                guard let expectedSize = wallpaper.foregroundByteCount,
                      let expectedSHA = wallpaper.foregroundSha256 else {
                    throw EagleWallpaperError.invalidResponse
                }
                let foregroundData = try await downloadPNG(from: foregroundURL)
                guard foregroundData.count == expectedSize,
                      Data(SHA256.hash(data: foregroundData)).map({ String(format: "%02x", $0) }).joined() == expectedSHA.lowercased(),
                      let foreground = UIImage(data: foregroundData),
                      foreground.size == background.size else {
                    throw EagleWallpaperError.invalidResponse
                }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let combined = UIGraphicsImageRenderer(size: background.size, format: format).image { _ in
                    background.draw(in: CGRect(origin: .zero, size: background.size))
                    foreground.draw(in: CGRect(origin: .zero, size: background.size))
                }
                guard let combinedPNG = combined.pngData() else {
                    throw EagleWallpaperError.invalidResponse
                }
                imageData = combinedPNG
            }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Eagle Wallpapers", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(wallpaper.id + ".png")
            try imageData.write(to: destination, options: .atomic)
            shareImage = EagleWallpaperShareImage(url: destination)
        } catch {
            EagleNotifications.shared.show(
                title: LaraL10n.text(en: "Wallpapers", es: "Fondos"),
                message: error.localizedDescription,
                kind: .error
            )
        }
    }

    private func downloadPNG(from url: URL) async throws -> Data {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (downloaded, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw EagleWallpaperError.invalidResponse
            }
            data = downloaded
        }
        guard data.count <= 20 * 1024 * 1024,
              data.starts(with: [0x89, 0x50, 0x4E, 0x47]),
              UIImage(data: data) != nil else {
            throw EagleWallpaperError.invalidResponse
        }
        return data
    }
}

/// A secondary action as a small round button.
private struct EagleRoundAction: View {
    let systemImage: String
    var busy = false

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1) }
    }
}

private struct EagleWallpaperVideoPreview: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

private struct EagleWallpaperShareImage: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct EagleWallpaperShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
            throw EagleWallpaperError.packageTooLarge
        }

        let archive = try ZipArchive(data: data)
        let expandedSize = archive.entries.reduce(UInt64(0)) { partial, entry in
            partial.addingReportingOverflow(entry.uncompressedSize).overflow
                ? UInt64.max
                : partial + entry.uncompressedSize
        }
        guard expandedSize <= maximumExpandedSize else {
            throw EagleWallpaperError.packageTooLarge
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("EagleTendies-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try extract(archive, to: root)
        let descriptors = try findDescriptors(in: root)
        log("(wallpaper) found \(descriptors.count) installable descriptor(s)")
        guard !descriptors.isEmpty else { throw EagleWallpaperError.noDescriptors }
        guard descriptors.count <= maximumDescriptors else {
            throw EagleWallpaperError.tooManyDescriptors
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
            throw EagleWallpaperError.invalidPackage
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
                throw EagleWallpaperError.unsupportedExtension
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
            throw EagleWallpaperError.invalidPackage
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
