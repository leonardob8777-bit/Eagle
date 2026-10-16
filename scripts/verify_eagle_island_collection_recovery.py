#!/usr/bin/env python3
"""Public parity for Island collection projection and cold-start recovery."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/IslandGalleryPresentation.swift"
ROOT = "lara/EagleCore/IslandGallery/"
COLLECTION = ROOT + "EagleIslandGalleryCollection.swift"
RECOVERY = ROOT + "EagleIslandGalleryRecovery.swift"
MARKERS = ["private var artworks:", "private var visibleArtworks:", "private func restoreSelection("]
BRIDGES = ['''private var artworks: [IslandGalleryArtwork] {
        EagleIslandGalleryCollection.assemble(
            styles: { IslandGalleryStyle.allCases },
            isAvailable: { $0.isAvailableInGallery },
            remoteStyle: IslandGalleryStyle.singularityLive,
            themes: { liveThemes },
            makeArtwork: { IslandGalleryArtwork(style: $0, liveTheme: $1) }
        )
    }''', '''private var visibleArtworks: [IslandGalleryArtwork] {
        EagleIslandGalleryCollection.visible(
            search: { search },
            artworks: { artworks },
            filter: { filter },
            favorites: { favorites },
            isLive: { $0.isLive },
            title: { $0.title },
            subtitle: { $0.subtitle }
        )
    }''', '''private func restoreSelection() {
        EagleIslandGalleryRecovery.restore(
            readSelectedRaw: { selectedRaw },
            writeSelectedRaw: { selectedRaw = $0 },
            readSelectedID: { selectedID },
            writeSelectedID: { selectedID = $0 },
            styleForRaw: { IslandGalleryStyle(rawValue: $0) },
            isAvailable: { $0.isAvailableInGallery },
            defaultStyle: { IslandGalleryStyle.starlight },
            remoteStyle: { IslandGalleryStyle.singularityLive },
            artworkID: { IslandGalleryArtwork(style: $0).id },
            readActiveFlags: { activeFlagsRaw },
            readActiveMode: { activeIslandModeRaw },
            readActiveLiveID: { activeLiveID },
            activeArtworkID: { activeArtwork?.id }
        )
    }''']


def originals():
    repo = Path(__file__).resolve().parents[1]
    text = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    return [declaration(text, marker) for marker in MARKERS]


def inline_collection_recovery(view):
    from verify_eagle_island_load_flow import inline_load_flow
    view = inline_load_flow(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return view


def body(method):
    return method[method.index("{"):]


def verify_texts(view, collection, recovery):
    assert hashlib.sha256(inline_collection_recovery(view).encode()).hexdigest() == "a8680ebfd7a6283b9e54ab02d107299f644afaeddd0bc9fa5644983a3fa1a87a", "Unrelated screen change"
    # Lock reviewed generic signatures, constraints, imports and bodies as well.
    assert hashlib.sha256(collection.encode()).hexdigest() == "8b28dda4215ed248113688484e2869df9f5647c1a966f2eaa39aec3bfe9a76cb"
    assert hashlib.sha256(recovery.encode()).hexdigest() == "791486d490e156d93679313399e6915a71be75d73a25165bbfa1ddafe902edaf"
    old = [body(method) for method in originals()]
    replacements = [
        [(r"IslandGalleryStyle.allCases.filter(\.isAvailableInGallery)", "styles().filter(isAvailable)"),
         ("IslandGalleryArtwork(style: style, liveTheme: style == .singularityLive", "makeArtwork(style, style == remoteStyle"),
         ("liveThemes.first", "themes().first"), ("liveThemes.filter", "themes().filter"),
         ("IslandGalleryArtwork(style: .singularityLive, liveTheme: $0)", "makeArtwork(remoteStyle, $0)")],
        [("search.trimmingCharacters", "search().trimmingCharacters"), ("return artworks.filter", "return artworks().filter"),
         ("filter.includes(item, favorites: favorites)", "filter().includes(isLive: isLive(item), artworkID: item.id, favorites: favorites())"),
         ("item.title.localizedStandardContains", "title(item).localizedStandardContains"),
         ("item.subtitle.localizedStandardContains", "subtitle(item).localizedStandardContains")],
        [("IslandGalleryStyle(rawValue: selectedRaw)", "styleForRaw(readSelectedRaw())"),
         ("!oldStyle.isAvailableInGallery", "!isAvailable(oldStyle)"),
         ("selectedRaw = IslandGalleryStyle.starlight.rawValue", "writeSelectedRaw(defaultStyle().rawValue)"),
         ("selectedID == IslandGalleryArtwork(style: oldStyle).id", "readSelectedID() == artworkID(oldStyle)"),
         ('selectedID = ""', 'writeSelectedID("")'), ("selectedID.isEmpty", "readSelectedID().isEmpty"),
         ("activeFlagsRaw & 1", "readActiveFlags() & 1"),
         ("activeIslandModeRaw == IslandGalleryStyle.singularityLive.rawValue", "readActiveMode() == remoteStyle().rawValue"),
         ("selectedID = activeLiveID", "writeSelectedID(readActiveLiveID())"),
         ("let active = activeArtwork { selectedID = active.id }", "let active = activeArtworkID() { writeSelectedID(active) }"),
         ("?? .starlight", "?? defaultStyle()"),
         ("selectedID = IslandGalleryArtwork(style: style).id", "writeSelectedID(artworkID(style))")]
    ]
    for index, rules in enumerate(replacements):
        for before, after in rules:
            # Recovery deliberately reads selectedRaw twice on the fallback path.
            if index == 2 and before == "IslandGalleryStyle(rawValue: selectedRaw)":
                assert old[index].count(before) == 2
                old[index] = old[index].replace(before, after)
            else:
                old[index] = replace_once(old[index], before, after)
    actual = [body(declaration(collection, "static func assemble<")),
              body(declaration(collection, "static func visible<")),
              body(declaration(recovery, "static func restore<"))]
    assert actual == old, "Bodies diverge from counted public algorithms"


def verify_sources(repo):
    texts = [(repo / p).read_text() for p in (VIEW, COLLECTION, RECOVERY)]
    verify_texts(*texts)
    mutations = [
        (0, "themes: { liveThemes }", "themes: { [] }"),
        (0, "search: { search }", 'search: { "" }'),
        (0, "filter: { filter },\n            favorites: { favorites }", "filter: { filter },\n            favorites: { [] }"),
        (0, "activeArtworkID: { activeArtwork?.id }", "activeArtworkID: { nil }"),
        (0, "readActiveLiveID: { activeLiveID }", 'readActiveLiveID: { "singularity-live" }'),
        (0, "eagle.islandGallery.selectedStyle", "eagle.islandGallery.selectedStyleV2"),
        (1, "styles().filter(isAvailable)", "styles()"),
        (1, '$0.id != "singularity-live"', '$0.id == "singularity-live"'),
        (1, "themes().first(where:", "themes().last(where:"),
        (1, ".whitespacesAndNewlines", ".whitespaces"),
        (1, "favorites: favorites()", "favorites: []"),
        (1, "query.isEmpty ||", "query.isEmpty &&"),
        (1, "|| title(item).localizedStandardContains(query)", "|| false"),
        (1, "subtitle(item).localizedStandardContains(query)", "false"),
        (1, "item.id.localizedStandardContains(query)", "false"),
        (2, "!isAvailable(oldStyle)", "isAvailable(oldStyle)"),
        (2, "writeSelectedRaw(defaultStyle().rawValue)", "writeSelectedRaw(36)"),
        (2, 'writeSelectedID("")', 'writeSelectedID("other")'),
        (2, "guard readSelectedID().isEmpty", "guard !readSelectedID().isEmpty"),
        (2, "readActiveFlags() & 1", "readActiveFlags() & 2"),
        (2, "readActiveMode() == remoteStyle().rawValue", "readActiveMode() != remoteStyle().rawValue"),
        (2, "writeSelectedID(readActiveLiveID())", 'writeSelectedID("singularity-live")'),
        (2, "?? defaultStyle()", "?? remoteStyle()"),
        (2, "import Foundation", "import Foundation\nimport UIKit"),
    ]
    for index, before, after in mutations:
        changed = texts.copy(); changed[index] = replace_once(changed[index], before, after)
        try:
            verify_texts(*changed)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    try:
        verify_texts(texts[0] + "\n// unrelated\n", *texts[1:])
    except AssertionError:
        print(f"PASS: three complete public bodies, reviewed APIs and full screen reversal; {len(mutations)+1} mutations rejected", flush=True)
        return
    raise AssertionError("Accepted unrelated screen edit")


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    fixture = (repo / "scripts/verify_eagle_island_collection_recovery.swift").read_text()
    dispatch = '''
    override func collection(_ visible: Bool) -> [String] {
        Trace.current = recorder
        return (visible ? visibleArtworks : artworks).map(\\.snapshot)
    }
    override func restore() { Trace.current = recorder; restoreSelection() }
'''
    for name, methods in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        fixture += "\n@MainActor final class " + name + ": Host {\n    " + "\n    ".join(methods) + dispatch + "}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-island-collection-recovery-") as directory:
        work = Path(directory); source = work / "Checks.swift"; binary = work / "verify"
        source.write_text(fixture)
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        str(repo / (ROOT + "EagleIslandGalleryFilter.swift")), str(repo / COLLECTION), str(repo / RECOVERY),
                        str(source), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
