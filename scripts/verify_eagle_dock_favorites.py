#!/usr/bin/env python3
"""Compare owned favorites JSON with exact public rules and inert storage bindings.

Only Foundation Core helpers and bounded host/SwiftUI fixtures are compiled.
No original app, native applying/access engine, simulator, installed preferences
or IPA is built, executed or modified.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_interactions import inline_interactions


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryFavorites.swift"
THEME_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift"
VIEW_MARKER = "struct DockGalleryView: View"
GETTER_MARKER = "private var favoriteIDs: Set<String>"
TOGGLE_MARKER = "private func toggleFavorite(_ theme: RemoteDockGalleryTheme)"
OWNED_MARKER = "nonisolated enum EagleDockGalleryFavorites"
STORAGE = '@AppStorage("eagle.dockGallery.favoriteIDs") private var favoriteIDsJSON = "[]"'
CHANGE_MARKER = ".onChange(of: favoriteIDsJSON)"
GETTER = """private var favoriteIDs: Set<String> {
        EagleDockGalleryFavorites.decode(favoriteIDsJSON)
    }"""
ENCODE_CALL = "guard let json = EagleDockGalleryFavorites.encode(ids) else { return }"
PUBLIC_TOGGLE = """var ids = favoriteIDs
        if !ids.insert(theme.id).inserted { ids.remove(theme.id) }"""
TOGGLE_CALL = "let ids = EagleDockGalleryFavorites.toggling(favoriteIDs, id: theme.id)"


def replace_counted(source, old, new, label):
    assert source.count(old) == 1, f"Counted favorites boundary changed: {label}"
    return source.replace(old, new, 1)


def encoding_guard(public_toggle):
    start_marker = "guard let data = try? JSONEncoder().encode(ids.sorted()),"
    assert public_toggle.count(start_marker) == 1, "Public encoder guard changed"
    start = public_toggle.index(start_marker)
    end_marker = "else { return }"
    assert public_toggle.count(end_marker) == 1, "Public encoder failure return changed"
    end = public_toggle.index(end_marker, start) + len(end_marker)
    return public_toggle[start:end]


def expected_metadata(public_view):
    public_toggle = declaration(public_view, TOGGLE_MARKER)
    assert public_toggle.count(PUBLIC_TOGGLE) == 1, "Public favorite membership rule changed"
    membership = PUBLIC_TOGGLE.replace("var ids = favoriteIDs", "var updated = ids", 1)
    membership = membership.replace("ids.insert(theme.id)", "updated.insert(id)").replace("ids.remove(theme.id)", "updated.remove(id)")
    toggling = "static func toggling(_ ids: Set<String>, id: String) -> Set<String> {\n" + membership + "\nreturn updated\n}"
    getter = declaration(public_view, GETTER_MARKER)
    decode = replace_counted(
        getter, GETTER_MARKER, "static func decode(_ json: String) -> Set<String>", "getter to pure decode",
    )
    decode = replace_counted(decode, "favoriteIDsJSON", "json", "explicit JSON input")
    guard = encoding_guard(declaration(public_view, TOGGLE_MARKER))
    guard = replace_counted(guard, "else { return }", "else { return nil }", "optional failure result")
    encode = "static func encode(_ ids: Set<String>) -> String? {\n" + guard + "\nreturn json\n}"
    return OWNED_MARKER + " {\n" + toggling + "\n" + decode + "\n" + encode + "\n}"


def project_view_favorites(source):
    """Exactly three counted delegations; shared by the whole-view filter gate."""
    getter = declaration(source, GETTER_MARKER)
    toggle = declaration(source, TOGGLE_MARKER)
    expected_toggle = replace_counted(toggle, encoding_guard(toggle), ENCODE_CALL, "encode guard delegation")
    expected_toggle = replace_counted(expected_toggle, PUBLIC_TOGGLE, TOGGLE_CALL, "membership decision delegation")
    expected = replace_counted(source, getter, GETTER, "decode getter delegation")
    return replace_counted(expected, toggle, expected_toggle, "toggle declaration")


def _verify_contract(public_view, current, model):
    code = re.sub(r"//[^\n]*", "", model)
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_metadata(public_view)), (
        "Owned favorites differ from public toggle/UTF8/default JSON decode/Set/sorted encode/optional failure rules"
    )
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], (
        "Favorites gained imports, storage or external code"
    )
    expected_view = project_view_favorites(public_view)
    expanded = inline_interactions(current)
    for marker in (GETTER_MARKER, TOGGLE_MARKER):
        assert compact(declaration(expanded, marker)) == compact(declaration(expected_view, marker)), (
            f"Favorites screen storage/toggle/early-return/effect sequence changed: {marker}"
        )
    assert public_view.count(STORAGE) == 1 and current.count(STORAGE) == 1, "Existing preference key/default changed"
    assert compact(declaration(current, CHANGE_MARKER)) == compact(declaration(public_view, CHANGE_MARKER)), (
        "The existing favorites change observer changed"
    )


def verify_sources(repo):
    """Import-safe source-only contract for this and the wider model gate."""
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
        ("model", "json.data(using: .utf8)", "json.data(using: .utf16)"),
        ("model", "decode([String].self, from: data)", "decode(Set<String>.self, from: data)"),
        ("model", "else { return [] }", 'else { return ["repaired"] }'),
        ("model", "return Set(ids)", "return Set(ids.map { $0.lowercased() })"),
        ("model", "return Set(ids)", "return Set(ids.filter { !$0.isEmpty })"),
        ("model", "ids.sorted()", "Array(ids)"),
        ("model", "ids.sorted()", "ids.sorted(by: >)"),
        ("model", "JSONEncoder().encode(ids.sorted())", "JSONEncoder().encode(ids.sorted().map { $0.trimmingCharacters(in: .whitespaces) })"),
        ("model", "String(data: data, encoding: .utf8)", "String(data: data, encoding: .utf16)"),
        ("model", "else { return nil }", 'else { return "[]" }'),
        ("model", "return json\n", 'return "[]"\n'),
        ("model", "import Foundation", "import Foundation\nimport SwiftUI"),
        ("model", "import Foundation", "import Foundation\nvar cachedFavorites: Set<String> = []"),
        ("current", "EagleDockGalleryFavorites.decode(favoriteIDsJSON)", "EagleDockGalleryFavorites.decode(\"[]\")"),
        ("current", "writeFavoritesJSON: { favoriteIDsJSON = $0 }", 'writeFavoritesJSON: { _ in favoriteIDsJSON = "[]" }'),
        ("current", "readFavorites: { favoriteIDs }", "readFavorites: { [theme.title] }"),
        ("current", "writeFavoritesJSON: { favoriteIDsJSON = $0 }", "writeFavoritesJSON: { synchronizeRemoteSelection(); favoriteIDsJSON = $0 }"),
        ("current", "writeFavoritesJSON: { favoriteIDsJSON = $0 }", "writeFavoritesJSON: { favoriteIDsJSON = $0; UISelectionFeedbackGenerator().selectionChanged() }"),
        ("current", STORAGE, STORAGE.replace("favoriteIDs\"", "favoriteIDsV2\"")),
        ("current", STORAGE, STORAGE.replace('= "[]"', '= ""')),
        ("current", ".onChange(of: favoriteIDsJSON)", ".onChange(of: selectedRemoteID)"),
        ("model", "if !updated.insert(id).inserted", "if updated.insert(id).inserted"),
        ("model", "if !updated.insert(id).inserted { updated.remove(id) }", "updated.insert(id)"),
        ("model", "if !updated.insert(id).inserted { updated.remove(id) }", "updated.remove(id)"),
        ("model", "var updated = ids", "var updated: Set<String> = []"),
        ("model", "return updated", "return ids"),
        ("model", "updated.insert(id)", "updated.insert(id.lowercased())"),
        ("model", "updated.remove(id)", "updated.remove(id.trimmingCharacters(in: .whitespaces))"),
        ("model", "var updated = ids", 'guard !id.isEmpty else { return ids }; var updated = ids'),
        ("current", "readFavorites: { favoriteIDs }", "readFavorites: { [] }"),
        ("current", "readFavorites: { favoriteIDs }", "readFavorites: { _ = favoriteIDs; return favoriteIDs }"),
    ]
    for field, old, new in cases:
        altered = values.copy()
        altered[field] = replace_counted(altered[field], old, new, f"negative {field}")
        try:
            _verify_contract(altered["public_view"], altered["current"], altered["model"])
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Changed favorites source escaped rejection: {old}")
    return len(cases)


def runtime_projection(values):
    # The runtime reference comes from the exact public statements above.
    # Its actor annotation is only a fixture property, not a production edit.
    metadata = replace_counted(
        expected_metadata(values["public_view"]), OWNED_MARKER,
        "enum BaselineDockGalleryFavorites", "public runtime name/actor fixture",
    )
    return "import Foundation\n\n" + metadata + "\n"


def swiftui_projection(values):
    view = declaration(values["current"], VIEW_MARKER)
    storage = next(line.strip() for line in view.splitlines() if STORAGE in line)
    getter = declaration(view, GETTER_MARKER)
    toggle = declaration(view, TOGGLE_MARKER)
    return "import Foundation\nimport SwiftUI\nimport UIKit\n\nprivate struct FavoritesStorageFixture: View {\n" + """
    private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
