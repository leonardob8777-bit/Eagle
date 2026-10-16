import Foundation
import SwiftUI
import UIKit
import Combine

enum PreviewPreparationState: String { case idle, preparing, ready }

enum PreviewTarget: String, CaseIterable, Identifiable {
    case dock, island
    var id: String { rawValue }
}

enum PreviewFilter: String, CaseIterable, Identifiable {
    case all, live, still, saved
    var id: String { rawValue }
}

/// Presentation-only localization shim used by the unchanged notification UI.
/// This app has a separate bundle and preferences from the installed Eagle.
@MainActor
enum LaraL10n {
    static let languageKey = "eagle.interfacePreview.language"
    static func text(en: String, es: String) -> String {
        UserDefaults.standard.string(forKey: languageKey) == "en" ? en : es
    }
}

private enum PreviewResourceTransport {
    static let catalogAddress = "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/dock-v1.json?catalog=21"

    /// Satisfies production transport interfaces from local bundle files only.
    /// No network request is made by the Preview app.
    static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, request.httpMethod == "GET", request.httpBody == nil else {
            throw URLError(.badURL)
        }
        let file: URL?
        if url.absoluteString == catalogAddress {
            file = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "PreviewResources")
        } else {
            guard url.scheme == "https", url.host == "preview.invalid",
                  url.query == nil, url.fragment == nil else { throw URLError(.unsupportedURL) }
            let allowed = ["bubblegum-preview.zip", "spectrum-preview.zip"]
            guard url.path == "/packages/" + url.lastPathComponent,
                  allowed.contains(url.lastPathComponent) else { throw URLError(.unsupportedURL) }
            file = Bundle.main.url(forResource: url.lastPathComponent,
                                   withExtension: nil, subdirectory: "PreviewResources/packages")
        }
        guard let file else { throw URLError(.fileDoesNotExist) }
        try await Task.sleep(nanoseconds: 180_000_000)
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}

