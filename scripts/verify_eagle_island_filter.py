#!/usr/bin/env python3
"""Verify the Island category extraction against the public declaration and whole screen."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/IslandGalleryPresentation.swift"
MODEL = "lara/EagleCore/IslandGallery/EagleIslandGalleryFilter.swift"
ORIGINAL = '''enum IslandGalleryFilter: String, CaseIterable, Identifiable {
    case all, live, still, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return LaraL10n.text(en: "All", es: "Todo")
        case .live: return "Live"
        case .still: return "Static"
        case .favorites: return "Saves"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .live: return "play.circle"
        case .still: return "sparkles"
        case .favorites: return "heart"
        }
    }
    func includes(_ artwork: IslandGalleryArtwork, favorites: Set<String>) -> Bool {
        switch self {
        case .all: return true
        case .live: return artwork.isLive
        case .still: return !artwork.isLive
        case .favorites: return favorites.contains(artwork.id)
        }
    }
}'''
BRIDGE = '''typealias IslandGalleryFilter = EagleIslandGalleryFilter

extension EagleIslandGalleryFilter {
    var title: String {
        title(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
    func includes(_ artwork: IslandGalleryArtwork, favorites: Set<String>) -> Bool {
        includes(isLive: artwork.isLive, artworkID: artwork.id, favorites: favorites)
    }
}'''
HEADER = '''func includes(
        isLive: @autoclosure () -> Bool,
        artworkID: @autoclosure () -> String,
        favorites: Set<String>
    ) -> Bool'''
COMMENTS = '''/// Island category metadata and inclusion rules, independent of presentation.
/// Deferred properties preserve the original per-category artwork reads.
'''


def inline_filter(view):
    from verify_eagle_island_favorites import inline_favorites
    view = inline_favorites(view)
    return replace_once(view, BRIDGE, ORIGINAL)


def expected_model():
    result = ORIGINAL
    for old, new in (
        ("enum IslandGalleryFilter: String, CaseIterable, Identifiable", "nonisolated enum EagleIslandGalleryFilter: String, CaseIterable, Identifiable, Sendable"),
        ("var title: String", "func title(localizedText: (String, String) -> String) -> String"),
        ('LaraL10n.text(en: "All", es: "Todo")', 'localizedText("All", "Todo")'),
        ("func includes(_ artwork: IslandGalleryArtwork, favorites: Set<String>) -> Bool", HEADER),
        ("return artwork.isLive", "return isLive()"),
        ("return !artwork.isLive", "return !isLive()"),
        ("favorites.contains(artwork.id)", "favorites.contains(artworkID())"),
    ):
        result = replace_once(result, old, new)
    return "import Foundation\n\n" + COMMENTS + result + "\n"


def verify_texts(view, model):
    assert hashlib.sha256(inline_filter(view).encode()).hexdigest() == "7f4a22f14536451cecd56327bb204a1334279facac49cdce87154883b4c27225", \
        "Island presentation changed beyond the exact category/bridge move"
    assert model == expected_model(), "Island filter differs from counted public declaration"


def verify_sources(repo):
    view, model = [(repo / path).read_text() for path in (VIEW, MODEL)]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    assert declaration(public, "enum IslandGalleryFilter:") == ORIGINAL
    verify_texts(view, model)
    cases = (
        ("model", "case all, live, still, favorites", "case all, still, live, favorites"),
        ("model", 'return "Static"', 'return "Still"'),
        ("model", 'localizedText("All", "Todo")', 'localizedText("All", "Todos")'),
        ("model", 'return "Saves"', 'return "Favorites"'),
        ("model", 'return "heart"', 'return "star"'),
        ("model", "case .all: return true", "case .all: return false"),
        ("model", "case .live: return isLive()", "case .live: return !isLive()"),
        ("model", "case .still: return !isLive()", "case .still: return isLive()"),
        ("model", "favorites.contains(artworkID())", 'favorites.contains("singularity-live")'),
        ("model", "isLive: @autoclosure () -> Bool", "isLive: Bool"),
        ("model", "import Foundation", "import Foundation\nimport UIKit"),
        ("view", "isLive: artwork.isLive", "isLive: true"),
        ("view", "artworkID: artwork.id", 'artworkID: "other"'),
        ("view", "LaraL10n.text(en: $0, es: $1)", "LaraL10n.text(en: $1, es: $0)"),
    )
    for target, old, new in cases:
        changed = replace_once(view if target == "view" else model, old, new)
        try:
            verify_texts(changed if target == "view" else view, changed if target == "model" else model)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted filter regression: {old}")
    try:
        verify_texts(view + "\n// unrelated edit\n", model)
    except AssertionError:
        print(f"PASS: exact public category/bridge extraction and whole-screen reversal; {len(cases) + 1} negative mutations rejected", flush=True)
        return public
    raise AssertionError("Accepted unrelated screen edit")


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    reference = replace_once(ORIGINAL, "enum IslandGalleryFilter:", "@MainActor enum PublicIslandGalleryFilter:")
    fixture = "import Foundation\n" + reference + "\n" + BRIDGE + '''
@MainActor final class Recorder {
    var events: [String] = []
    var language = "en"
}
@MainActor enum LaraL10n {
    static let recorder = Recorder()
    static func text(en: String, es: String) -> String {
        recorder.events.append("language.\\(en).\\(es)")
        return recorder.language == "es" ? es : en
    }
}
@MainActor struct IslandGalleryArtwork {
    let live: Bool
    let identifier: String
    let recorder: Recorder
    var isLive: Bool { recorder.events.append("live"); return live }
    var id: String { recorder.events.append("id"); return identifier }
}
@main struct Checks {
    static func main() async {
        let raw = ["all", "live", "still", "favorites"]
        precondition(EagleIslandGalleryFilter.allCases.map(\\.rawValue) == raw)
        precondition(PublicIslandGalleryFilter.allCases.map(\\.rawValue) == raw)
        // The existing picker deliberately orders Static before Live.
        precondition([IslandGalleryFilter.all, .still, .live, .favorites].map(\\.rawValue) == ["all", "still", "live", "favorites"])
        for value in raw + ["", "All", "Static", "Saves", "unknown"] {
            precondition(EagleIslandGalleryFilter(rawValue: value)?.rawValue == PublicIslandGalleryFilter(rawValue: value)?.rawValue)
        }
        var labels = 0
        for language in ["en", "es", "en"] {
            LaraL10n.recorder.language = language
            for old in PublicIslandGalleryFilter.allCases {
                let owned = EagleIslandGalleryFilter(rawValue: old.rawValue)!
                LaraL10n.recorder.events = []
                let expected = old.title
                let events = LaraL10n.recorder.events
                LaraL10n.recorder.events = []
                precondition(owned.title == expected && LaraL10n.recorder.events == events)
                precondition(events.count == (old == .all ? 1 : 0))
                precondition(owned.id == old.id && owned.icon == old.icon)
                labels += 1
            }
        }
        var cases = 0
        for identifier in ["", "island-9", "singularity-live", "blue-flame", "UNKNOWN", "á", "a\\u{301}", "🌈"] {
            let sets: [Set<String>] = [[], [identifier], ["other"], ["island-9", "singularity-live"], [identifier, "other"], ["á"]]
            for live in [false, true] {
                for favorites in sets {
                    for old in PublicIslandGalleryFilter.allCases {
                        let owned = EagleIslandGalleryFilter(rawValue: old.rawValue)!
                        let recorder = Recorder()
                        let artwork = IslandGalleryArtwork(live: live, identifier: identifier, recorder: recorder)
                        let expected = old.includes(artwork, favorites: favorites)
                        let reads = recorder.events
                        recorder.events = []
                        precondition(owned.includes(artwork, favorites: favorites) == expected)
                        precondition(recorder.events == reads)
                        let exactReads = old == .all ? [] : old == .favorites ? ["id"] : ["live"]
                        precondition(reads == exactReads, "Unnecessary/eager artwork reads")
                        let detached = await Task.detached { owned.includes(isLive: live, artworkID: identifier, favorites: favorites) }.value
                        precondition(detached == expected)
                        cases += 1
                    }
                }
            }
        }
        print("PASS: \\(cases) public/owned category cases also detached, with exact per-category property reads")
        print("PASS: \\(labels) late-language/metadata checks; raw identity, picker order, invalid IDs and unchanged app bridge")
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="eagle-island-filter-") as directory:
        work = Path(directory)
        source = work / "FilterChecks.swift"
        source.write_text(fixture)
        binary = work / "verify"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        str(repo / MODEL), str(source), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
