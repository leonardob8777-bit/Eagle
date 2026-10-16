#!/usr/bin/env python3
"""Check the owned media view against public Eagle and its environment bridge."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_core_module_build import declaration

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/LaraRemoteMediaPreview.swift"
OWNED_PATH = "lara/EagleAdapters/EagleRemoteMediaPreview.swift"
EXPECTED_BRIDGE = '''import SwiftUI

typealias LaraRemoteMediaPreview = EagleRemoteMediaPreview<EagleRainbowSpinner, EagleGalleryPresentationMotion>

extension EnvironmentValues {
    var laraMediaPreviewsEnabled: Bool {
        get { eagleMediaPreviewsEnabled }
        set { eagleMediaPreviewsEnabled = newValue }
    }
}

extension EagleRemoteMediaPreview where LoadingIndicator == EagleRainbowSpinner, ImageMotion == EagleGalleryPresentationMotion {
    init(
        url: URL?,
        animated: Bool = false,
        contentMode: ContentMode = .fill,
        showsRetry: Bool = true,
        compactPlaceholder: Bool = false,
        background: Color = Color(uiColor: .tertiarySystemFill),
        presentationMotion: Bool = false,
        onReady: ((Bool) -> Void)? = nil
    ) {
        self.init(
            url: url,
            animated: animated,
            contentMode: contentMode,
            showsRetry: showsRetry,
            compactPlaceholder: compactPlaceholder,
            background: background,
            presentationMotion: presentationMotion,
            onReady: onReady,
            loadingIndicator: { EagleRainbowSpinner(size: 22) },
            imageMotion: { EagleGalleryPresentationMotion(active: $0) },
            localizedText: { en, es in LaraL10n.text(en: en, es: es) }
        )
    }
}
'''


def replace_counted(source, old, new, count=1):
    assert source.count(old) == count, f"Preview projection changed: {old}"
    return source.replace(old, new)


def expected_preview(public):
    old_loader = declaration(public, "@MainActor\nprivate final class LaraRemoteMediaLoader:")
    source = replace_counted(public, old_loader + "\n\n", "")
    for old, new, count in (
        ("import ImageIO\n", "", 1),
        ("LaraRemoteMediaLoader", "EagleRemoteMediaLoader", 2),
        ("LaraMediaPreviewsEnabledKey", "EagleMediaPreviewsEnabledKey", 3),
        ("laraMediaPreviewsEnabled", "eagleMediaPreviewsEnabled", 2),
        ("struct LaraRemoteMediaPreview: View {",
         "struct EagleRemoteMediaPreview<LoadingIndicator: View, ImageMotion: ViewModifier>: View {", 1),
        ("LaraAnimatedDataView", "EagleAnimatedMediaView", 2),
        ("    var onReady: ((Bool) -> Void)? = nil\n",
         "    var onReady: ((Bool) -> Void)? = nil\n\n"
         "    let loadingIndicator: () -> LoadingIndicator\n"
         "    let imageMotion: (Bool) -> ImageMotion\n"
         "    let localizedText: (String, String) -> String\n", 1),
        ("                .eagleGalleryPresentationMotion(\n"
         "                    active: presentationMotion && shouldLoad\n"
         "                )",
         "                .modifier(imageMotion(presentationMotion && shouldLoad))", 1),
        ("EagleRainbowSpinner(size: 22)", "loadingIndicator()", 1),
        ('LaraL10n.text(en: "Loading preview…", es: "Cargando vista previa…")',
         'localizedText("Loading preview…", "Cargando vista previa…")', 1),
        ('LaraL10n.text(en: "Preview unavailable", es: "Vista previa no disponible")',
         'localizedText("Preview unavailable", "Vista previa no disponible")', 1),
        ('LaraL10n.text(en: "Try again", es: "Intentar de nuevo")',
         'localizedText("Try again", "Intentar de nuevo")', 1),
    ):
        source = replace_counted(source, old, new, count)
    return source


def verify_sources(repo, public=None):
    if public is None:
        public = subprocess.run(
            ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"],
            cwd=repo, check=True, capture_output=True, text=True, timeout=55,
        ).stdout
    owned = (repo / OWNED_PATH).read_text()
    bridge = (repo / VIEW_PATH).read_text()
    assert owned == expected_preview(public), "Owned preview rendering/lifecycle differs from public projection"
    assert bridge == EXPECTED_BRIDGE, "Preview defaults, environment forwarding or dependency binding changed"
    assert all(name not in owned for name in (
        "Lara", "lara", "laramgr", "RemoteCall", "DarkSword", "AnyView",
        "EagleRainbowSpinner", "EagleGalleryPresentationMotion",
    )), "Owned view depends on app-specific presentation or native services"
    return owned, bridge


def verify_environment(owned, bridge):
    # Exercise the real old/new keys together, without mounting a view or networking.
    fixture = "import SwiftUI\n\n" + "\n\n".join((
        declaration(owned, "private struct EagleMediaPreviewsEnabledKey:"),
        declaration(owned, "extension EnvironmentValues {"),
        declaration(bridge, "extension EnvironmentValues {"),
    )) + r'''
@main struct MediaEnvironmentChecks {
    @MainActor static func main() {
        var values = EnvironmentValues()
        precondition(values.eagleMediaPreviewsEnabled && values.laraMediaPreviewsEnabled)
        for value in [false, true, true, false] {
            values.laraMediaPreviewsEnabled = value
            precondition(values.eagleMediaPreviewsEnabled == value)
            values.eagleMediaPreviewsEnabled = !value
            precondition(values.laraMediaPreviewsEnabled == !value)
        }
        var copy = values
        copy.laraMediaPreviewsEnabled = !values.eagleMediaPreviewsEnabled
        precondition(copy.eagleMediaPreviewsEnabled != values.laraMediaPreviewsEnabled)
        print("PASS: default, bidirectional preview environment writes and copied values")
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="eagle-media-environment-") as directory:
        work = Path(directory)
        source = work / "EnvironmentChecks.swift"
        source.write_text(fixture)
        binary = work / "environment-checks"
        subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            "-swift-version", "5", "-default-isolation", "MainActor",
            "-strict-concurrency=complete", "-warnings-as-errors",
            str(source), "-o", str(binary),
        ], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)


def main():
    repo = Path(__file__).resolve().parents[1]
    owned, bridge = verify_sources(repo)
    print("PASS: complete public preview/animated-renderer projection and exact app dependency bridge", flush=True)
    verify_environment(owned, bridge)


if __name__ == "__main__":
    main()
