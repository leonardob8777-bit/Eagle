#!/usr/bin/env python3
"""Verify owned visit lifecycle against public hooks, event traces and iOS wiring."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryLifecycle.swift"
MARKERS = (".onAppear", ".onDisappear", ".onChange(of: scenePhase)")
APPEAR_INLINE = "if !visitStarted { beginGalleryVisit() }"
APPEAR_CALL = """EagleDockGalleryLifecycle.appear(
                visitStarted: { visitStarted },
                beginVisit: { beginGalleryVisit() }
            )"""
DISAPPEAR_SCREEN = """.onDisappear {
            EagleDockGalleryLifecycle.disappear(
                showAccessSetup: { showAccessSetup },
                setVisitStarted: { visitStarted = $0 }
            )
        }"""
SCENE_SCREEN = """.onChange(of: scenePhase) { phase in
            EagleDockGalleryLifecycle.sceneChanged(
                phase == .background ? .background : (phase == .active ? .active : .other),
                visitStarted: { visitStarted },
                needsNewVisitOnResume: { needsNewVisitOnResume },
                setNeedsNewVisitOnResume: { needsNewVisitOnResume = $0 },
                showAccessSetup: { showAccessSetup },
                isApplying: { isApplying },
                downloadingID: { remoteGallery.downloadingID },
                beginVisit: { beginGalleryVisit() }
            )
        }"""
APPEAR_HEADER = """static func appear(
        visitStarted: () -> Bool,
        beginVisit: () -> Void
    )"""
DISAPPEAR_HEADER = """static func disappear(
        showAccessSetup: () -> Bool,
        setVisitStarted: (Bool) -> Void
    )"""
SCENE_HEADER = """static func sceneChanged(
        _ phase: Phase,
        visitStarted: () -> Bool,
        needsNewVisitOnResume: () -> Bool,
        setNeedsNewVisitOnResume: (Bool) -> Void,
        showAccessSetup: () -> Bool,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        beginVisit: () -> Void
    )"""


def replace_counted(source, old, new, count=1):
    assert source.count(old) == count, f"Lifecycle counted boundary changed: {old}"
    return source.replace(old, new)


def public_hooks(repo):
    source = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    view = declaration(source, "struct DockGalleryView: View")
    return tuple(declaration(view, marker) for marker in MARKERS)


def expected_core(hooks):
    appear, disappear, scene = hooks
    assert appear.count(APPEAR_INLINE) == 1, "Public initial-visit decision changed"
    appear = APPEAR_HEADER + " {\n" + APPEAR_INLINE + "\n}"
    appear = replace_counted(appear, "!visitStarted {", "!visitStarted() {")
    appear = replace_counted(appear, "beginGalleryVisit()", "beginVisit()")
    disappear = replace_counted(disappear, ".onDisappear", DISAPPEAR_HEADER)
    disappear = replace_counted(disappear, "!showAccessSetup {", "!showAccessSetup() {")
    disappear = replace_counted(disappear, "visitStarted = false", "setVisitStarted(false)")
    scene = replace_counted(scene, ".onChange(of: scenePhase) { phase in", SCENE_HEADER + " {")
    for old, new, count in (
        ("visitStarted", "visitStarted()", 2),
        ("needsNewVisitOnResume = true", "setNeedsNewVisitOnResume(true)", 1),
        ("needsNewVisitOnResume = false", "setNeedsNewVisitOnResume(false)", 1),
        ("needsNewVisitOnResume {", "needsNewVisitOnResume() {", 1),
        ("!showAccessSetup", "!showAccessSetup()", 1),
        ("!isApplying", "!isApplying()", 1),
        ("remoteGallery.downloadingID", "downloadingID()", 1),
        ("beginGalleryVisit()", "beginVisit()", 1),
    ):
        # Parameter declarations are not part of the executable body projection.
        body = scene[len(SCENE_HEADER):]
        scene = SCENE_HEADER + replace_counted(body, old, new, count)
    return """import Foundation
