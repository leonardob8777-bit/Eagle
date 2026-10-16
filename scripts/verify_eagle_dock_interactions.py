#!/usr/bin/env python3
"""Check owned Gallery actions, exact screen wiring and guarded effect traces."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration

CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryInteractions.swift"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
CATEGORY_MARKER = "private func selectMediaFilter(_ filter: MediaFilter)"
STEP_MARKER = "private func stepRemote(_ step: Int)"
FAVORITE_MARKER = "private func toggleFavorite(_ theme: RemoteDockGalleryTheme)"
BEGIN_MARKER = "private func beginGalleryVisit()"
FAVORITE_INLINE = """private func toggleFavorite(_ theme: RemoteDockGalleryTheme) {
        let ids = EagleDockGalleryFavorites.toggling(favoriteIDs, id: theme.id)
        guard let json = EagleDockGalleryFavorites.encode(ids) else { return }
        // Store catalog IDs, so favorites survive app restarts and asset updates.
        favoriteIDsJSON = json
        synchronizeRemoteSelection()
        UISelectionFeedbackGenerator().selectionChanged()
    }"""
BEGIN_INLINE = """private func beginGalleryVisit() {
        session.beginVisit()
        synchronizeRemoteSelection()
    }"""
FAVORITE_SCREEN = """private func toggleFavorite(_ theme: RemoteDockGalleryTheme) {
        EagleDockGalleryInteractions.toggleFavorite(
            theme,
            readFavorites: { favoriteIDs },
            writeFavoritesJSON: { favoriteIDsJSON = $0 },
            synchronize: { synchronizeRemoteSelection() },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }"""
BEGIN_SCREEN = """private func beginGalleryVisit() {
        EagleDockGalleryInteractions.beginVisit(
            readSession: { session },
            writeSession: { session = $0 },
            synchronize: { synchronizeRemoteSelection() }
        )
    }"""
FAVORITE_HEADER = """static func toggleFavorite(
        _ theme: EagleDockGalleryTheme,
        readFavorites: () -> Set<String>,
        writeFavoritesJSON: (String) -> Void,
        synchronize: () -> Void,
        feedback: () -> Void
    )"""
BEGIN_HEADER = """static func beginVisit(
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        synchronize: () -> Void
    )"""
CATEGORY_INLINE = """private func selectMediaFilter(_ filter: MediaFilter) {
        guard mediaFilter != filter, !isApplying, remoteGallery.downloadingID == nil else { return }
        let selectedThemeID = selectedRemoteTheme?.id
        session.selectCategory(filter, remembering: selectedThemeID)
        synchronizeRemoteSelection()
        UISelectionFeedbackGenerator().selectionChanged()
    }"""
STEP_INLINE = """private func stepRemote(_ step: Int) {
        guard !isApplying, remoteGallery.downloadingID == nil else { return }
        let themes = visibleRemoteThemes
        guard themes.count > 1 else { return }
        session.step(step, in: themes)
        rememberViewedTheme()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }"""
CATEGORY_SCREEN = """private func selectMediaFilter(_ filter: MediaFilter) {
        EagleDockGalleryInteractions.selectCategory(
            filter,
            readSession: { session },
            writeSession: { session = $0 },
            isApplying: { isApplying },
            downloadingID: { remoteGallery.downloadingID },
            selectedThemeID: { selectedRemoteTheme?.id },
            synchronize: { synchronizeRemoteSelection() },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }"""
STEP_SCREEN = """private func stepRemote(_ step: Int) {
        EagleDockGalleryInteractions.step(
            step,
            readSession: { session },
            writeSession: { session = $0 },
            isApplying: { isApplying },
            downloadingID: { remoteGallery.downloadingID },
            visibleThemes: { visibleRemoteThemes },
            rememberViewedTheme: { rememberViewedTheme() },
            feedback: { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        )
    }"""
CATEGORY_HEADER = """static func selectCategory(
        _ filter: EagleDockGalleryMediaFilter,
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        selectedThemeID: () -> String?,
        synchronize: () -> Void,
        feedback: () -> Void
    )"""
STEP_HEADER = """static func step(
        _ step: Int,
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        visibleThemes: () -> [EagleDockGalleryTheme],
        rememberViewedTheme: () -> Void,
        feedback: () -> Void
    )"""


def replace_counted(source, old, new, count=1):
    assert source.count(old) == count, f"Interaction boundary count changed: {old}"
    return source.replace(old, new)


def expected_core():
    category = replace_counted(CATEGORY_INLINE, CATEGORY_MARKER, CATEGORY_HEADER)
    for old, new in (
        ("guard mediaFilter != filter", "guard readSession().mediaFilter != filter"),
        ("!isApplying, remoteGallery.downloadingID == nil", "!isApplying(), downloadingID() == nil"),
        ("selectedRemoteTheme?.id", "selectedThemeID()"),
        ("session.selectCategory(filter, remembering: selectedThemeID)",
         "var updated = readSession()\n        updated.selectCategory(filter, remembering: selectedThemeID)\n        writeSession(updated)"),
        ("synchronizeRemoteSelection()", "synchronize()"),
        ("UISelectionFeedbackGenerator().selectionChanged()", "feedback()"),
    ):
        category = replace_counted(category, old, new)
    step = replace_counted(STEP_INLINE, STEP_MARKER, STEP_HEADER)
    for old, new in (
        ("!isApplying, remoteGallery.downloadingID == nil", "!isApplying(), downloadingID() == nil"),
        ("let themes = visibleRemoteThemes", "let themes = visibleThemes()"),
        ("session.step(step, in: themes)", "var updated = readSession()\n        updated.step(step, in: themes)\n        writeSession(updated)"),
        ("UIImpactFeedbackGenerator(style: .soft).impactOccurred()", "feedback()"),
    ):
        step = replace_counted(step, old, new)
    favorite = replace_counted(FAVORITE_INLINE, FAVORITE_MARKER, FAVORITE_HEADER)
    for old, new in (
        ("toggling(favoriteIDs,", "toggling(readFavorites(),"),
        ("favoriteIDsJSON = json", "writeFavoritesJSON(json)"),
        ("synchronizeRemoteSelection()", "synchronize()"),
        ("UISelectionFeedbackGenerator().selectionChanged()", "feedback()"),
    ):
        favorite = replace_counted(favorite, old, new)
    begin = replace_counted(BEGIN_INLINE, BEGIN_MARKER, BEGIN_HEADER)
    begin = replace_counted(begin, "session.beginVisit()", "var updated = readSession()\n        updated.beginVisit()\n        writeSession(updated)")
    begin = replace_counted(begin, "synchronizeRemoteSelection()", "synchronize()")
    return "import Foundation\n@MainActor\nenum EagleDockGalleryInteractions {\n" + "\n".join((category, step, favorite, begin)) + "\n}"


def verify_core(source):
    assert compact(re.sub(r"//[^\n]*", "", source)) == compact(re.sub(r"//[^\n]*", "", expected_core())), (
        "Interaction guards, read/copy/write/effect sequence or synchronous isolation changed"
    )


def inline_interactions(source):
    repo = Path(__file__).resolve().parents[1]
    verify_core((repo / CORE_PATH).read_text())
    for marker, screen, original in (
        (CATEGORY_MARKER, CATEGORY_SCREEN, CATEGORY_INLINE),
        (STEP_MARKER, STEP_SCREEN, STEP_INLINE),
        (FAVORITE_MARKER, FAVORITE_SCREEN, FAVORITE_INLINE),
        (BEGIN_MARKER, BEGIN_SCREEN, BEGIN_INLINE),
    ):
        actual = declaration(source, marker)
        assert compact(actual) == compact(screen), f"Interaction screen wiring changed: {marker}"
        source = replace_counted(source, actual, original)
    return source


def verify_sources(repo):
    from verify_eagle_dock_session import NEW_CATEGORY, NEW_STEP, NEW_BEGIN, verify_sources as verify_session
    from verify_eagle_dock_favorites import verify_sources as verify_favorites, project_view_favorites
    current = (repo / VIEW_PATH).read_text()
    inline_interactions(current)
    assert compact(CATEGORY_INLINE) == compact(NEW_CATEGORY)
    assert compact(STEP_INLINE) == compact(NEW_STEP)
    assert compact(BEGIN_INLINE) == compact(NEW_BEGIN)
    favorite_values = verify_favorites(repo)
    assert compact(FAVORITE_INLINE) == compact(declaration(project_view_favorites(favorite_values["public_view"]), FAVORITE_MARKER))
    verify_session(repo)
    return current


def verify_negatives(current, core):
    cases = [
        ("core", "@MainActor", "nonisolated"),
        ("core", "guard readSession().mediaFilter != filter, ", "guard "),
        ("core", "!isApplying(), downloadingID() == nil", "downloadingID() == nil, !isApplying()", 2),
        ("core", "!isApplying(), downloadingID() == nil", "!isApplying()", 2),
        ("core", "guard themes.count > 1", "guard !themes.isEmpty"),
        ("core", "let selectedThemeID = selectedThemeID()", "let selectedThemeID: String? = nil"),
        ("core", "var updated = readSession()", "var updated = EagleDockGallerySession()", 3),
        ("core", "writeSession(updated)\n        synchronize()", "synchronize()\n        writeSession(updated)", 2),
        ("core", "rememberViewedTheme()\n        feedback()", "feedback()\n        rememberViewedTheme()"),
        ("core", "updated.step(step, in: themes)", "updated.step(1, in: themes)"),
        ("current", "isApplying: { isApplying }", "isApplying: { false }", 2),
        ("current", "downloadingID: { remoteGallery.downloadingID }", "downloadingID: { nil }", 2),
        ("current", "writeSession: { session = $0 }", "writeSession: { _ in }", 3),
        ("current", "selectedThemeID: { selectedRemoteTheme?.id }", "selectedThemeID: { selectedRemoteID }"),
        ("current", "synchronize: { synchronizeRemoteSelection() }", "synchronize: {}", 3),
        ("core", "readFavorites(), id: theme.id", "readFavorites(), id: theme.title"),
        ("core", "writeFavoritesJSON(json)\n        synchronize()", "synchronize()\n        writeFavoritesJSON(json)"),
        ("core", "encode(ids) else { return }", 'encode(ids) else { writeFavoritesJSON("[]"); return }'),
        ("core", "updated.beginVisit()", "_ = updated.visitStarted"),
        ("current", "readFavorites: { favoriteIDs }", "readFavorites: { [] }"),
        ("current", "writeFavoritesJSON: { favoriteIDsJSON = $0 }", "writeFavoritesJSON: { _ in }"),
    ]
    for field, old, new, *counts in cases:
        region = core if field == "core" else "\n".join(declaration(current, marker) for marker in (CATEGORY_MARKER, STEP_MARKER, FAVORITE_MARKER, BEGIN_MARKER))
        changed = replace_counted(region, old, new, counts[0] if counts else 1)
        try:
            verify_core(changed) if field == "core" else inline_interactions(changed)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Interaction mutation was not rejected: {old}")
    return len(cases)


def host_fixture(current):
    result = "import Foundation\n"
    for name, bodies in (
        ("PreviousInteractionFixture", (CATEGORY_INLINE, STEP_INLINE, FAVORITE_INLINE, BEGIN_INLINE)),
        ("OwnedInteractionFixture", tuple(declaration(current, marker) for marker in (CATEGORY_MARKER, STEP_MARKER, FAVORITE_MARKER, BEGIN_MARKER))),
    ):
        category, step, favorite, begin = bodies
        favorite = replace_counted(favorite, "UISelectionFeedbackGenerator().selectionChanged()", 'feedback("favorite")')
        joined = "\n".join((category, step, favorite, begin))
        joined = replace_counted(joined, "UISelectionFeedbackGenerator().selectionChanged()", 'feedback("category")')
        joined = replace_counted(joined, "UIImpactFeedbackGenerator(style: .soft).impactOccurred()", 'feedback("step")')
        result += "final class " + name + ": InteractionStorage {\n" + joined + "\n" + """
    override func category(_ filter: MediaFilter) { selectMediaFilter(filter) }
    override func navigate(_ step: Int) { stepRemote(step) }
    override func favorite(_ theme: RemoteDockGalleryTheme) { toggleFavorite(theme) }
    override func begin() { beginGalleryVisit() }
}
"""
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    current = verify_sources(repo)
    negatives = verify_negatives(current, (repo / CORE_PATH).read_text())
    print(f"PASS: exact owned action bodies, public-derived predecessors and screen wiring; {negatives} mutations rejected", flush=True)
    if args.source_only:
        return
    from verify_eagle_dock_session import CORE_PATHS
    sources = [str(repo / path) for path in CORE_PATHS]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-interactions-") as directory:
        work = Path(directory)
        fixture = work / "ExactInteractionHosts.swift"
        fixture.write_text(host_fixture(current))
        binary = work / "verify-interactions"
        subprocess.run(["swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        *sources, str(fixture), str(repo / "scripts/verify_eagle_dock_interactions.swift"),
                        "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: real action coordinator and screen helpers with inert storage/effect spies; no real UI or device execution", flush=True)


if __name__ == "__main__":
    main()
