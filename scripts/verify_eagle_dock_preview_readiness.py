#!/usr/bin/env python3
"""Verify preview-readiness ownership without rendering or fetching media."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryPreviewReadiness.swift"
MARKER = "onReady: { ready in"
SCREEN = """onReady: { ready in
                            EagleDockGalleryPreviewReadiness.update(
                                ready,
                                themeID: theme.id,
                                selectedThemeID: { selectedRemoteTheme?.id },
                                readyPreviewID: { readyRemotePreviewID },
                                setReadyPreviewID: { readyRemotePreviewID = $0 }
                            )
                        }"""
HEADER = """static func update(
        _ ready: Bool,
        themeID: String,
        selectedThemeID: () -> String?,
        readyPreviewID: () -> String,
        setReadyPreviewID: (String) -> Void
    )"""


def replace_counted(source, old, new, count=1):
    assert source.count(old) == count, f"Preview readiness boundary changed: {old}"
    return source.replace(old, new)


def public_callback(repo):
    public = subprocess.check_output(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55)
    return declaration(public, MARKER)


def expected_core(public):
    body = replace_counted(public, MARKER, HEADER + " {")
    for old, new, count in (
        ("selectedRemoteTheme?.id", "selectedThemeID()", 1),
        ("readyRemotePreviewID = theme.id", "setReadyPreviewID(themeID)", 1),
        ('readyRemotePreviewID = ""', 'setReadyPreviewID("")', 1),
        ("readyRemotePreviewID == theme.id", "readyPreviewID() == themeID", 1),
        ("theme.id", "themeID", 1),
    ):
        body = replace_counted(body, old, new, count)
    return "import Foundation\n@MainActor\nenum EagleDockGalleryPreviewReadiness {\n" + body + "\n}"


def verify_contract(public, current, core):
    assert compact(re.sub(r"//[^\n]*", "", core)) == compact(expected_core(public)), "Preview guard, ID comparison, read/write order or isolation changed"
    assert compact(declaration(current, MARKER)) == compact(SCREEN), "Preview callback forwarding changed"


def inline_preview_readiness(source):
    repo = Path(__file__).resolve().parents[1]
    public = public_callback(repo)
    verify_contract(public, source, (repo / CORE_PATH).read_text())
    return replace_counted(source, declaration(source, MARKER), public)


def verify_sources(repo):
    public = public_callback(repo)
    current = (repo / VIEW_PATH).read_text()
    core = (repo / CORE_PATH).read_text()
    verify_contract(public, current, core)
    media = (repo / "lara/EagleAdapters/EagleRemoteMediaPreview.swift").read_text()
    assert media.count("var onReady: ((Bool) -> Void)? = nil") == 1, "Media callback type changed"
    return public, current, core


def verify_negatives(public, current, core):
    cases = [
        ("core", "@MainActor", "nonisolated"),
        ("core", "import Foundation", "import SwiftUI"),
        ("core", "guard selectedThemeID() == themeID else { return }", "_ = selectedThemeID()"),
        ("core", "selectedThemeID() == themeID", "selectedThemeID() != themeID"),
        ("core", "if ready {", "if !ready {"),
        ("core", "setReadyPreviewID(themeID)", 'setReadyPreviewID("")'),
        ("core", "else if readyPreviewID() == themeID", "else if true"),
        ("core", "readyPreviewID() == themeID", "readyPreviewID() != themeID"),
        ("core", 'setReadyPreviewID("")', "setReadyPreviewID(themeID)"),
        ("core", "if ready {", "_ = readyPreviewID(); if ready {"),
        ("core", "setReadyPreviewID(themeID)", "if readyPreviewID() != themeID { setReadyPreviewID(themeID) }"),
        ("current", "themeID: theme.id", "themeID: selectedRemoteID"),
        ("current", "selectedThemeID: { selectedRemoteTheme?.id }", "selectedThemeID: { selectedRemoteID }"),
        ("current", "readyPreviewID: { readyRemotePreviewID }", 'readyPreviewID: { "" }'),
        ("current", "setReadyPreviewID: { readyRemotePreviewID = $0 }", "setReadyPreviewID: { _ in }"),
        ("current", "                                ready,", "                                !ready,"),
    ]
    for field, old, new in cases:
        # Restrict current mutations to this callback, not unrelated session fields.
        region = core if field == "core" else declaration(current, MARKER)
        altered = replace_counted(region, old, new)
        try:
            verify_contract(public, altered if field == "current" else current, altered if field == "core" else core)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Preview readiness mutation escaped rejection: {old}")
    return len(cases)


def host_fixtures(public, current):
    result = "import Foundation\n"
    for name, callback in (
        ("PublicPreviewReadinessFixture", public),
        ("OwnedPreviewReadinessFixture", declaration(current, MARKER)),
    ):
        callback = replace_counted(callback, "onReady: ", "")
        # The production owner is a value View. The instrumented host is a
        # reference type and requires an explicit capture for an escaping closure.
        callback = replace_counted(callback, "{ ready in", "{ [self] ready in")
        result += f"final class {name}: PreviewReadinessStorage {{\n override func callback(for theme: RemoteDockGalleryTheme) -> (Bool) -> Void {{\n return {callback}\n}}\n}}\n"
    return result


def swiftui_fixture(current):
    from verify_eagle_dock_session import screen_bindings
    bindings = "\n".join(screen_bindings(current, ("selectedRemoteID", "readyRemotePreviewID")))
    selected = declaration(current, "private var selectedRemoteTheme: RemoteDockGalleryTheme?")
    return "import Foundation\nimport SwiftUI\n" + """
private struct ReadinessProbe: View {
    var onReady: ((Bool) -> Void)? = nil
    var body: some View { Color.clear }
}
private struct ReadinessBindingFixture: View {
    private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    let theme: EagleDockGalleryTheme
    private let visibleRemoteThemes: [EagleDockGalleryTheme] = []
""" + bindings + "\n" + selected + "\nvar body: some View { ReadinessProbe(\n" + declaration(current, MARKER) + "\n) }\n}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    public, current, core = verify_sources(repo)
    count = verify_negatives(public, current, core)
    print(f"PASS: exact public preview readiness body, screen closure and media callback type; {count} mutations rejected", flush=True)
    if args.source_only:
        return
    from verify_eagle_dock_session import CORE_PATHS
    sources = [str(repo / path) for path in (*CORE_PATHS, CORE_PATH)]
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-preview-readiness-") as directory:
        work = Path(directory)
        fixture = work / "ExactPreviewReadinessHosts.swift"
        fixture.write_text(host_fixtures(public, current))
        binary = work / "verify-preview-readiness"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(fixture),
                        str(repo / "scripts/verify_eagle_dock_preview_readiness.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactReadinessSwiftUI.swift"
        fixture.write_text(swiftui_fixture(current))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck", "-target", "arm64-apple-ios16.0",
                        "-sdk", sdk, *sources, str(fixture)], check=True, timeout=55)
    print("PASS: actual callback/selected-theme/session-State wiring typechecks on iOS; no rendering, network, app or native engine execution", flush=True)


if __name__ == "__main__":
    main()