@MainActor
enum EagleDockGalleryLifecycle {
    nonisolated enum Phase: Sendable { case active, background, other }
""" + "\n".join((appear, disappear, scene)) + "\n}"


def code(source):
    return compact(re.sub(r"//[^\n]*", "", source))


def verify_contract(hooks, current, core):
    from verify_eagle_dock_stored_selection import inline_stored_preferences
    assert code(core) == code(expected_core(hooks)), "Owned lifecycle body/isolation/guards/effect order differs from public"
    current = inline_stored_preferences(current)
    expected = (replace_counted(hooks[0], APPEAR_INLINE, APPEAR_CALL), DISAPPEAR_SCREEN, SCENE_SCREEN)
    for marker, screen in zip(MARKERS, expected):
        assert compact(declaration(current, marker)) == compact(screen), f"Lifecycle screen binding changed: {marker}"


def inline_lifecycle(source):
    repo = Path(__file__).resolve().parents[1]
    hooks = public_hooks(repo)
    verify_contract(hooks, source, (repo / CORE_PATH).read_text())
    for marker, original in zip(MARKERS, hooks):
        source = replace_counted(source, declaration(source, marker), original)
    return source


def verify_sources(repo):
    hooks = public_hooks(repo)
    current = (repo / VIEW_PATH).read_text()
    core = (repo / CORE_PATH).read_text()
    verify_contract(hooks, current, core)
    return hooks, current, core


def verify_negatives(hooks, current, core):
    cases = [
        ("core", "@MainActor", "nonisolated"),
        ("core", "import Foundation", "import SwiftUI"),
        ("core", "if !visitStarted()", "if visitStarted()"),
        ("core", "if !showAccessSetup()", "if true"),
        ("core", "setVisitStarted(false)", "setVisitStarted(true)"),
        ("core", "phase == .background, visitStarted()", "phase == .background"),
        ("core", "setNeedsNewVisitOnResume(true)", "setNeedsNewVisitOnResume(false)"),
        ("core", "phase == .active, needsNewVisitOnResume()", "phase == .active"),
        ("core", "setNeedsNewVisitOnResume(false)\n", "\n"),
        ("core", "visitStarted(), !showAccessSetup(), !isApplying()", "visitStarted(), !isApplying(), !showAccessSetup()"),
        ("core", "downloadingID() == nil", "downloadingID()?.isEmpty != false"),
        ("core", "setNeedsNewVisitOnResume(false)\n            if", "if"),
        ("current", "phase == .background ? .background", "phase == .background ? .other"),
        ("current", "phase == .active ? .active : .other", "phase == .active ? .active : .background"),
        ("current", "needsNewVisitOnResume: { needsNewVisitOnResume }", "needsNewVisitOnResume: { true }"),
        ("current", "setNeedsNewVisitOnResume: { needsNewVisitOnResume = $0 }", "setNeedsNewVisitOnResume: { _ in }"),
        ("current", "setVisitStarted: { visitStarted = $0 }", "setVisitStarted: { _ in }"),
        ("current", "isApplying: { isApplying }", "isApplying: { false }"),
        ("current", "downloadingID: { remoteGallery.downloadingID }", "downloadingID: { nil }"),
        ("current", "setSelectedRaw: { selectedRaw = $0 }", "setSelectedRaw: { _ in }"),
    ]
    for field, old, new in cases:
        # Mutate only these actual hooks, never another callback with the same text.
        view_hooks = "\n".join(declaration(current, marker) for marker in MARKERS)
        changed = replace_counted(core if field == "core" else view_hooks, old, new)
        try:
            verify_contract(hooks, changed if field == "current" else current, changed if field == "core" else core)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Lifecycle mutation escaped detection: {old}")
    return len(cases)


def host_fixtures(hooks, current):
    result = "import Foundation\n"
    for name, appear, disappear, scene in (
        ("PreviousLifecycleFixture", APPEAR_INLINE, hooks[1], hooks[2]),
        ("OwnedLifecycleFixture", APPEAR_CALL, declaration(current, MARKERS[1]), declaration(current, MARKERS[2])),
    ):
        disappear = replace_counted(disappear, ".onDisappear", "override func disappear()")
        scene = replace_counted(scene, ".onChange(of: scenePhase) { phase in", "override func change(_ phase: LifecyclePhase) {")
        result += f"final class {name}: LifecycleStorage {{\n override func appear() {{\n{appear}\n}}\n{disappear}\n{scene}\n}}\n"
    return result


def swiftui_fixture(current):
    from verify_eagle_dock_session import screen_bindings
    from verify_eagle_dock_stored_selection import FIELDS, MAPPING_MARKER, storage_declaration
    hooks = "\n".join(declaration(current, marker) for marker in MARKERS)
    bindings = "\n".join(screen_bindings(current, ("visitStarted",)))
    fields = []
    for name in ("needsNewVisitOnResume", "showAccessSetup", "isApplying"):
        matches = [line.strip() for line in current.splitlines() if line.strip().startswith(f"@State private var {name} =")]
        assert len(matches) == 1
        fields.extend(matches)
    begin = declaration(current, "private func beginGalleryVisit()")
    preferences = "\n".join(storage_declaration(current, name) for name in FIELDS)
    verified = declaration(current, "private var hasVerifiedDock: Bool")
    mapping = declaration(current, MAPPING_MARKER)
    return "import Foundation\nimport SwiftUI\n" + r"""
private struct LifecycleBindingFixture: View {
    private typealias DockGalleryStyle = EagleDockGalleryBuiltInTheme
    @Environment(\.scenePhase) private var scenePhase
    private struct Download { var downloadingID: String? }
    private let remoteGallery = Download()
""" + preferences + "\n" + verified + "\n" + mapping + "\n" + bindings + "\n" + "\n".join(fields) + "\nvar body: some View { Text(\"Fixture\")\n" + hooks + "\n}\n" + begin + """
    private func synchronizeRemoteSelection() {}
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    hooks, current, core = verify_sources(repo)
    count = verify_negatives(hooks, current, core)
    print(f"PASS: exact public lifecycle sequence, all screen hooks and unchanged appearance migration; {count} negative mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-lifecycle-") as directory:
        work = Path(directory)
        fixture = work / "ExactLifecycleHosts.swift"
        fixture.write_text(host_fixtures(hooks, current))
        binary = work / "verify-lifecycle"
        subprocess.run(["swiftc", *flags, "-parse-as-library", str(repo / CORE_PATH), str(fixture),
                        str(repo / "scripts/verify_eagle_dock_lifecycle.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactLifecycleSwiftUI.swift"
        fixture.write_text(swiftui_fixture(current))
        from verify_eagle_dock_session import CORE_PATHS
        paths = (*CORE_PATHS, CORE_PATH, "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInTheme.swift",
                 "lara/EagleCore/DockGallery/EagleDockGalleryStoredSelection.swift", "lara/classes/EagleStoredThemeValues.swift")
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck", "-target", "arm64-apple-ios16.0",
                        "-sdk", sdk, *(str(repo / path) for path in paths), str(fixture)], check=True, timeout=55)
    print("PASS: actual lifecycle hooks and session/State bindings typecheck on iOS; inert fixtures only, no UI lifecycle/native engine/device execution", flush=True)


if __name__ == "__main__":
    main()
