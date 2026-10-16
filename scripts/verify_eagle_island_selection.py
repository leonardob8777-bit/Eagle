#!/usr/bin/env python3
"""Verify the complete Island selection/navigation block without native execution."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/IslandGalleryPresentation.swift"
MODEL = "lara/EagleCore/IslandGallery/EagleIslandGallerySelection.swift"
FILTER = "lara/EagleCore/IslandGallery/EagleIslandGalleryFilter.swift"
MARKERS = ["private var selected:", "private var selectionIndex:", "private func select(",
           "private func selectFilter(", "private func synchronizeSelection(", "private func step("]
BRIDGES = ['''private var selected: IslandGalleryArtwork? {
        selectionController.selected
    }''', '''private var selectionIndex: Int {
        selectionController.selectionIndex
    }''', '''private func select(_ item: IslandGalleryArtwork) {
        selectionController.select(item)
    }''', '''private func selectFilter(_ value: IslandGalleryFilter) {
        selectionController.selectFilter(value)
    }''', '''private func synchronizeSelection() {
        selectionController.synchronizeSelection()
    }''', '''private func step(_ delta: Int) {
        selectionController.step(delta)
    }''']
CONTROLLER = '''private var selectionController: EagleIslandGallerySelection<IslandGalleryArtwork> {
        EagleIslandGallerySelection(
            readVisibleArtworks: { self.visibleArtworks },
            readApplying: { self.applying },
            readSelectedID: { self.selectedID },
            writeSelectedID: { self.selectedID = $0 },
            writeSelectedRaw: { self.selectedRaw = $0 },
            readFilter: { self.filter },
            writeFilter: { self.filter = $0 },
            readMemory: { self.rememberedSelections },
            writeMemory: { self.rememberedSelections = $0 },
            rawStyle: { $0.style.rawValue },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }'''
HEADER = '''import Foundation

/// Synchronous selection, category memory and navigation coordination.
/// Storage remains supplied by the screen; reads are deferred to preserve ordering.
@MainActor
struct EagleIslandGallerySelection<Artwork: Identifiable> where Artwork.ID == String {
    let readVisibleArtworks: () -> [Artwork]
    let readApplying: () -> Bool
    let readSelectedID: () -> String
    let writeSelectedID: (String) -> Void
    let writeSelectedRaw: (Int) -> Void
    let readFilter: () -> EagleIslandGalleryFilter
    let writeFilter: (EagleIslandGalleryFilter) -> Void
    let readMemory: () -> [EagleIslandGalleryFilter: String]
    let writeMemory: ([EagleIslandGalleryFilter: String]) -> Void
    let rawStyle: (Artwork) -> Int
    let feedback: () -> Void

    private var visibleArtworks: [Artwork] { readVisibleArtworks() }
    private var applying: Bool { readApplying() }
    private var selectedID: String {
        get { readSelectedID() }
        nonmutating set { writeSelectedID(newValue) }
    }
    private var filter: EagleIslandGalleryFilter {
        get { readFilter() }
        nonmutating set { writeFilter(newValue) }
    }
    private var rememberedSelections: [EagleIslandGalleryFilter: String] {
        get { readMemory() }
        nonmutating set { writeMemory(newValue) }
    }'''


def originals():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    return [declaration(public, marker) for marker in MARKERS]


def inline_selection(view):
    from verify_eagle_island_collection_recovery import inline_collection_recovery
    view = inline_collection_recovery(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_model():
    methods = []
    for method in originals():
        method = replace_once(method, "private ", "")
        method = method.replace("IslandGalleryArtwork", "Artwork").replace("IslandGalleryFilter", "EagleIslandGalleryFilter")
        for name in ("item", "selected", "first"):
            old = f"selectedRaw = {name}.style.rawValue"
            if old in method:
                method = replace_once(method, old, f"writeSelectedRaw(rawStyle({name}))")
        if "UISelectionFeedbackGenerator().selectionChanged()" in method:
            method = replace_once(method, "UISelectionFeedbackGenerator().selectionChanged()", "feedback()")
        methods.append(method)
    return HEADER + "\n\n    " + "\n\n    ".join(methods) + "\n}\n"


def verify_texts(view, model):
    assert hashlib.sha256(inline_selection(view).encode()).hexdigest() == "ad460fd763801a7c71939b49e7b79b1522f8bf0f632e34c7d27e8a58d8efb253", "Selection extraction changed other screen behavior"
    assert model == expected_model(), "Core differs from complete counted public selection methods"


def verify_sources(repo):
    view, model = [(repo / path).read_text() for path in (VIEW, MODEL)]
    verify_texts(view, model)
    mutations = [
        ("model", "?? visibleArtworks.first", "?? visibleArtworks.last"),
        ("model", "?? 0", "?? 1"),
        ("model", "writeSelectedRaw(rawStyle(item))", "writeSelectedRaw(36)"),
        ("model", "rememberedSelections[filter] = item.id", "rememberedSelections[.all] = item.id"),
        ("model", "feedback()\n    }", "// feedback omitted\n    }"),
        ("model", "filter = value", "filter = .all"),
        ("model", "rememberedSelections[value]", "rememberedSelections[.all]"),
        ("model", "selectedID = remembered", 'selectedID = ""'),
        ("model", "synchronizeSelection()\n        if let selected", "if let selected"),
        ("model", "guard !applying, visibleArtworks.count > 1", "guard !applying, visibleArtworks.count > 0"),
        ("model", "selectionIndex + delta", "selectionIndex - delta"),
        ("model", "select(visibleArtworks[next])", "select(visibleArtworks[0])"),
        ("model", "get { readMemory() }", "get { [:] }"),
        ("model", "nonmutating set { writeMemory(newValue) }", "nonmutating set {}"),
        ("model", "import Foundation", "import Foundation\nimport UIKit"),
        ("view", "readApplying: { self.applying }", "readApplying: { false }"),
        ("view", "readVisibleArtworks: { self.visibleArtworks }", "readVisibleArtworks: { artworks }"),
        ("view", "writeSelectedRaw: { self.selectedRaw = $0 }", "writeSelectedRaw: { _ in }"),
        ("view", "writeSelectedID: { self.selectedID = $0 }", "writeSelectedID: { _ in }"),
        ("view", "writeMemory: { self.rememberedSelections = $0 }", "writeMemory: { _ in }"),
        ("view", "rawStyle: { $0.style.rawValue }", "rawStyle: { _ in 36 }"),
        ("view", "selectionController.step(delta)", "selectionController.step(1)"),
        ("view", "eagle.islandGallery.selectedArtworkID", "eagle.islandGallery.selectedArtworkIDV2"),
    ]
    for target, old, new in mutations:
        changed = replace_once(view if target == "view" else model, old, new)
        try:
            verify_texts(changed if target == "view" else view, changed if target == "model" else model)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation: {old}")
    try:
        verify_texts(view + "\n// unrelated\n", model)
    except AssertionError:
        print(f"PASS: six complete public methods, exact screen bridge and reversal; {len(mutations)+1} rejected mutations", flush=True)
        return
    raise AssertionError("Accepted unrelated edit")


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    fixture = (repo / "scripts/verify_eagle_island_selection.swift").read_text()
    dispatch = '''
    override func run(_ action: Action) -> String {
        UISelectionFeedbackGenerator.recorder = recorder
        switch action {
        case .selected: return selected?.id ?? "<nil>"
        case .index: return String(selectionIndex)
        case .select(let id): select(artwork(id))
        case .category(let value): selectFilter(value)
        case .sync: synchronizeSelection()
        case .step(let delta): step(delta)
        }
        return "done"
    }
'''
    for name, methods in (("PublicHost", originals()), ("OwnedHost", BRIDGES + [CONTROLLER])):
        fixture += "\n@MainActor final class " + name + ": Host {\n    " + "\n    ".join(methods) + dispatch + "}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-island-selection-core-") as directory:
        work = Path(directory)
        source = work / "SelectionChecks.swift"
        source.write_text(fixture)
        binary = work / "verify"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        str(repo / FILTER), str(repo / MODEL), str(source), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
