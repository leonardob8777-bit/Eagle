#!/usr/bin/env python3
"""Render exact release-note cards in a UI-only simulator app; no native engine."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'lara/views/new/EagleBeta10WelcomeView.swift').read_text()

def declaration(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

parts = [declaration(m) for m in [
    'private var updatesCard:', 'private var fixesCard:', 'private var compatibilityCard:',
    'private func welcomeCard<', 'private func welcomeSectionTitle(', 'private func welcomeRow('
]]
assert sum(p.count('welcomeRow(') for p in parts[:3]) == 6
assert 'iOS 26.0 – iOS 26.0.1' not in ''.join(parts)
code = '''import SwiftUI
enum LaraL10n {
    static func text(en: String, es: String) -> String {
        if ProcessInfo.processInfo.arguments.contains("--zh") { return EagleChineseText.translate(en) }
        return ProcessInfo.processInfo.arguments.contains("--es") ? es : en
    }
}
@main struct NotesQAApp: App {
    var body: some Scene { WindowGroup { NotesView().preferredColorScheme(.dark) } }
}
struct NotesView: View {
    private let colorScheme: ColorScheme = .dark
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    updatesCard
                    fixesCard.id("fixes")
                    compatibilityCard
                }.padding(20)
            }
            .background(Color.black)
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large") ? .accessibility2 : .large)
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--bottom") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("fixes", anchor: .top) }
                }
            }
        }
    }
''' + '\n'.join(parts) + '\n}\n'
code += (ROOT/'lara/EagleAdapters/Appearance/EagleVisualTheme.swift').read_text()
code += (ROOT/'lara/config/EagleChineseText.swift').read_text()
phrases = re.findall(r'en: "([^"\n]+)"', '\n'.join(parts))
assert len(phrases) == 14
table = (ROOT/'lara/config/EagleChineseText.swift').read_text()
assert all('"' + phrase + '":' in table for phrase in phrases), 'Missing Chinese release-note translation'
directory = Path(tempfile.mkdtemp(prefix='eagle-106-notes-'))
app = directory/'EagleNotesQA.app'
app.mkdir()
(directory/'Notes.swift').write_text(code)
(app/'Info.plist').write_bytes(plistlib.dumps(dict(
    CFBundleIdentifier='local.eagle.notes106',CFBundleExecutable='EagleNotesQA',
    CFBundleName='Eagle Notes QA',CFBundlePackageType='APPL',CFBundleVersion='95',
    CFBundleShortVersionString='1.0.6',MinimumOSVersion='16.0',UIDeviceFamily=[1],
    UILaunchScreen={},UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False})))
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-target',
    'arm64-apple-ios16.0-simulator','-sdk',sdk,str(directory/'Notes.swift'),'-o',str(app/'EagleNotesQA')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['xcrun','simctl','install','9324C0D4-39F1-4AE7-BAFF-7A03294BF784',str(app)],check=True)
print(directory)