""" + storage + "\n" + getter + "\n" + toggle + "\n" + """
    var body: some View { Text(String(favoriteIDs.count)) }
    private func synchronizeRemoteSelection() {}
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    negative_count = verify_memory_negatives(values)
    print(f"PASS: exact public/owned favorites rules and unchanged storage/effect wiring; {negative_count} negative mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    model = repo / MODEL_PATH
    runner = repo / "scripts/verify_eagle_dock_favorites.swift"
    assert runner.is_file(), "Standalone favorites runner required"
    with tempfile.TemporaryDirectory(prefix="eagle-dock-favorites-") as directory:
        work = Path(directory)
        reference = work / "ExactPublicDockGalleryFavorites.swift"
        reference.write_text(runtime_projection(values))
        binary = work / "verify-dock-favorites"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", str(model), str(reference), str(runner), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactFavoritesSwiftUIStorage.swift"
        fixture.write_text(swiftui_projection(values))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        from verify_eagle_dock_session import add_session_sources
        sources = [str(repo / path) for path in add_session_sources((MODEL_PATH, THEME_PATH))]
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, *sources, str(fixture)],
            check=True, timeout=55,
        )
    print("PASS: exact AppStorage/getter/toggle compile in inert iOS SwiftUI fixture; temporary host outputs cleaned; no original app/native engine/preferences/IPA", flush=True)


if __name__ == "__main__":
    main()
