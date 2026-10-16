#!/usr/bin/env python3
"""Build the actual Island Gallery UI in an isolated simulator preview app.

Only access/apply operations and catalog transport are replaced. Images and
SwiftUI presentation come from the real sources. Never connects to SpringBoard.
"""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("simulator")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
gallery = repo.parent / "Eagle-Gallery"
work = Path(tempfile.mkdtemp(prefix="eagle-island-gallery-preview-"))
app = work / "IslandGalleryPreview.app"
app.mkdir()

style = (repo / "lara/views/new/IslandGalleryView.swift").read_text().split("private final class IslandGalleryRemoteCallBox:")[0]
model = (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift").read_text() + "\n" + (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryFilter.swift").read_text() + "\n" + (repo / "lara/views/new/IslandLiveMedia.swift").read_text().split("/// An isolated,")[0]
loader = (repo / "lara/EagleAdapters/EagleRemoteMediaLoader.swift").read_text()
model += "\n" + (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryFavorites.swift").read_text()
model += "\n" + (repo / "lara/EagleCore/IslandGallery/EagleIslandGallerySelection.swift").read_text()
model += "\n" + "\n".join((repo / f"lara/EagleCore/IslandGallery/EagleIslandGallery{name}.swift").read_text()
                            for name in ("Collection", "Recovery", "LoadFlow", "ActionFlow"))
load_guard = '        if !forceRefresh, loadedURL == url, case .loaded = state {'
assert loader.count(load_guard) == 1, "The preview fixture must replace exactly one loader entry"
loader = loader.replace(load_guard, '''
        let file = Bundle.main.bundleURL.appendingPathComponent("previews/" + url.lastPathComponent)
        if let data = try? Data(contentsOf: file) {
            loadedURL = url
            state = .loaded(data, Self.mimeType(for: url, response: nil), UUID())
            return
        }
        if !forceRefresh, loadedURL == url, case .loaded = state {''')
media = "\n".join((
    loader,
    (repo / "lara/EagleAdapters/EagleRemoteMediaPreview.swift").read_text(),
    (repo / "lara/views/new/LaraRemoteMediaPreview.swift").read_text(),
))
presentation = (repo / "lara/views/new/IslandGalleryPresentation.swift").read_text()
motion = (repo / "lara/views/new/EagleGalleryMotion.swift").read_text()
position = (repo / "lara/EagleCore/Gallery/EagleGalleryPosition.swift").read_text() + "\n" + (repo / "lara/EagleAdapters/Gallery/EagleGalleryPositionStorage.swift").read_text() + "\n" + (repo / "lara/views/new/GalleryPositionControl.swift").read_text()
shell = (repo / "lara/views/new/EagleAppShellView.swift").read_text().split("private struct TelegramSafariView:")[0]
# QA-only scroll position; the production view and native controls stay unchanged.
presentation = presentation.replace("collectionSection(proxy: proxy)", 'collectionSection(proxy: proxy).id("qa-collection")', 1)
presentation = presentation.replace(".scrollIndicators(.hidden)", '''.scrollIndicators(.hidden)
            .onAppear {
                if CommandLine.arguments.contains("--collection") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        proxy.scrollTo("qa-collection", anchor: .top)
                    }
                }
            }''', 1)
language = (repo / "lara/EagleCore/Localization/EagleLocalization.swift").read_text() + "\n" + (repo / "lara/config/LaraLanguage.swift").read_text()
stub = r'''
nonisolated enum IslandLiveMedia {
    static let previewURL = URL(string: "https://example.test/singularity-live.gif")!
    static let posterURL = URL(string: "https://example.test/singularity-live.png")!
    static func loadCatalog(force: Bool = false) async throws -> [IslandLiveTheme] {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("catalog.json"))
        return try JSONDecoder().decode(IslandLiveCatalog.self, from: data).themes
    }
}
@MainActor final class laramgr: ObservableObject {
    static let shared = laramgr()
    @Published var dsready = !CommandLine.arguments.contains("--needs-access")
}
struct IslandGalleryApplyResult { let succeeded: Bool; let message: String }
@MainActor final class IslandGalleryExecutor {
    static let shared = IslandGalleryExecutor()
    func apply(_ style: IslandGalleryStyle, shadowIntensity: Double) async -> IslandGalleryApplyResult {
        IslandGalleryApplyResult(succeeded: true, message: "Preview only: no native operation was performed.")
    }
    func applyLive(_ theme: IslandLiveTheme, shadowIntensity: Double) async -> IslandGalleryApplyResult {
        await apply(.singularityLive, shadowIntensity: shadowIntensity)
    }
    func restore() async -> IslandGalleryApplyResult { await apply(.starlight, shadowIntensity: 0.72) }
}
struct LaraAccessView: View {
    var compact: Bool
    var completion: (() -> Void)? = nil
    var body: some View { Text("Access setup placeholder — isolated preview app") }
}
struct EagleRainbowSpinner: View {
    var size: CGFloat
    var body: some View { ProgressView().frame(width: size, height: size) }
}
@MainActor final class EagleNotifications: ObservableObject {
    static let shared = EagleNotifications()
    @Published var visible = false
    func result(_ succeeded: Bool, title: String, message: String) {}
}
extension View {
    func eagleNotice<Item: Identifiable>(item: Binding<Item?>, title: String,
        message: @escaping (Item) -> String) -> some View { self }
}
@MainActor final class EagleSceneManager: ObservableObject {
    static let shared = EagleSceneManager()
    struct Notice: Identifiable { let id = UUID(); let message: String }
    @Published var notice: Notice?
    @Published var isApplying = false
    var progress: Double = 0
}
enum EagleVisualTheme { static let accent = Color.purple }
struct EagleBlockingProgress: View {
    let title: String
    let progress: Double
    var body: some View { ProgressView(title, value: progress) }
}
struct EagleBeta10AccessView: View {
    var body: some View { NavigationStack { Text("Access") } }
}
struct LaraHomeView: View {
    var body: some View {
        Group {
            if CommandLine.arguments.contains("--direct") {
                NavigationStack { IslandGalleryView(preview: true) }
            } else {
                NavigationStack {
                    NavigationLink("Open Island Gallery") { IslandGalleryView(preview: true) }
                        .navigationTitle("Customize")
                }
            }
        }
    }
}
func argument(_ name: String, default fallback: String) -> String {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          index + 1 < CommandLine.arguments.count else { return fallback }
    return CommandLine.arguments[index + 1]
}
extension IslandGalleryView {
    init(preview: Bool) {
        self.init()
        _filter = State(initialValue: IslandGalleryFilter(rawValue: argument("--filter", default: "all")) ?? .all)
        _search = State(initialValue: argument("--search", default: ""))
    }
}
@main struct IslandGalleryPreviewApp: App {
    init() {
        UserDefaults.standard.set(argument("--language", default: "es"), forKey: "lara.interfaceLanguage")
        UserDefaults.standard.set(argument("--theme", default: "island-9"), forKey: "eagle.islandGallery.selectedArtworkID")
        UserDefaults.standard.set("[]", forKey: "eagle.islandGallery.favoriteIDs")
        UserDefaults.standard.set(CommandLine.arguments.contains("--active") ? 1 : 0,
                                  forKey: "eagle.auraStudio.activeFlags")
        UserDefaults.standard.set(9, forKey: "eagle.auraStudio.activeIslandMode")
        UserDefaults.standard.set(Double(argument("--shadow", default: "0.72")) ?? 0.72,
                                  forKey: "eagle.islandGallery.shadowIntensity")
    }
    var body: some Scene {
        WindowGroup {
            EagleAppShellView()
            .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : .dark)
            .dynamicTypeSize(CommandLine.arguments.contains("--large-text") ? .accessibility2 : .large)
        }
    }
}
'''
swift = work / "Gallery.swift"
swift.write_text(style + model + language + motion + position + media + presentation + shell + stub)
(app / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "local.eagle.island-gallery-preview",
    "CFBundleExecutable": "IslandGalleryPreview", "CFBundleName": "Island Gallery Preview",
    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1",
    "MinimumOSVersion": "16.0", "UIDeviceFamily": [1], "UILaunchScreen": {},
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
}))
shutil.copy2(gallery / "catalogs/island-gallery-v1.json", app / "catalog.json")
shutil.copytree(gallery / "previews/island", app / "previews")
assets = work / "Assets.xcassets"
assets.mkdir()
for name in ["Rainbow", "Inferno", "Sky", "Vortex", "Bubblegum", "Traffic", "DuckMood", "BlueScreen", "WalkingFlame"]:
    shutil.copytree(repo / f"lara/other/media.xcassets/PhotoAura{name}.imageset", assets / f"PhotoAura{name}.imageset")
subprocess.run(["xcrun", "actool", str(assets), "--compile", str(app), "--platform", "iphonesimulator",
                "--minimum-deployment-target", "16.0", "--target-device", "iphone"], check=True)
sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-target",
                "arm64-apple-ios16.0-simulator", "-sdk", sdk, str(swift), "-o", str(app / "IslandGalleryPreview")], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
subprocess.run(["xcrun", "simctl", "install", args.simulator, str(app)], check=True)
print("PREVIEW_APP:", app)
