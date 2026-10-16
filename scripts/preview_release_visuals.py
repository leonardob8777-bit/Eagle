#!/usr/bin/env python3
"""Render the production home cards/badges and Updates UI in a simulator-only app.

Device support is stubbed and destinations are placeholders. No native access.
"""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('simulator')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='eagle-release-preview-'))
app = work / 'EagleReleasePreview.app'
app.mkdir()
home = (repo / 'lara/views/new/LaraHomeView.swift').read_text()
components = home[home.index('private struct AuraStudioHeroCard:'):]
start = home.index('                        VStack(alignment: .leading, spacing: 20)')
end = home.index('                                    NavigationLink(destination: AnimatedWallpapersView())', start)
cards = home[start:end] + '\n}.buttonStyle(.plain).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))\n}\n}\n'
welcome = (repo / 'lara/views/new/EagleBeta10WelcomeView.swift').read_text().split('#Preview')[0]
language = (repo / 'lara/EagleCore/Localization/EagleLocalization.swift').read_text() + '\n' + (repo / 'lara/config/LaraLanguage.swift').read_text()
theme = (repo / 'lara/EagleAdapters/Appearance/EagleVisualTheme.swift').read_text() + '\n' + (repo / 'lara/views/new/EagleRainbowLoadingView.swift').read_text().split('struct EagleBrandMark:')[0]
badge = (repo / 'lara/views/new/EagleNewBadge.swift').read_text()
stub = r'''
enum EagleSupportStatus { case possible, testedNeedsMoreTesting, supported, unsupported }
struct EagleSupportAssessment {
    var status = EagleSupportStatus.supported
    func message(spanish: Bool) -> String {
        spanish ? "Vista previa de interfaz; no se ejecuta acceso al sistema." : "Interface preview; no system access is performed."
    }
}
func eagleSupportAssessment() -> EagleSupportAssessment { EagleSupportAssessment() }
func devicemachine() -> String { "iPhone17,1" }
enum EagleDeviceIdentity { static func displayName(for model: String) -> String { "iPhone 16 Pro" } }
struct EagleBrandMark: View {
    var size: CGFloat
    var body: some View { Image("EagleBrandMark").resizable().scaledToFit().frame(width: size, height: size) }
}
struct EagleWordmark: View {
    var logoSize: CGFloat = 54
    var nameSize: CGFloat = 32
    var spacing: CGFloat = 12
    var body: some View {
        HStack(spacing: spacing) {
            EagleBrandMark(size: logoSize)
            Text("Eagle")
                .font(.system(size: nameSize, weight: .semibold, design: .serif).lowercaseSmallCaps())
                .tracking(1.5)
        }
    }
}
extension EagleBeta10WelcomeView {
    var qaFixes: some View { fixesCard }
    var qaNews: some View { updatesCard }
}
struct HomeCardsPreview: View {
    @State var hasSeenIslandGallery = false
    @State var hasSeenDockGallery = false
    @State var hasSeenHideSurfaces = false
    var auraStudioDestination: some View { Text("Aura preview") }
    var islandGalleryDestination: some View { Text("Island preview") }
    var dockGalleryDestination: some View { Text("Dock preview") }
    var hideSurfacesDestination: some View { Text("Hide preview") }
    var body: some View {
        NavigationStack {
            ScrollView {
'''
stub += cards + r'''
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(LaraL10n.text(en: "Customize", es: "Personalizar"))
        }
    }
}
@main struct PreviewApp: App {
    init() {
        UserDefaults.standard.set(CommandLine.arguments.contains("--english") ? "en" : "es",
                                  forKey: LaraLanguage.storageKey)
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if CommandLine.arguments.contains("--updates") {
                    EagleBeta10WelcomeView(onContinue: {})
                } else if CommandLine.arguments.contains("--fixes") || CommandLine.arguments.contains("--news") {
                    NavigationStack {
                        ScrollView {
                            Group {
                                if CommandLine.arguments.contains("--fixes") {
                                    EagleBeta10WelcomeView(onContinue: {}).qaFixes
                                } else {
                                    EagleBeta10WelcomeView(onContinue: {}).qaNews
                                }
                            }.padding(20)
                        }
                        .background(Color(uiColor: .systemGroupedBackground))
                        .navigationTitle(LaraL10n.text(en: "Updates", es: "Actualizaciones"))
                        .navigationBarTitleDisplayMode(.inline)
                    }
                } else { HomeCardsPreview() }
            }
            .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : .dark)
            .dynamicTypeSize(CommandLine.arguments.contains("--large-text") ? .accessibility2 : .large)
        }
    }
}
'''
swift = work / 'Preview.swift'
swift.write_text(language + theme + badge + components + welcome + stub)
(app / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.eagle.release-preview', 'CFBundleExecutable': 'EagleReleasePreview',
    'CFBundleName': 'Eagle Release Preview', 'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '85', 'CFBundleShortVersionString': '1.0.5',
    'MinimumOSVersion': '16.0', 'UIDeviceFamily': [1], 'UILaunchScreen': {},
    'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
}))
assets = work / 'Assets.xcassets'
assets.mkdir()
shutil.copytree(repo / 'lara/other/media.xcassets/EagleBrandMark.imageset', assets / 'EagleBrandMark.imageset')
subprocess.run(['xcrun', 'actool', str(assets), '--compile', str(app), '--platform', 'iphonesimulator',
                '--minimum-deployment-target', '16.0', '--target-device', 'iphone'], check=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target',
                'arm64-apple-ios16.0-simulator', '-sdk', sdk, str(swift), '-o', str(app / 'EagleReleasePreview')], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['xcrun', 'simctl', 'install', args.simulator, str(app)], check=True)
print('PREVIEW_APP:', app)
