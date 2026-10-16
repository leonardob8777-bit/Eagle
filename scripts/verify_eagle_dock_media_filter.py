#!/usr/bin/env python3
"""Check owned Gallery classification against public source and an inert UI seam.

Compiles only the actual Foundation theme/filter/memory and tiny host/SwiftUI fixtures.
The original view and earlier request wrappers are compared as text only;
no app target, applying engine, simulator or IPA is compiled or executed.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_favorites import project_view_favorites
from verify_eagle_dock_collection import project_view_collection
from verify_eagle_dock_selection import project_view_selection, project_last_viewed
from verify_eagle_dock_visit_order import project_view_visit_order
from verify_eagle_dock_selection_memory import MEMORY_PATH, project_view_selection_memory
from verify_eagle_dock_session import add_session_sources, project_session_category, project_session_step, project_session_reconciliation, project_view_session, screen_bindings
from verify_eagle_gallery_services import OLD_VIEW_BINDING, VIEW_BINDING


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
THEME_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift"
VIEW_MARKER = "struct DockGalleryView: View"
PUBLIC_MARKER = "private enum MediaFilter: String, CaseIterable"
OWNED_MARKER = "nonisolated enum EagleDockGalleryMediaFilter: String, CaseIterable, Sendable"
UI_ALIAS = "private typealias MediaFilter = EagleDockGalleryMediaFilter"


def replace_counted(source, old, new, label):
    assert source.count(old) == 1, f"Counted media-filter boundary changed: {label}"
    return source.replace(old, new, 1)


def expected_metadata(public_enum):
    expected = replace_counted(public_enum, PUBLIC_MARKER, OWNED_MARKER, "enum name/access/Sendable")
    return replace_counted(expected, "_ theme: RemoteDockGalleryTheme", "_ theme: EagleDockGalleryTheme", "owned theme type")


def expected_view(public_view, public_enum):
    expected = replace_counted(public_view, public_enum, UI_ALIAS, "nested enum replaced by private alias")
    # These two request wrappers predate this extraction. Normalize their exact
    # counted source only; do not compile, execute or change the original view.
    expected = replace_counted(
        expected,
        "let result = await DockGalleryExecutor.shared.applyRemote(theme, directory: directory, intensity: requestedIntensity)",
        """let result = await EagleDockGalleryCore(port: CurrentDockGalleryPort())
                    .applyRemote(EagleDockGalleryApplyRequest(
                        theme: theme,
                        directory: directory,
                        intensity: requestedIntensity
                    ))""",
        "existing apply request wrapper",
    )
    expected = replace_counted(
        expected,
        "let result = await DockGalleryExecutor.shared.restore()",
        "let result = await EagleDockGalleryCore(port: CurrentDockGalleryPort()).restore()",
        "existing restore wrapper",
    )
    # Subsequent pure favorites extraction: preserve the exact getter and guard
    # delegations, not a blanket exemption for selection/storage or UI changes.
    expected = project_view_favorites(expected)
    expected = project_view_collection(expected)
    expected = project_view_selection(expected)
    expected = project_view_visit_order(expected)
    expected = project_view_selection_memory(expected)
    expected = project_session_reconciliation(project_session_step(project_session_category(project_view_session(expected))))
    expected = project_last_viewed(expected)
    return replace_counted(expected, OLD_VIEW_BINDING, VIEW_BINDING, "owned shared Store composition")


def _verify_contract(public_enum, public_view, current, model):
    from verify_eagle_dock_apply_flow import inline_apply_flow
    from verify_eagle_dock_synchronization import inline_synchronization
    from verify_eagle_dock_interactions import inline_interactions
    from verify_eagle_dock_lifecycle import inline_lifecycle
    from verify_eagle_dock_stored_selection import inline_legacy_mapping
    from verify_eagle_dock_preview_readiness import inline_preview_readiness
    code = re.sub(r"//[^\n]*", "", model)
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_metadata(public_enum)), (
        "Owned filter differs from public case order, raw IDs, labels/icons or classification"
    )
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], (
        "Owned filter gained imports or external code"
    )
    assert current.count(UI_ALIAS) == 1, "The screen must use the exact private owned filter alias"
    assert "enum MediaFilter:" not in current, "The screen still owns its filter declaration"
    expanded = inline_preview_readiness(inline_legacy_mapping(inline_lifecycle(inline_interactions(inline_synchronization(inline_apply_flow(current))))))
    actual_view = declaration(expanded, VIEW_MARKER)
    assert compact(actual_view) == compact(expected_view(public_view, public_enum)), (
        "Original Gallery differs beyond counted filter/request/session delegations and owned shared Store binding"
    )


def verify_sources(repo):
    """Import-safe exact source check, also used by the wider model gate."""
    repo = Path(repo)
    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    public_view = declaration(public, VIEW_MARKER)
    public_enum = declaration(public_view, PUBLIC_MARKER)
    current = (repo / VIEW_PATH).read_text()
    model = (repo / MODEL_PATH).read_text()
    _verify_contract(public_enum, public_view, current, model)
    return {"public_enum": public_enum, "public_view": public_view, "current": current, "model": model}


def verify_memory_negatives(values):
    cases = [
        ("model", 'case still = "Static"\n    case live = "Live"', 'case live = "Live"\n    case still = "Static"'),
        ("model", 'case favorites = "Favorites"', 'case favorites = "Saves"'),
        ("model", 'self == .favorites ? "Saves" : rawValue', 'self == .favorites ? "Favorites" : rawValue'),
        ("model", 'case .still: return "sparkles"', 'case .still: return "star"'),
        ("model", 'case .live: return "play.circle"', 'case .live: return "play"'),
        ("model", 'case .favorites: return "heart"', 'case .favorites: return "heart.fill"'),
        ("model", "theme.frameCount == 1", "theme.frameCount <= 1"),
        ("model", "theme.frameCount > 1", "theme.frameCount == 17"),
        ("model", "favorites.contains(theme.id)", "favorites.contains(theme.title)"),
        ("model", "favorites.contains(theme.id)", "favorites.contains(theme.id.lowercased())"),
        ("model", "theme.frameCount > 1", "theme.isSupportedPackage && theme.frameCount > 1"),
        ("model", "import Foundation", "import Foundation\nimport SwiftUI"),
        ("model", "import Foundation", "import Foundation\nlet extraState = 1"),
        ("current", UI_ALIAS, "private typealias MediaFilter = DifferentFilter"),
        ("current", "get { session.mediaFilter }", "get { MediaFilter.live }"),
        ("current", "private var rememberedSelections: EagleDockGallerySelectionMemory {", "private var rememberedSelections: [String: String] {"),
        ("current", "filter: mediaFilter,", "filter: .still,"),
        ("current", "private func selectMediaFilter(_ filter: MediaFilter)", "private func selectMediaFilter(_ filter: String)"),
    ]
    for field, old, new in cases:
        altered = values.copy()
        altered[field] = replace_counted(altered[field], old, new, f"negative {field}")
        try:
            _verify_contract(altered["public_enum"], altered["public_view"], altered["current"], altered["model"])
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Changed media-filter source escaped rejection: {old}")
    return len(cases)


def runtime_projection(values):
    reference = replace_counted(
        values["public_enum"], PUBLIC_MARKER,
        "enum BaselineDockGalleryMediaFilter: String, CaseIterable", "public fixture visibility/name",
    )
    reference = replace_counted(
        reference, "_ theme: RemoteDockGalleryTheme", "_ theme: EagleDockGalleryTheme", "public fixture owned data input",
    )
    return "import Foundation\n\n" + reference + "\n"


def swiftui_projection(values):
    view = declaration(values["current"], VIEW_MARKER)
    alias = next(line.strip() for line in view.splitlines() if UI_ALIAS in line)
    bindings = screen_bindings(view, ("mediaFilter", "rememberedSelections"))
    return "import Foundation\nimport SwiftUI\n\nprivate struct FilterBindingFixture: View {\n" + alias + "\n" + "\n".join(bindings) + "\n" + """
    var body: some View {
        Text(mediaFilter.title).onAppear {
            let restored = MediaFilter(rawValue: mediaFilter.rawValue)!
            rememberedSelections.remember(id: "fixture", for: restored)
            mediaFilter = restored
            _ = MediaFilter.allCases.map { ($0.rawValue, $0.title, $0.icon) }
        }
    }

    private func visibleFixture(_ themes: [EagleDockGalleryTheme], favorites: Set<String>) -> [EagleDockGalleryTheme] {
        themes.filter { mediaFilter.includes($0, favorites: favorites) }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    negative_count = verify_memory_negatives(values)
    print(f"PASS: exact public/owned filter and whole original Gallery view normalization; {negative_count} negative mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [repo / path for path in add_session_sources((THEME_PATH, MODEL_PATH, MEMORY_PATH))]
    runner = repo / "scripts/verify_eagle_dock_media_filter.swift"
    assert runner.is_file(), "Standalone media-filter runner required"
    with tempfile.TemporaryDirectory(prefix="eagle-dock-media-filter-") as directory:
        work = Path(directory)
        reference = work / "ExactPublicDockGalleryMediaFilter.swift"
        reference.write_text(runtime_projection(values))
        binary = work / "verify-dock-media-filter"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", *map(str, sources), str(reference), str(runner), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactMediaFilterSwiftUIBindings.swift"
        fixture.write_text(swiftui_projection(values))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, *map(str, sources), str(fixture)],
            check=True, timeout=55,
        )
    print("PASS: actual nested alias/State/owned memory/filter typechecks in an inert iOS SwiftUI fixture; temporary outputs cleaned; no full view/app/native engine/IPA", flush=True)


if __name__ == "__main__":
    main()
