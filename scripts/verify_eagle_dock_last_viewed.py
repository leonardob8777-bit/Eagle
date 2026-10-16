#!/usr/bin/env python3
"""Check last-viewed decision parity with inert preference/read spies.

Only benign Core values and generated fixtures compile. The reference uses the
public remember helper with the pre-step owned selected/visible getters. Real
AppStorage, SwiftUI observers, the full app and the native backend are not run.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import declaration
from verify_eagle_dock_selection import (
    verify_sources, _verify_contract, replace_counted,
    REMEMBER_MARKER, SELECTED_MARKER, LAST_VIEWED_MARKER,
)
from verify_eagle_dock_session import CORE_PATHS, screen_bindings


VISIBLE_MARKER = "private var visibleRemoteThemes: [RemoteDockGalleryTheme]"
PREFERENCE_FIELDS = ("lastViewedStaticID", "lastViewedLiveID")
SOURCES = (*CORE_PATHS, "lara/EagleCore/DockGallery/EagleDockGalleryCollection.swift")


def preference_lines(source):
    result = []
    for field in PREFERENCE_FIELDS:
        matches = [line.strip() for line in source.splitlines()
                   if "@AppStorage(" in line and f"private var {field} =" in line]
        assert len(matches) == 1, f"Missing/duplicated preference declaration: {field}"
        result.append(matches[0])
    return result


def verify_contract(values):
    _verify_contract(**values)
    assert preference_lines(values["current"]) == preference_lines(values["public_view"]), (
        "Last-viewed preference keys/defaults changed"
    )
    assert values["current"].count("rememberViewedTheme()") == values["public_view"].count("rememberViewedTheme()") == 3, (
        "Last-viewed persistence gained/lost a call site"
    )


def verify_negatives(values):
    cases = [
        ("model", LAST_VIEWED_MARKER, "theme.frameCount > 1", "theme.frameCount == 17"),
        ("model", LAST_VIEWED_MARKER, "theme.frameCount > 1", "theme.frameCount >= 1"),
        ("model", LAST_VIEWED_MARKER, "theme.frameCount > 1", "theme.frameCount > 0"),
        ("model", LAST_VIEWED_MARKER, "return nil", 'return .still("")'),
        ("model", LAST_VIEWED_MARKER, "return .live(theme.id)", "return .still(theme.id)"),
        ("model", LAST_VIEWED_MARKER, "return .still(theme.id)", "return .live(theme.id)"),
        ("model", LAST_VIEWED_MARKER, "return .still(theme.id)", "return nil"),
        ("model", LAST_VIEWED_MARKER, "return .live(theme.id)", "return .live(theme.title)"),
        ("model", LAST_VIEWED_MARKER, "return .still(theme.id)", "return .still(theme.id.lowercased())"),
        ("model", LAST_VIEWED_MARKER, "if theme.frameCount > 1", "if theme.isSupportedPackage && theme.frameCount > 1"),
        ("current", REMEMBER_MARKER, "lastViewed(selectedRemoteTheme)", "lastViewed(nil)"),
        ("current", REMEMBER_MARKER, "lastViewedLiveID = id", "lastViewedStaticID = id"),
        ("current", REMEMBER_MARKER, "lastViewedStaticID = id", "lastViewedLiveID = id"),
        ("current", REMEMBER_MARKER, "lastViewedStaticID = id", "lastViewedStaticID = selectedRemoteID"),
        ("current", REMEMBER_MARKER, "lastViewedLiveID = id", 'lastViewedLiveID = id\n            lastViewedStaticID = ""'),
        ("current", REMEMBER_MARKER, "lastViewedStaticID = id", "if lastViewedStaticID != id { lastViewedStaticID = id }"),
        ("current", REMEMBER_MARKER, "lastViewedStaticID = id", 'lastViewedStaticID = selectedRemoteTheme?.id ?? ""'),
        ("current", REMEMBER_MARKER, "else { return }", 'else { lastViewedStaticID = ""; return }'),
        ("current", None, '"eagle.dockGallery.lastViewedStaticID"', '"eagle.dockGallery.lastViewedStillID"'),
        ("current", None, '"eagle.dockGallery.lastViewedLiveID"', '"eagle.dockGallery.lastViewedMotionID"'),
        ("current", None, 'private var lastViewedStaticID = ""', 'private var lastViewedStaticID = "default"'),
        ("current", None, 'private var lastViewedLiveID = ""', 'private var lastViewedLiveID = "default"'),
    ]
    for field, marker, old, new in cases:
        altered = values.copy()
        region = declaration(altered[field], marker) if marker else altered[field]
        changed = replace_counted(region, old, new, "negative last-viewed region")
        altered[field] = replace_counted(altered[field], region, changed, "negative last-viewed declaration") if marker else changed
        try:
            verify_contract(altered)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Last-viewed mutation escaped rejection: {field}/{old}")
    return len(cases)


def screen_fixture(values, name, owned):
    # Both sides retain the prior owned one-snapshot getter. Only the remember
    # helper differs, so this does not erase/claim public getter-count parity.
    selected = declaration(values["current"], SELECTED_MARKER)
    selected = replace_counted(selected, SELECTED_MARKER,
                               "func computeSelected() -> RemoteDockGalleryTheme?", "selected getter read spy")
    visible = declaration(values["current"], VISIBLE_MARKER)
    visible = replace_counted(visible, VISIBLE_MARKER,
                              "func computeVisible() -> [RemoteDockGalleryTheme]", "visible getter read spy")
    remember = declaration(values["current" if owned else "public_view"], REMEMBER_MARKER)
    remember = replace_counted(remember, REMEMBER_MARKER, "func rememberViewedTheme()", "fixture access")
    return "final class " + name + " {\n" + r'''
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    struct Store { var themes: [EagleDockGalleryTheme] = [] }
    var remoteGallery = Store()
    var selectedRemoteID = ""
    var shuffledRemoteIDs: [String] = []
    var mediaFilter: EagleDockGalleryMediaFilter = .still
    var favoriteIDs: Set<String> = []
    var events: [LastViewedEvent] = []
    var lastViewedStaticID = "" {
        didSet { events.append(.write("static", Array(lastViewedStaticID.utf8))) }
    }
    var lastViewedLiveID = "" {
        didSet { events.append(.write("live", Array(lastViewedLiveID.utf8))) }
    }
    var selectedRemoteTheme: EagleDockGalleryTheme? {
        events.append(.selected)
        return computeSelected()
    }
    var visibleRemoteThemes: [EagleDockGalleryTheme] {
        events.append(.visible)
        return computeVisible()
    }
''' + selected + "\n" + visible + "\n" + remember + "\n}\n"


def swiftui_fixture(values):
    source = values["current"]
    bindings = screen_bindings(source, ("selectedRemoteID", *PREFERENCE_FIELDS))
    return "import Foundation\nimport SwiftUI\n\nprivate struct LastViewedBindingFixture: View {\n" + """
    private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    private var visibleRemoteThemes: [EagleDockGalleryTheme] { [] }
