#!/usr/bin/env python3
"""Check exact public ordered-theme projection with bounded Foundation fixtures.

Compiles the actual benign theme/filter/collection only, plus tiny host and
SwiftUI binding fixtures. No app, native backend, simulator, cache or IPA.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_session import add_session_sources, screen_bindings


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryCollection.swift"
CORE_PATHS = (
    "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift",
    MODEL_PATH,
)
VIEW_MARKER = "struct DockGalleryView: View"
GETTER_MARKER = "private var visibleRemoteThemes: [RemoteDockGalleryTheme]"
PUBLIC_FILTER_MARKER = "private enum MediaFilter: String, CaseIterable"
OWNED_MARKER = "nonisolated enum EagleDockGalleryCollection"
HEADER = """static func visible(
        themes: [EagleDockGalleryTheme],
        orderedIDs: [String],
        filter: EagleDockGalleryMediaFilter,
        favorites: Set<String>
    ) -> [EagleDockGalleryTheme]"""
GETTER = """private var visibleRemoteThemes: [RemoteDockGalleryTheme] {
        let favorites = favoriteIDs
        return EagleDockGalleryCollection.visible(
            themes: remoteGallery.themes,
            orderedIDs: shuffledRemoteIDs,
            filter: mediaFilter,
            favorites: favorites
        )
    }"""


def replace_counted(source, old, new, label):
    assert source.count(old) == 1, f"Counted collection boundary changed: {label}"
    return source.replace(old, new, 1)


def expected_metadata(public_view):
    getter = declaration(public_view, GETTER_MARKER)
    expected = replace_counted(getter, GETTER_MARKER, HEADER, "explicit value inputs/result")
    expected = replace_counted(expected, "        let favorites = favoriteIDs\n", "", "keep favorite snapshot in UI")
    for old, new in (("remoteGallery.themes", "themes"), ("shuffledRemoteIDs", "orderedIDs"), ("mediaFilter.includes", "filter.includes")):
        expected = replace_counted(expected, old, new, f"explicit input {old}")
    return OWNED_MARKER + " {\n" + expected + "\n}"


def project_view_collection(source):
    """One exact delegation, used by the whole-view source comparison too."""
    getter = declaration(source, GETTER_MARKER)
    return replace_counted(source, getter, GETTER, "visible themes delegation")


def _verify_contract(public_view, current, model):
    code = re.sub(r"//[^\n]*", "", model)
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_metadata(public_view)), (
        "Collection differs from public first-per-ID/dictionary/ordered compactMap/post-filter sequence"
    )
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], (
        "Collection gained imports, shared state or external code"
    )
    assert compact(declaration(current, GETTER_MARKER)) == compact(GETTER), (
        "Caller changed favorite snapshot position or themes/order/filter/favorites inputs"
    )


def verify_sources(repo):
    """Import-safe exact source-only check for this and the wider model gate."""
    repo = Path(repo)
    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    public_view = declaration(public, VIEW_MARKER)
    current = (repo / VIEW_PATH).read_text()
    model = (repo / MODEL_PATH).read_text()
    _verify_contract(public_view, current, model)
    return {"public_view": public_view, "current": current, "model": model}


def verify_memory_negatives(values):
    cases = [
        ("model", "{ first, _ in first }", "{ _, last in last }"),
        ("model", "themes.map { ($0.id, $0) }", "themes.map { ($0.title, $0) }"),
        ("model", "themes.map { ($0.id, $0) }", "themes.filter { filter.includes($0, favorites: favorites) }.map { ($0.id, $0) }"),
        ("model", "orderedIDs.compactMap", "Array(Set(orderedIDs)).compactMap"),
        ("model", "orderedIDs.compactMap", "orderedIDs.sorted().compactMap"),
        ("model", "orderedIDs.compactMap", "orderedIDs.reversed().compactMap"),
        ("model", "themesByID[$0]", "themesByID[$0.lowercased()]"),
        ("model", "filter.includes($0, favorites: favorites)", "filter.includes($0, favorites: [])"),
        ("model", "filter.includes($0, favorites: favorites)", "$0.isSupportedPackage && filter.includes($0, favorites: favorites)"),
        ("model", "return orderedIDs.compactMap { themesByID[$0] }", "return Array(themesByID.values)"),
        ("model", "import Foundation", "import Foundation\nimport SwiftUI"),
        ("model", "import Foundation", "import Foundation\nvar sharedOrder: [String] = []"),
        ("current", "themes: remoteGallery.themes,", "themes: [],"),
        ("current", "orderedIDs: shuffledRemoteIDs,", "orderedIDs: shuffledRemoteIDs.sorted(),"),
        ("current", "filter: mediaFilter,", "filter: .still,"),
        ("current", "favorites: favorites\n", "favorites: []\n"),
        ("current", "let favorites = favoriteIDs\n        return EagleDockGalleryCollection.visible", "let favorites: Set<String> = []\n        return EagleDockGalleryCollection.visible"),
        ("current", "favorites: favorites\n", "favorites: favoriteIDs\n"),
    ]
    for field, old, new in cases:
        altered = values.copy()
        if field == "current":
            # Other screen helpers legitimately reuse the same input labels.
            # Mutate only this complete getter, then check the full contract.
            getter = declaration(altered[field], GETTER_MARKER)
            changed = replace_counted(getter, old, new, "negative collection getter")
            altered[field] = replace_counted(altered[field], getter, changed, "negative current")
        else:
            altered[field] = replace_counted(altered[field], old, new, f"negative {field}")
        try:
            _verify_contract(altered["public_view"], altered["current"], altered["model"])
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Changed collection source escaped rejection: {old}")
    return len(cases)


def runtime_projection(values):
    reference = replace_counted(expected_metadata(values["public_view"]), OWNED_MARKER,
                                "enum BaselineDockGalleryCollection", "public fixture name/actor")
    reference = replace_counted(reference, "filter: EagleDockGalleryMediaFilter",
                                "filter: BaselineDockGalleryMediaFilter", "exact public filter fixture input")
    public_filter = declaration(values["public_view"], PUBLIC_FILTER_MARKER)
    public_filter = replace_counted(public_filter, PUBLIC_FILTER_MARKER,
                                   "enum BaselineDockGalleryMediaFilter: String, CaseIterable", "public filter fixture name/visibility")
    public_filter = replace_counted(public_filter, "_ theme: RemoteDockGalleryTheme",
                                   "_ theme: EagleDockGalleryTheme", "already-owned data parameter")
    return "import Foundation\n\n" + public_filter + "\n\n" + reference + "\n"


def swiftui_projection(values):
    view = declaration(values["current"], VIEW_MARKER)
    getter = declaration(view, GETTER_MARKER)
    bindings = screen_bindings(view, ("mediaFilter", "shuffledRemoteIDs"))
    return "import Foundation\nimport SwiftUI\n\nprivate struct CollectionBindingFixture: View {\n" + """
    private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    private typealias MediaFilter = EagleDockGalleryMediaFilter
    private struct Store { var themes: [EagleDockGalleryTheme] = [] }
    private var remoteGallery = Store()
    private var favoriteIDs: Set<String> { [] }
""" + "\n".join(bindings) + "\n" + getter + "\n" + """
    var body: some View { Text(String(visibleRemoteThemes.count)) }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    negative_count = verify_memory_negatives(values)
    print(f"PASS: exact public/owned ordered collection and caller; {negative_count} negative mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [repo / path for path in add_session_sources(CORE_PATHS)]
    runner = repo / "scripts/verify_eagle_dock_collection.swift"
    assert runner.is_file(), "Standalone collection runner required"
    with tempfile.TemporaryDirectory(prefix="eagle-dock-collection-") as directory:
        work = Path(directory)
        reference = work / "ExactPublicDockGalleryCollection.swift"
        reference.write_text(runtime_projection(values))
        binary = work / "verify-dock-collection"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", *map(str, sources), str(reference), str(runner), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactCollectionSwiftUIBindings.swift"
        fixture.write_text(swiftui_projection(values))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, *map(str, sources), str(fixture)],
            check=True, timeout=55,
        )
    print("PASS: actual list getter/State/value bindings typecheck in inert iOS SwiftUI fixture; temporary outputs cleaned; no app/native engine/IPA", flush=True)


if __name__ == "__main__":
    main()
