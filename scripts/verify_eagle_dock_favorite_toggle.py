#!/usr/bin/env python3
"""Check owned favorite membership and the original screen's effect sequence.

Only Foundation Core dependencies and inert storage/feedback fixtures compile.
The public reference getter/toggle comes from the fixed public commit. No real
preferences, UI observers, app target, native backend or IPA is executed.
"""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import declaration
from verify_eagle_dock_session import add_session_sources
from verify_eagle_dock_favorites import (
    verify_sources, verify_memory_negatives, replace_counted,
    GETTER_MARKER, TOGGLE_MARKER, MODEL_PATH, THEME_PATH,
)


def screen_fixture(source, name):
    getter = declaration(source, GETTER_MARKER)
    getter = replace_counted(getter, GETTER_MARKER, "func computeFavoriteIDs() -> Set<String>", "getter instrumentation")
    toggle = declaration(source, TOGGLE_MARKER)
    toggle = replace_counted(toggle, TOGGLE_MARKER, TOGGLE_MARKER.removeprefix("private "), "fixture visibility")
    toggle = replace_counted(toggle, "UISelectionFeedbackGenerator().selectionChanged()",
                              "events.append(.feedback)", "inert feedback spy")
    return "final class " + name + " {\n" + r'''
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    var events: [FavoriteToggleEvent] = []
    var favoriteIDsJSON = "[]" {
        didSet { events.append(.write(Array(favoriteIDsJSON.utf8))) }
    }
    var favoriteIDs: Set<String> {
        events.append(.read(Array(favoriteIDsJSON.utf8)))
        return computeFavoriteIDs()
    }
    func synchronizeRemoteSelection() {
        events.append(.synchronize(Array(favoriteIDsJSON.utf8)))
    }
''' + getter + "\n" + toggle + "\n}\n"


def main():
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    negatives = verify_memory_negatives(values)
    print(f"PASS: exact public-derived membership and complete favorite helper/storage/observer contract; {negatives} source mutations rejected", flush=True)
    sources = [str(repo / path) for path in add_session_sources((MODEL_PATH, THEME_PATH))]
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-favorite-toggle-") as directory:
        work = Path(directory)
        fixture = work / "ExactFavoriteToggleFixtures.swift"
        fixture.write_text("import Foundation\n" + screen_fixture(values["public_view"], "PublicFavoriteToggleFixture") +
                           "\n" + screen_fixture(values["current"], "OwnedFavoriteToggleFixture"))
        binary = work / "verify-favorite-toggle"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(fixture),
                        str(repo / "scripts/verify_eagle_dock_favorite_toggle.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: temporary inert fixtures cleaned; no real storage/observers/feedback/app/backend/IPA; actual iOS bindings remain covered by the favorites suite", flush=True)


if __name__ == "__main__":
    main()