""" + "\n".join(bindings) + "\n" + "\n".join(
        declaration(source, marker) for marker in (SELECTED_MARKER, REMEMBER_MARKER)
    ) + "\n" + """
    var body: some View {
        Text(lastViewedStaticID)
        Text(lastViewedLiveID)
        Button("Remember") { rememberViewedTheme() }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    verify_contract(values)
    negatives = verify_negatives(values)
    print(f"PASS: public-derived last-viewed rule/caller and exact preference keys/defaults; {negatives} negative mutations rejected", flush=True)
    if args.source_only:
        return
    sources = [str(repo / path) for path in SOURCES]
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-last-viewed-") as directory:
        work = Path(directory)
        fixture = work / "ExactLastViewedFixtures.swift"
        fixture.write_text("import Foundation\n" + screen_fixture(values, "PublicLastViewedFixture", False) +
                           "\n" + screen_fixture(values, "OwnedLastViewedFixture", True))
        binary = work / "verify-last-viewed"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(fixture),
                        str(repo / "scripts/verify_eagle_dock_last_viewed.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
        binding = work / "ExactLastViewedBindings.swift"
        binding.write_text(swiftui_fixture(values))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
                        "-target", "arm64-apple-ios16.0", "-sdk", sdk, *sources, str(binding)], check=True, timeout=55)
    print("PASS: exact last-viewed State/AppStorage/helper typechecks in an inert iOS fixture; temporary outputs cleaned; no full app/native backend/preferences execution/IPA", flush=True)


if __name__ == "__main__":
    main()
