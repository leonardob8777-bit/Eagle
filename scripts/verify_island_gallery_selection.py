#!/usr/bin/env python3
"""Test the production Island Gallery models/selection helpers, without native writes."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
source = (repo / "lara/views/new/IslandGalleryPresentation.swift").read_text()
assert "IslandGalleryScene" not in source
assert "presentationPicker" not in source
assert "collectionIntro" not in source
assert "Small Island" not in source
assert "A preview of the look" not in source
filter_model = (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryFilter.swift").read_text()
assert 'case .still: return "Static"' in filter_model


def declaration(marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


style = (repo / "lara/views/new/IslandGalleryView.swift").read_text().split("private final class IslandGalleryRemoteCallBox:")[0]
model = (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift").read_text() + "\n" + (repo / "lara/views/new/IslandLiveMedia.swift").read_text().split("/// An isolated,")[0]
types = (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryFavorites.swift").read_text() + "\n" + filter_model + "\n" + source.split("struct IslandGalleryView: View")[0]
types = (repo / "lara/EagleCore/IslandGallery/EagleIslandGallerySelection.swift").read_text() + "\n" + types
types = "\n".join((repo / f"lara/EagleCore/IslandGallery/EagleIslandGallery{name}.swift").read_text()
                  for name in ("Collection", "Recovery")) + "\n" + types
helpers = "\n".join(declaration(marker) for marker in [
    "private var artworks:", "private var favorites:", "private var visibleArtworks:",
    "private var selected:", "private var activeArtwork:",
    "private var hasRetiredIslandStyle:", "private func isActive(",
    "private var selectionIndex:", "private var selectionController:", "private func toggleFavorite(", "private func select(",
    "private func selectFilter(", "private func synchronizeSelection(",
    "private func restoreSelection(", "private func step(",
])
stub = r'''
enum LaraL10n { static func text(en: String, es: String) -> String { es } }
enum IslandLiveMedia {
    static let previewURL = URL(string: "https://example.test/singularity-live.gif")!
    static let posterURL = URL(string: "https://example.test/singularity-live.png")!
}
struct UISelectionFeedbackGenerator { func selectionChanged() {} }
@MainActor final class Harness {
    var selectedRaw = IslandGalleryStyle.starlight.rawValue
    var selectedID = ""
    var favoritesJSON = "[]"
    var activeFlagsRaw = 0
    var activeIslandModeRaw = 0
    var activeLiveID = "singularity-live"
    var liveThemes: [IslandLiveTheme] = []
    var filter: IslandGalleryFilter = .all
    var search = ""
    var applying = false
    var rememberedSelections: [IslandGalleryFilter: String] = [:]
'''
tests = r'''
    static func verify() throws {
        let catalog = try JSONDecoder().decode(IslandLiveCatalog.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        assert(catalog.isSupported)
        let h = Harness()
        assert(IslandGalleryFilter.still.title == "Static")
        assert(IslandGalleryFilter.favorites.title == "Saves")
        h.restoreSelection()
        assert(h.selectedID == "island-9")
        h.liveThemes = catalog.themes
        let liveCount = catalog.themes.filter(\.isAnimated).count
        let stillCount = catalog.themes.count - liveCount + 6
        let allCount = catalog.themes.count + 6
        assert(h.artworks.count == allCount && Set(h.artworks.map(\.id)).count == allCount)
        assert(Set(h.artworks.map(\.id)).isDisjoint(with: ["island-32", "island-33", "island-34"]))
        let retired = Harness()
        retired.selectedRaw = 32
        retired.selectedID = "island-32"
        retired.restoreSelection()
        assert(retired.selectedID == "island-9" && retired.selectedRaw == 9)
        retired.activeFlagsRaw = 1
        retired.activeIslandModeRaw = 32
        assert(retired.hasRetiredIslandStyle && retired.activeArtwork == nil)
        h.selectFilter(.live)
        assert(h.visibleArtworks.count == liveCount)
        var seen = Set<String>()
        for _ in 0..<liveCount { seen.insert(h.selected!.id); h.step(1) }
        assert(seen.count == liveCount && h.selectionIndex == 0)
        h.step(-1)
        assert(h.selectionIndex == liveCount - 1)
        let lastLive = h.selected!
        h.selectFilter(.still)
        assert(h.visibleArtworks.count == stillCount)
        h.step(3)
        let still = h.selected!
        h.selectFilter(.live)
        assert(h.selectedID == lastLive.id && h.selectedRaw == 36)
        h.selectFilter(.still)
        assert(h.selectedID == still.id && h.selectedRaw == still.style.rawValue)
        h.toggleFavorite(still)
        h.toggleFavorite(lastLive)
        h.selectFilter(.favorites)
        assert(h.visibleArtworks.count == 2)
        let saved = Harness()
        saved.liveThemes = catalog.themes
        saved.favoritesJSON = h.favoritesJSON
        saved.selectFilter(.favorites)
        assert(Set(saved.visibleArtworks.map(\.id)) == [still.id, lastLive.id])
        h.toggleFavorite(still)
        h.synchronizeSelection() // The view's onChange observer.
        assert(h.selected?.id == lastLive.id)
        h.toggleFavorite(lastLive)
        h.synchronizeSelection()
        assert(h.visibleArtworks.isEmpty && h.selected == nil)
        h.step(1)
        h.selectFilter(.all)
        h.search = "  BLUE-FLAME  "
        h.synchronizeSelection()
        assert(h.visibleArtworks.count == 1 && h.selected?.id == "blue-flame")
        h.search = "no-such-island-style"
        h.synchronizeSelection()
        assert(h.selected == nil)
        h.search = ""
        h.synchronizeSelection()
        assert(h.selected?.id == "blue-flame")
        h.activeFlagsRaw = 1
        h.activeIslandModeRaw = 36
        h.activeLiveID = "blue-flame"
        assert(h.artworks.filter(h.isActive).map(\.id) == ["blue-flame"])
        h.applying = true
        let selectedBefore = h.selectedID
        let favoritesBefore = h.favoritesJSON
        h.step(1)
        h.selectFilter(.still)
        h.toggleFavorite(lastLive)
        assert(h.selectedID == selectedBefore && h.filter == .all && h.favoritesJSON == favoritesBefore)
        h.applying = false
        h.favoritesJSON = "invalid"
        assert(h.favorites.isEmpty)
        let restored = Harness()
        restored.activeFlagsRaw = 1
        restored.activeIslandModeRaw = 36
        restored.activeLiveID = "blue-flame"
        restored.restoreSelection()
        assert(restored.selectedID == "blue-flame") // Before remote catalog arrives.
        restored.liveThemes = catalog.themes
        restored.synchronizeSelection()
        assert(restored.selected?.id == "blue-flame")
        restored.liveThemes = []
        restored.synchronizeSelection()
        assert(restored.selected != nil) // Built-in art remains usable offline.
        print("PASS: \(allCount) unique styles; \(liveCount) Live; \(stillCount) static; carousel wraparound; category memory; saved/removable favorites; empty/search states; unique active identity; operation lock; cold-start restoration; offline fallback")
    }
}
@main struct SelectionChecks {
    @MainActor static func main() throws { try Harness.verify() }
}
'''
with tempfile.TemporaryDirectory(prefix="eagle-island-selection-") as temporary:
    path = Path(temporary) / "Selection.swift"
    path.write_text((style + model + types + stub + helpers + tests).replace("import UIKit\n", ""))
    binary = Path(temporary) / "verify"
    subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-parse-as-library",
                    str(path), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(repo.parent / "Eagle-Gallery/catalogs/island-gallery-v1.json")], check=True)
