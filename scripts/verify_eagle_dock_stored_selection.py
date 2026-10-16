#!/usr/bin/env python3
"""Check saved-selection recovery and legacy IDs against fixed public source."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryStoredSelection.swift"
BUILTIN_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInTheme.swift"
MAPPING_MARKER = "private static func remoteID(forLegacyMode mode: Int) -> String?"
MAPPING_SCREEN = MAPPING_MARKER + """ {
        EagleDockGalleryStoredSelection.remoteID(forLegacyMode: mode)
    }"""
CALL = """EagleDockGalleryStoredSelection.reconcile(
                selectedRaw: { selectedRaw },
                setSelectedRaw: { selectedRaw = $0 },
                hasVerifiedDock: { hasVerifiedDock },
                activeRaw: { activeRaw },
                setActiveRaw: { activeRaw = $0 },
                activeDockModeRaw: { activeDockModeRaw },
                setActiveDockModeRaw: { activeDockModeRaw = $0 },
                activeRemoteID: { activeRemoteID },
                setActiveRemoteID: { activeRemoteID = $0 }
            )"""
HEADER = """static func reconcile(
        selectedRaw: () -> Int,
        setSelectedRaw: (Int) -> Void,
        hasVerifiedDock: () -> Bool,
        activeRaw: () -> Int,
        setActiveRaw: (Int) -> Void,
        activeDockModeRaw: () -> Int,
        setActiveDockModeRaw: (Int) -> Void,
        activeRemoteID: () -> String,
        setActiveRemoteID: (String) -> Void
    )"""
FIELDS = ("selectedRaw", "activeRaw", "activeFlagsRaw", "activeDockModeRaw", "activeRemoteID")


def replace_counted(source, old, new, count=1):
    assert source.count(old) == count, f"Stored-selection counted boundary changed: {old}"
    return source.replace(old, new)


def public_view(repo):
    source = subprocess.check_output(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55)
    return declaration(source, "struct DockGalleryView: View")


def migration(view):
    appear = declaration(view, ".onAppear")
    start = appear.index("if DockGalleryStyle(rawValue: selectedRaw)")
    return appear[start:appear.rfind("}")].rstrip()


def expected_core(public):
    body = migration(public)
    for old, new, count in (
        ("selectedRaw = DockGalleryStyle.bubblegum.rawValue", "setSelectedRaw(DockGalleryStyle.bubblegum.rawValue)", 1),
        ("activeDockModeRaw = activeRaw", "setActiveDockModeRaw(activeRaw())", 1),
        ("activeRaw = 0", "setActiveRaw(0)", 1),
        ("activeRemoteID = legacyID", "setActiveRemoteID(legacyID)", 1),
        ("rawValue: selectedRaw)", "rawValue: selectedRaw())", 1),
        ("rawValue: activeRaw)", "rawValue: activeRaw())", 1),
        ("hasVerifiedDock", "hasVerifiedDock()", 3),
        ("activeDockModeRaw == 1", "activeDockModeRaw() == 1", 1),
        ("rawValue: activeDockModeRaw)", "rawValue: activeDockModeRaw())", 1),
        ("activeRemoteID.isEmpty", "activeRemoteID().isEmpty", 1),
        ("Self.remoteID(forLegacyMode: activeDockModeRaw)", "remoteID(forLegacyMode: activeDockModeRaw())", 1),
        ("DockGalleryStyle", "EagleDockGalleryBuiltInTheme", 4),
    ):
        body = replace_counted(body, old, new, count)
    mapping = replace_counted(declaration(public, MAPPING_MARKER), "private static func", "nonisolated static func")
    return "import Foundation\n@MainActor\nenum EagleDockGalleryStoredSelection {\n" + HEADER + " {\n" + body + "\n}\n" + mapping + "\n}"


def code(source):
    return compact(re.sub(r"//[^\n]*", "", source))


def verify_core(public, source):
    assert code(source) == code(expected_core(public)), "Saved-selection core/isolation/lazy sequence or legacy mapping changed"


def inline_stored_preferences(source):
    repo = Path(__file__).resolve().parents[1]
    public = public_view(repo)
    verify_core(public, (repo / CORE_PATH).read_text())
    # Counted full call: wrong callback/read/write is rejected before expansion.
    return replace_counted(source, CALL, migration(public))


def inline_legacy_mapping(source):
    repo = Path(__file__).resolve().parents[1]
    public = public_view(repo)
    verify_core(public, (repo / CORE_PATH).read_text())
    actual = declaration(source, MAPPING_MARKER)
    assert compact(actual) == compact(MAPPING_SCREEN), "Legacy mapping screen delegation changed"
    return replace_counted(source, actual, declaration(public, MAPPING_MARKER))


def storage_declaration(source, name):
    matches = re.findall(r'@AppStorage\("[^"\n]+"\)\s+private var ' + re.escape(name) + r' = [^\n]+', source)
    assert len(matches) == 1, f"Expected one stored field: {name}"
    return matches[0]


def verify_contract(public, current, core):
    verify_core(public, core)
    assert current.count(CALL) == 1, "Complete saved-selection screen forwarding changed"
    assert compact(declaration(current, MAPPING_MARKER)) == compact(MAPPING_SCREEN), "Mapping wrapper changed"
    for name in FIELDS:
        assert compact(storage_declaration(current, name)) == compact(storage_declaration(public, name)), f"Preference key/default changed: {name}"
    verified = "private var hasVerifiedDock: Bool"
    assert compact(declaration(current, verified)) == compact(declaration(public, verified)), "Verified-Dock flag interpretation changed"


def verify_sources(repo):
    public = public_view(repo)
    current = (repo / VIEW_PATH).read_text()
    core = (repo / CORE_PATH).read_text()
    verify_contract(public, current, core)
    # Also establishes placement after beginVisit and checks all appearance text.
    from verify_eagle_dock_lifecycle import verify_sources as verify_lifecycle
    verify_lifecycle(repo)
    return public, current, core


def verify_negatives(public, current, core):
    cases = [
        ("core", "@MainActor", "nonisolated"),
        ("core", "import Foundation", "import SwiftUI"),
        ("core", "rawValue: selectedRaw()) == nil", "rawValue: selectedRaw()) != nil"),
        ("core", "setSelectedRaw(EagleDockGalleryBuiltInTheme.bubblegum.rawValue)", "setSelectedRaw(0)"),
        ("core", "rawValue: activeRaw()) != nil", "rawValue: activeRaw()) == nil"),
        ("core", "activeDockModeRaw() == 1", "activeDockModeRaw() == 35"),
        ("core", "setActiveDockModeRaw(activeRaw())", "setActiveDockModeRaw(selectedRaw())"),
        ("core", "!hasVerifiedDock() ||", "!hasVerifiedDock() &&"),
        ("core", "setActiveRaw(0)", "setActiveRaw(selectedRaw())"),
        ("core", "activeRemoteID().isEmpty", "activeRemoteID().trimmingCharacters(in: .whitespaces).isEmpty"),
        ("core", "remoteID(forLegacyMode: activeDockModeRaw())", "remoteID(forLegacyMode: activeRaw())"),
        ("core", '18: "neon-chase"', '18: "neon-drift"'),
        ("core", '31: "prism-blur"', '35: "prism-blur"'),
        ("current", "setSelectedRaw: { selectedRaw = $0 }", "setSelectedRaw: { _ in }"),
        ("current", "hasVerifiedDock: { hasVerifiedDock }", "hasVerifiedDock: { true }"),
        ("current", "activeRaw: { activeRaw }", "activeRaw: { selectedRaw }"),
        ("current", "setActiveDockModeRaw: { activeDockModeRaw = $0 }", "setActiveDockModeRaw: { activeRaw = $0 }"),
        ("current", "activeRemoteID: { activeRemoteID }", 'activeRemoteID: { "" }'),
        ("current", "EagleDockGalleryStoredSelection.remoteID(forLegacyMode: mode)", "EagleDockGalleryStoredSelection.remoteID(forLegacyMode: 15)"),
        ("current", '@AppStorage("eagle.dockGallery.selectedStyle")', '@AppStorage("eagle.dockGallery.selectedStyleV2")'),
        ("current", 'private var activeRemoteID = ""', 'private var activeRemoteID = "bubblegum"'),
    ]
    for field, old, new in cases:
        altered = replace_counted(core if field == "core" else current, old, new)
        try:
            verify_contract(public, altered if field == "current" else current, altered if field == "core" else core)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Stored-selection mutation escaped rejection: {old}")
    return len(cases)


def host_fixtures(public, current):
    result = "import Foundation\n"
    for name, body, mapping in (
        ("PublicStoredSelectionFixture", migration(public), declaration(public, MAPPING_MARKER)),
        ("OwnedStoredSelectionFixture", CALL, declaration(current, MAPPING_MARKER)),
    ):
        result += f"final class {name}: StoredSelectionStorage {{\n override func reconcile() {{\n{body}\n}}\n{mapping}\n"
        result += "override class func mapped(_ mode: Int) -> String? { remoteID(forLegacyMode: mode) }\n}\n"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    public, current, core = verify_sources(repo)
    count = verify_negatives(public, current, core)
    print(f"PASS: exact public saved-selection rules, mapping, screen forwarding and preference keys/defaults; {count} mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-stored-selection-") as directory:
        work = Path(directory)
        fixture = work / "ExactStoredSelectionHosts.swift"
        fixture.write_text(host_fixtures(public, current))
        binary = work / "verify-stored-selection"
        subprocess.run(["swiftc", *flags, "-parse-as-library", str(repo / CORE_PATH), str(repo / BUILTIN_PATH), str(fixture),
                        str(repo / "lara/classes/EagleStoredThemeValues.swift"),
                        str(repo / "scripts/verify_eagle_dock_stored_selection.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    # Lifecycle's actual complete .onAppear fixture also compiles this call.
    print("PASS: actual public/current saved-selection bodies with inert preference spies; no installed preferences or native engine executed", flush=True)


if __name__ == "__main__":
    main()