@MainActor
final class EagleInterfacePreviewModel: ObservableObject {
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: LaraL10n.languageKey) }
    }
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "eagle.interfacePreview.appearance") }
    }
    @Published private(set) var demoState: PreviewPreparationState = .idle
    @Published private(set) var progress = 0.0
    @Published var selectedThemeID: String?
    @Published private(set) var frameURLs: [URL] = []
    @Published var selectedTarget: PreviewTarget = .dock
    @Published var filter: PreviewFilter = .all
    @Published private(set) var positionX: CGFloat = 0
    @Published private(set) var positionY: CGFloat = 0
    @Published private(set) var saved: Set<String> = []
    @Published private(set) var status = ""
    @Published private(set) var busy = false
    @Published private(set) var qaResult: String?

    let store: EagleDockGalleryStore
    private var storeSubscription: AnyCancellable?

    init() {
        let args = ProcessInfo.processInfo.arguments
        language = args.contains("--english") ? "en" :
            (UserDefaults.standard.string(forKey: LaraL10n.languageKey) ?? "es")
        appearance = args.contains("--light") ? "light" : (args.contains("--dark") ? "dark" :
            (UserDefaults.standard.string(forKey: "eagle.interfacePreview.appearance") ?? "system"))
        store = EagleDockGalleryStore(
            catalogLoader: EagleDockGalleryCatalogLoader(fetch: { try await PreviewResourceTransport.fetch($0) }),
            packagePreparation: EagleDockGalleryPackagePreparation(
                downloader: EagleDockGalleryPackageDownloader(fetch: { try await PreviewResourceTransport.fetch($0) })
            ),
            catalogFailureMessage: {
                LaraL10n.text(en: "The local test collection could not be loaded.",
                              es: "No se pudo cargar la colección local de prueba.")
            },
            diagnostics: { { _ in } }
        )
        UserDefaults.standard.set(language, forKey: LaraL10n.languageKey)
        // App-level forwarding only; production Core/Store is not edited.
        storeSubscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var visibleThemes: [EagleDockGalleryTheme] {
        store.themes.filter { theme in
            switch filter {
            case .all: return true
            case .live: return theme.frameCount > 1
            case .still: return theme.frameCount == 1
            case .saved: return saved.contains(theme.id)
            }
        }
    }

    var currentTheme: EagleDockGalleryTheme? {
        store.themes.first { $0.id == selectedThemeID }
    }

    var preferredColorScheme: ColorScheme? {
        appearance == "light" ? .light : (appearance == "dark" ? .dark : nil)
    }

    func t(en: String, es: String) -> String { language == "en" ? en : es }

    func initialLoad() async {
        await store.load()
        if selectedThemeID == nil { selectedThemeID = store.themes.first?.id }
    }

    func selectTheme(id: String) {
        guard !busy, id != selectedThemeID else { return }
        selectedThemeID = id
        frameURLs = []
        status = ""
    }

    func toggleSaved(id: String) {
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
    }

    func move(dx: CGFloat, dy: CGFloat) {
        positionX = min(16, max(-16, positionX + dx))
        positionY = min(16, max(-16, positionY + dy))
    }

    func resetPreview() {
        positionX = 0
        positionY = 0
        frameURLs = []
        status = ""
    }

    func previewURL(for theme: EagleDockGalleryTheme) -> URL? {
        guard ["bubblegum-preview", "spectrum-preview"].contains(theme.id) else { return nil }
        return Bundle.main.url(forResource: theme.id, withExtension: "png", subdirectory: "PreviewResources/previews")
    }

    func currentFrame(at date: Date) -> URL? {
        guard !frameURLs.isEmpty else { return currentTheme.flatMap { previewURL(for: $0) } }
        let frames = Double(frameURLs.count)
        let time = date.timeIntervalSinceReferenceDate * (currentTheme?.fps ?? 1)
        guard time.isFinite else { return frameURLs.first }
        let index = Int(max(0, time).truncatingRemainder(dividingBy: frames))
        return frameURLs[index]
    }

    func runPreparationDemo() async {
        guard demoState != .preparing else { return }
        demoState = .preparing
        progress = 0
        do {
            for step in 1...24 {
                try await Task.sleep(nanoseconds: 90_000_000)
                withAnimation(.linear(duration: 0.09)) { progress = Double(step) / 24 }
            }
            withAnimation(.easeInOut(duration: 0.45)) { demoState = .ready }
            EagleNotifications.shared.result(true, title: "Eagle Preview",
                message: t(en: "Visual demo complete. No system access was performed.",
                           es: "Demostración visual lista. No se accedió al sistema."))
        } catch {
            progress = 0
            demoState = .idle
        }
    }

    func prepareSelectedTheme() async {
        guard let theme = currentTheme, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let directory = try await store.prepare(theme)
            frameURLs = (1...theme.frameCount).map {
                directory.appendingPathComponent(String(format: "frame%02d.png", $0))
            }
            status = t(en: "\(frameURLs.count) frames validated · inside Preview only",
                       es: "\(frameURLs.count) fotogramas validados · solo dentro de Preview")
            EagleNotifications.shared.result(true,
                title: selectedTarget == .dock ? "Dock Preview" : "Island Preview",
                message: t(en: "The local package is ready. Nothing was applied to iOS.",
                           es: "El paquete local está listo. No se aplicó nada a iOS."))
        } catch {
            status = t(en: "Could not validate the local package.", es: "No se pudo validar el paquete local.")
            EagleNotifications.shared.result(false, title: "Gallery Preview", message: status)
        }
    }

    /// Runs only in the standalone app when explicitly launched with --qa.
    /// Reports local data/UI checks, never Prepare/native access compatibility.
    func runQA() async {
        var checks: [String] = []
        func require(_ value: Bool, _ name: String) throws {
            guard value else { throw NSError(domain: "EaglePreviewQA", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: name]) }
            checks.append(name)
        }
        do {
            for _ in 0..<100 {
                if UIApplication.shared.applicationState == .active { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            await initialLoad()
            try require(store.themes.count == 2 && store.errorMessage == nil, "offline catalog")
            try require(Set(store.themes.map(\.frameCount)) == [1, 17], "static/live metadata")
            filter = .still
            try require(visibleThemes.count == 1 && visibleThemes[0].frameCount == 1, "static filter")
            filter = .live
            try require(visibleThemes.count == 1 && visibleThemes[0].frameCount == 17, "live filter")
            let themeID = store.themes[0].id
            toggleSaved(id: themeID)
            filter = .saved
            try require(visibleThemes.map(\.id) == [themeID], "saved filter")
            filter = .all
            for theme in store.themes {
                selectTheme(id: theme.id)
                let first = try await store.prepare(theme)
                let second = try await store.prepare(theme)
                try require(first == second && store.downloadingID == nil, "cache fast path \(theme.id)")
                let files = try (1...theme.frameCount).map { index -> Data in
                    let file = first.appendingPathComponent(String(format: "frame%02d.png", index))
                    let data = try Data(contentsOf: file)
                    try require(EagleDockGalleryFrameImage.isValid(data, theme: theme), "frame \(theme.id) \(index)")
                    return data
                }
                try require(theme.frameCount == 1 || Set(files).count == 17, "distinct live frames \(theme.id)")
            }
            move(dx: 0.5, dy: -0.5)
            try require(positionX == 0.5 && positionY == -0.5, "preview-only position")
            resetPreview()
            try require(positionX == 0 && positionY == 0, "position reset")
            let originalLanguage = language
            language = "en"
            try require(LaraL10n.text(en: "English", es: "Español") == "English", "English binding")
            language = "es"
            try require(LaraL10n.text(en: "English", es: "Español") == "Español", "Spanish binding")
            language = originalLanguage
            await runPreparationDemo()
            try require(demoState == .ready && progress == 1, "visual preparation demo")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            for number in 0..<12 {
                EagleNotifications.shared.result(number.isMultiple(of: 2), title: "Preview \(number)", message: "UI test only")
            }
            try require(EagleNotifications.shared.current?.title == "Preview 11", "instant notice replacement")
            EagleNotifications.shared.dismiss()
            try await Task.sleep(nanoseconds: 800_000_000)
            qaResult = "PASS"
        } catch { qaResult = "FAIL: \(error.localizedDescription)" }
        let result: [String: Any] = [
            "scope": "interface-and-local-data-only",
            "result": qaResult ?? "FAIL",
            "checks": checks,
            "systemChanges": false,
            "nativeEngineIncluded": false,
        ]
        if let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: root.appendingPathComponent("PreviewQA.json"), options: .atomic)
        }
        print("Eagle Preview QA: \(qaResult ?? "FAIL"), \(checks.count) checks")
    }
}
