#!/usr/bin/env python3
"""UI-only preview of the real button styles, switches and Prepare progress; no engine."""
from pathlib import Path
import argparse
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('simulator')
    args = parser.parse_args()
    source = (ROOT / 'lara/views/new/LaraAccessView.swift').read_text()
    start = source.index('private struct EaglePrepareButtonLabel:')
    end = source.index('/// Touch-down reaction:', start)
    code = source[start:end]
    for path in ['lara/EagleAdapters/Appearance/EagleVisualTheme.swift', 'lara/views/new/EaglePressableStyle.swift']:
        code += '\n' + (ROOT / path).read_text()
    code += r'''
@main struct ReadabilityQA: App {
    var body: some Scene {
        WindowGroup {
            ReadabilityView()
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ? .light : .dark)
                .toggleStyle(EagleSwitchToggleStyle())
        }
    }
}
struct ReadabilityView: View {
    @State private var enabled = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Eagle · controles y progreso").font(.headline)
                Button("Vista previa real") {}.buttonStyle(EagleSecondaryButtonStyle())
                HStack {
                    Button("Generar") {}.buttonStyle(.borderedProminent)
                        .tint(EagleVisualTheme.actionFill).eagleProminentLabel()
                    Button("Generar") {}.buttonStyle(.borderedProminent)
                        .tint(EagleVisualTheme.actionFill).eagleProminentLabel().disabled(true)
                }.controlSize(.large)
                VStack {
                    Toggle("Fondo / 壁纸", isOn: $enabled).padding(.trailing, 4)
                    Toggle("Código / 密码", isOn: .constant(false)).padding(.trailing, 4)
                }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                ForEach([0.10, 0.30, 0.59, 0.90], id: \.self) { progress in
                    EaglePrepareButtonLabel(title: "Preparando", progress: progress, busy: true,
                        finishing: false, rippleOrigin: nil, rippleKey: 0)
                }
                Text("Vista aislada: sin acciones ni motor").font(.footnote).foregroundStyle(.secondary)
            }.padding(22)
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
'''
    work = Path(tempfile.mkdtemp(prefix='eagle-readability-95-'))
    app = work / 'ReadabilityQA.app'
    app.mkdir()
    (work / 'QA.swift').write_text(code)
    (app / 'Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='local.eagle.readability95', CFBundleExecutable='ReadabilityQA',
        CFBundleName='Eagle Readability QA', CFBundlePackageType='APPL', CFBundleVersion='95',
        CFBundleShortVersionString='1.0.6', MinimumOSVersion='16.0', UIDeviceFamily=[1],
        UILaunchScreen={}, UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes': False})))
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target',
                    'arm64-apple-ios16.0-simulator', '-sdk', sdk, str(work / 'QA.swift'),
                    '-o', str(app / 'ReadabilityQA')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', args.simulator, str(app)], check=True)
    print(work)

if __name__ == '__main__':
    main()
