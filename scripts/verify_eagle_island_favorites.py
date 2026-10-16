#!/usr/bin/env python3
"""Compare Island favorites with public code without UI or native execution."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/IslandGalleryPresentation.swift"
MODEL = "lara/EagleCore/IslandGallery/EagleIslandGalleryFavorites.swift"
GETTER = '''private var favorites: Set<String> {
        guard let data = favoritesJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }'''
TOGGLE = '''private func toggleFavorite(_ item: IslandGalleryArtwork) {
        guard !applying else { return }
        var ids = favorites
        if !ids.insert(item.id).inserted { ids.remove(item.id) }
        if let data = try? JSONEncoder().encode(ids.sorted()), let json = String(data: data, encoding: .utf8) {
            favoritesJSON = json
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }'''
GETTER_BRIDGE = '''private var favorites: Set<String> {
        EagleIslandGalleryFavorites.decode(favoritesJSON)
    }'''
TOGGLE_BRIDGE = '''private func toggleFavorite(_ item: IslandGalleryArtwork) {
        EagleIslandGalleryFavorites.toggle(
            applying: { applying },
            favorites: { favorites },
            artworkID: { item.id },
            save: { favoritesJSON = $0 },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }'''
HEADER = '''@MainActor
    static func toggle(
        applying: () -> Bool,
        favorites: () -> Set<String>,
        artworkID: () -> String,
        save: (String) -> Void,
        feedback: () -> Void
    )'''


def inline_favorites(view):
    from verify_eagle_island_selection import inline_selection
    view = inline_selection(view)
    return replace_once(replace_once(view, GETTER_BRIDGE, GETTER), TOGGLE_BRIDGE, TOGGLE)


def expected_model():
    getter = replace_once(GETTER, "private var favorites: Set<String>", "static func decode(_ json: String) -> Set<String>")
    getter = replace_once(getter, "favoritesJSON.data", "json.data")
    toggle = replace_once(TOGGLE, "private func toggleFavorite(_ item: IslandGalleryArtwork)", HEADER)
    for old, new in (("!applying", "!applying()"), ("var ids = favorites", "var ids = favorites()"),
                     ("ids.insert(item.id)", "ids.insert(artworkID())"),
                     ("ids.remove(item.id)", "ids.remove(artworkID())"),
                     ("favoritesJSON = json", "save(json)"),
                     ("UISelectionFeedbackGenerator().selectionChanged()", "feedback()")):
        toggle = replace_once(toggle, old, new)
    return '''import Foundation

/// Owns Island favorite decoding and toggle/write/feedback sequencing.
/// The screen retains its existing AppStorage key and observation behavior.
nonisolated enum EagleIslandGalleryFavorites {
    ''' + getter + "\n\n    " + toggle + "\n}\n"


def verify_texts(view, model):
    assert hashlib.sha256(inline_favorites(view).encode()).hexdigest() == "ae2bd9aee9f9fc635a22e86057ab7d27be8cca115f5ff3fa067eca30e766a71e", "Unrelated screen/storage/observer edit"
    assert model == expected_model(), "Favorites differs from counted public extraction"


def verify_sources(repo):
    view, model = [(repo / path).read_text() for path in (VIEW, MODEL)]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    assert declaration(public, "private var favorites:") == GETTER
    assert declaration(public, "private func toggleFavorite(") == TOGGLE
    verify_texts(view, model)
    cases = (
        ("model", "guard !applying()", "guard applying()"),
        ("model", "else { return [] }", 'else { return ["other"] }'),
        ("model", "return Set(ids)", "return []"),
        ("model", "ids.sorted()", "Array(ids)"),
        ("model", "ids.remove(artworkID())", 'ids.remove("other")'),
        ("model", "ids.insert(artworkID())", 'ids.insert("other")'),
        ("model", "save(json)", "feedback()\n            save(json)"),
        ("model", "var ids = favorites()", "var ids: Set<String> = []"),
        ("model", "import Foundation", "import Foundation\nimport UIKit"),
        ("view", 'eagle.islandGallery.favoriteIDs', 'eagle.islandGallery.favoritesV2'),
        ("view", "applying: { applying }", "applying: { false }"),
        ("view", "favorites: { favorites },\n            artworkID:", "favorites: { [] },\n            artworkID:"),
        ("view", "artworkID: { item.id }", 'artworkID: { "other" }'),
        ("view", "save: { favoritesJSON = $0 }", "save: { _ in }"),
        ("view", "EagleIslandGalleryFavorites.decode(favoritesJSON)", 'EagleIslandGalleryFavorites.decode("[]")'),
    )
    for target, old, new in cases:
        changed = replace_once(view if target == "view" else model, old, new)
        try:
            verify_texts(changed if target == "view" else view, changed if target == "model" else model)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted regression: {old}")
    try:
        verify_texts(view + "\n// unrelated edit\n", model)
    except AssertionError:
        print(f"PASS: exact public favorites extraction and whole-screen reversal; {len(cases) + 1} negative mutations rejected", flush=True)
        return
    raise AssertionError("Accepted unrelated edit")


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    fixture = '''import Foundation
@MainActor final class Recorder {
    var json: String
    let busy: Bool
    var events: [String] = []
    init(_ json: String, _ busy: Bool) { self.json = json; self.busy = busy }
}
@MainActor struct IslandGalleryArtwork {
    let identifier: String
    let recorder: Recorder
    var id: String { recorder.events.append("id"); return identifier }
}
@MainActor struct UISelectionFeedbackGenerator {
    static var recorder: Recorder?
    func selectionChanged() { Self.recorder!.events.append("feedback") }
}
'''
    for name, getter, toggle in (("PublicHost", GETTER, TOGGLE), ("OwnedHost", GETTER_BRIDGE, TOGGLE_BRIDGE)):
        fixture += f"@MainActor final class {name} {{\n" + '''
    let recorder: Recorder
    init(_ recorder: Recorder) { self.recorder = recorder }
    var applying: Bool { recorder.events.append("busy"); return recorder.busy }
    var favoritesJSON: String {
        get { recorder.events.append("read"); return recorder.json }
        set { recorder.events.append("save"); recorder.json = newValue }
    }
    ''' + getter + "\n    " + toggle + '''
    func run(_ identifier: String) {
        UISelectionFeedbackGenerator.recorder = recorder
        toggleFavorite(IslandGalleryArtwork(identifier: identifier, recorder: recorder))
    }
    func decoded() -> Set<String> { favorites }
}
'''
    fixture += r'''
@main struct Checks {
    static func main() async {
        let identifiers = ["", "island-9", "other", "UNKNOWN", "á", "a\u{301}", "🌈", "a/b", "quote\"", "line\n"]
        var inputs = ["", "[", "null", "{}", "[1]", "[\"x\",null]", "[]", "[\"island-9\",\"island-9\"]"]
        for id in identifiers {
            for list in [[id], [id, id], ["other", id, "island-9"]] {
                inputs.append(String(data: try! JSONEncoder().encode(list), encoding: .utf8)!)
            }
        }
        var cases = 0
        var decodes = 0
        var events = 0
        for json in inputs {
            let decoded = PublicHost(Recorder(json, false)).decoded()
            precondition(EagleIslandGalleryFavorites.decode(json) == decoded)
            let detached = await Task.detached { EagleIslandGalleryFavorites.decode(json) }.value
            precondition(detached == decoded)
            decodes += 1
            for busy in [false, true] {
                for identifier in identifiers {
                    let old = Recorder(json, busy)
                    let owned = Recorder(json, busy)
                    let oldHost = PublicHost(old)
                    let ownedHost = OwnedHost(owned)
                    // Consecutive taps exercise both insertion and removal without stale snapshots.
                    for _ in 0..<4 {
                        let before = EagleIslandGalleryFavorites.decode(old.json)
                        old.events = []; owned.events = []
                        oldHost.run(identifier); ownedHost.run(identifier)
                        precondition(old.json == owned.json && old.events == owned.events)
                        let expected = busy ? ["busy"] : ["busy", "read", "id"] + (before.contains(identifier) ? ["id"] : []) + ["save", "feedback"]
                        precondition(owned.events == expected)
                        if busy {
                            precondition(owned.json == json)
                        } else {
                            var next = before
                            if !next.insert(identifier).inserted { next.remove(identifier) }
                            let saved = try! JSONDecoder().decode([String].self, from: Data(owned.json.utf8))
                            precondition(saved == next.sorted())
                        }
                        events += owned.events.count
                        cases += 1
                    }
                    if !busy { precondition(EagleIslandGalleryFavorites.decode(owned.json) == decoded) }
                }
            }
        }
        print("PASS: \(cases) repeated-toggle public/owned cases; \(events) exact ordered events, busy guards and sorted persistence")
        print("PASS: \(decodes) decode cases also detached; malformed/duplicate/unknown/Unicode IDs and semantic round trips")
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="eagle-island-favorites-") as directory:
        work = Path(directory)
        source = work / "FavoritesChecks.swift"
        source.write_text(fixture)
        binary = work / "verify"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        str(repo / MODEL), str(source), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
