#!/usr/bin/env python3
"""Exercise the actual Dock Gallery selection helpers with its owned Core types.

Only ten Foundation Core sources and extracted, benign selection helpers are
compiled. The app view, UIKit, native applying/access engine and IPA are excluded.
"""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_session import session_aliases

repo = Path(__file__).resolve().parents[1]
source = (repo / "lara/views/new/DockGalleryView.swift").read_text()
core_sources = [
    repo / "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGalleryFavorites.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGalleryCollection.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGalleryVisitOrder.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGallerySelectionMemory.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGallerySession.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGallerySynchronization.swift",
    repo / "lara/EagleCore/DockGallery/EagleDockGalleryInteractions.swift",
]
assert all(path.is_file() for path in core_sources), "Owned theme/filter/favorites/collection/selection/visit-order/memory/session sources are required"
theme_alias = "private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme"
filter_alias = "private typealias MediaFilter = EagleDockGalleryMediaFilter"
assert source.count(theme_alias) == 1, "The screen must use the actual owned theme alias"
assert source.count(filter_alias) == 1, "The screen must use the actual owned filter alias"
assert "struct DockGalleryView: View {\n    " + filter_alias in source, "Filter alias location changed"


def declaration(marker):
    assert source.count(marker) == 1, f"Expected one benign selection declaration: {marker}"
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        assert end < len(source), f"Unbalanced selection declaration: {marker}"
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


# Host-class bridges expose fields to assertions; widen only this alias's
# visibility in the fixture. The actual screen declaration is checked above.
helpers = filter_alias.replace("private ", "", 1) + "\n" + "\n".join(session_aliases(source, host_class=True)) + "\n" + "\n".join(declaration(marker) for marker in [
    "private var selectedRemoteTheme:",
    "private var visibleRemoteThemes:", "private var favoriteIDs:",
    "private func toggleFavorite(_ theme:", "private func selectMediaFilter(_ filter:",
    "private func beginGalleryVisit()", "private func synchronizeRemoteSelection()",
    "private func rememberViewedTheme()", "private func stepRemote(_ step:",
])
assert all(value not in helpers for value in (
    "laramgr", "RemoteCall", "DockGalleryExecutor", "DarkSword", "URLSession", "FileManager",
)), "Selection projection gained an out-of-scope dependency"
harness = r'''
import Foundation
enum LaraL10n { static func text(en: String, es: String) -> String { en } }
''' + theme_alias + r'''
nonisolated extension EagleDockGalleryTheme {
    init(id: String, frameCount: Int) {
        let address = URL(string: "https://fixture.invalid/preview.png")!
        self.init(
            id: id, version: 1, title: id, titleES: id, subtitle: "", subtitleES: "",
            accent: "#DB40E0", previewURL: address, animatedPreviewURL: nil,
            packageURL: address, sha256: "", byteCount: 1, frameCount: frameCount,
            fps: frameCount > 1 ? 6 : 1, width: 1146, height: 318
        )
    }
}
private struct Store { var themes: [RemoteDockGalleryTheme] = []; var downloadingID: String? }
struct UISelectionFeedbackGenerator { func selectionChanged() {} }
struct UIImpactFeedbackGenerator {
    enum Style { case soft }
    init(style: Style) {}
    func impactOccurred() {}
}
private final class Harness {
    var remoteGallery = Store()
    private var session = EagleDockGallerySession()
    var activeRemoteID = ""
    var isApplying = false
    var favoriteIDsJSON = "[]"
    var lastViewedStaticID = ""
    var lastViewedLiveID = ""
''' + helpers
harness += r'''
static func verify() {
    assert(MediaFilter.favorites.title == "Saves")
    assert(MediaFilter.favorites.rawValue == "Favorites") // Preserve stored identities.
    let h = Harness()
    let s1 = RemoteDockGalleryTheme(id: "s1", frameCount: 1)
    let s2 = RemoteDockGalleryTheme(id: "s2", frameCount: 1)
    let l1 = RemoteDockGalleryTheme(id: "l1", frameCount: 17)
    let l2 = RemoteDockGalleryTheme(id: "l2", frameCount: 17)
    h.remoteGallery.themes = [s1, l1, s2, l2]
    h.activeRemoteID = "l2"
    h.lastViewedStaticID = "s1"
    h.lastViewedLiveID = "l2"
    h.beginGalleryVisit()
    assert(h.mediaFilter == .still && h.selectedRemoteID == "s2")
    assert(Set(h.visibleRemoteThemes.map(\.id)) == ["s1", "s2"])
    let order = h.shuffledRemoteIDs
    h.synchronizeRemoteSelection()
    assert(h.shuffledRemoteIDs == order)
    h.readyRemotePreviewID = "s2"
    h.stepRemote(-1)
    assert(h.selectedRemoteID == "s1" && h.readyRemotePreviewID.isEmpty)
    h.stepRemote(1)
    assert(h.selectedRemoteID == "s2")
    h.selectMediaFilter(.live)
    assert(h.selectedRemoteID == "l1")
    h.stepRemote(1)
    assert(h.selectedRemoteID == "l2")
    h.selectMediaFilter(.still)
    assert(h.selectedRemoteID == "s2")
    h.selectMediaFilter(.live)
    assert(h.selectedRemoteID == "l2")
    h.selectMediaFilter(.still)
    h.toggleFavorite(s2)
    h.toggleFavorite(l1)
    assert(h.favoriteIDs == ["s2", "l1"])
    assert(h.selectedRemoteID == "s2" && h.shuffledRemoteIDs == order)
    h.selectMediaFilter(.favorites)
    assert(Set(h.visibleRemoteThemes.map(\.id)) == ["s2", "l1"])
    let restored = Harness()
    restored.favoriteIDsJSON = h.favoriteIDsJSON
    restored.remoteGallery.themes = h.remoteGallery.themes
    restored.beginGalleryVisit()
    restored.selectMediaFilter(.favorites)
    assert(Set(restored.visibleRemoteThemes.map(\.id)) == ["s2", "l1"])
    h.toggleFavorite(h.selectedRemoteTheme!)
    assert(h.visibleRemoteThemes.count == 1)
    h.readyRemotePreviewID = h.selectedRemoteID
    h.stepRemote(1)
    assert(h.readyRemotePreviewID == h.selectedRemoteID)
    h.toggleFavorite(h.selectedRemoteTheme!)
    assert(h.selectedRemoteID.isEmpty && h.selectedRemoteTheme == nil)
    h.stepRemote(1)
    assert(h.selectedRemoteTheme == nil)
    h.selectMediaFilter(.still)
    assert(h.selectedRemoteID == "s2")
    h.isApplying = true
    h.stepRemote(1)
    assert(h.selectedRemoteID == "s2")
    h.selectMediaFilter(.live)
    assert(h.mediaFilter == .still)
    h.isApplying = false
    h.remoteGallery.downloadingID = "s2"
    h.stepRemote(1)
    assert(h.selectedRemoteID == "s2")
    h.remoteGallery.downloadingID = nil
    h.remoteGallery.themes = [s1, l1]
    h.synchronizeRemoteSelection()
    assert(h.selectedRemoteID == "s1")
    h.remoteGallery.themes = []
    h.synchronizeRemoteSelection()
    h.stepRemote(1)
    assert(h.selectedRemoteID.isEmpty && h.selectedRemoteTheme == nil)
    h.remoteGallery.themes = [s1]
    h.synchronizeRemoteSelection()
    assert(h.selectedRemoteID == "s1")
    h.selectMediaFilter(.live)
    assert(h.selectedRemoteID.isEmpty && h.selectedRemoteTheme == nil)
    h.toggleFavorite(s1)
    h.remoteGallery.themes = []
    h.synchronizeRemoteSelection()
    assert(h.favoriteIDs == ["s1"])
    h.remoteGallery.themes = [s1]
    h.synchronizeRemoteSelection()
    h.selectMediaFilter(.favorites)
    assert(h.selectedRemoteID == "s1")

    let large = Harness()
    large.remoteGallery.themes = (1...232).map { RemoteDockGalleryTheme(id: "s\($0)", frameCount: 1) }
        + (1...196).map { RemoteDockGalleryTheme(id: "l\($0)", frameCount: 17) }
    var visits = Set<[String]>()
    for _ in 0..<100 {
        let oldStatic = large.lastViewedStaticID
        let oldLive = large.lastViewedLiveID
        large.beginGalleryVisit()
        assert(large.visibleRemoteThemes.count == 232)
        assert(large.selectedRemoteID != oldStatic)
        assert(Set(large.shuffledRemoteIDs).count == 428)
        let sessionOrder = large.shuffledRemoteIDs
        visits.insert(sessionOrder)
        large.selectMediaFilter(.live)
        assert(large.visibleRemoteThemes.count == 196 && large.selectedRemoteID != oldLive)
        var seen = Set<String>()
        for _ in 0..<196 {
            seen.insert(large.selectedRemoteID)
            large.stepRemote(1)
        }
        assert(seen.count == 196)
        large.synchronizeRemoteSelection()
        assert(large.shuffledRemoteIDs == sessionOrder)
    }
    assert(visits.count == 100)
    let selected = large.selectedRemoteID
    let before = large.shuffledRemoteIDs
    large.remoteGallery.themes.append(RemoteDockGalleryTheme(id: "new", frameCount: 1))
    large.synchronizeRemoteSelection()
    assert(large.selectedRemoteID == selected)
    assert(Array(large.shuffledRemoteIDs.prefix(before.count)) == before)
    restored.favoriteIDsJSON = "broken JSON"
    assert(restored.favoriteIDs.isEmpty)
    print("PASS: 100 shuffled visits, no repeated opening theme, 428 unique styles, stable session order, category wraparound, saved favorites, removal and empty favorites, stale preview reset, operation lock, catalog updates")
}

static func verifyFavoritePersistence() {
    for broken in ["broken JSON", "[\"kept\",null]", "{\"ids\":[\"old\"]}", "42"] {
        let h = Harness()
        h.favoriteIDsJSON = broken
        assert(h.favoriteIDs.isEmpty)
        assert(h.favoriteIDs.isEmpty)
        assert(h.favoriteIDsJSON == broken) // A getter does not repair persistence.
        h.toggleFavorite(RemoteDockGalleryTheme(id: "new", frameCount: 1))
        assert(h.favoriteIDs == ["new"])
        let data = h.favoriteIDsJSON.data(using: .utf8)!
        assert(try! JSONDecoder().decode([String].self, from: data) == ["new"])
        let restored = Harness()
        restored.favoriteIDsJSON = h.favoriteIDsJSON
        assert(restored.favoriteIDs == ["new"])
    }

    let identifiers = ["", " ", " same ", "same", "SAME", "é", "e\u{301}", "🦅",
                       "quote\"id", "line\nbreak", "tab\tid", "slash/id", "back\\slash", "nul\u{0}id"]
    for id in identifiers {
        let h = Harness()
        let theme = RemoteDockGalleryTheme(id: id, frameCount: 1)
        h.toggleFavorite(theme)
        assert(h.favoriteIDs == [id])
        let data = h.favoriteIDsJSON.data(using: .utf8)!
        assert(try! JSONDecoder().decode([String].self, from: data) == [id])
        let restored = Harness()
        restored.favoriteIDsJSON = h.favoriteIDsJSON
        assert(restored.favoriteIDs == [id])
        for _ in 0..<6 {
            restored.toggleFavorite(theme)
            assert(restored.favoriteIDs.isEmpty && restored.favoriteIDsJSON == "[]")
            restored.toggleFavorite(theme)
            assert(restored.favoriteIDs == [id])
        }
    }

    let h = Harness()
    var expected = Set<String>()
    let themes = identifiers.map { RemoteDockGalleryTheme(id: $0, frameCount: 1) }
    for theme in themes {
        if !expected.insert(theme.id).inserted { expected.remove(theme.id) }
        h.toggleFavorite(theme)
        assert(h.favoriteIDs == expected)
    }
    let restored = Harness()
    restored.favoriteIDsJSON = h.favoriteIDsJSON
    assert(restored.favoriteIDs == expected)
    for _ in 0..<4 {
        for theme in themes {
            if !expected.insert(theme.id).inserted { expected.remove(theme.id) }
            restored.toggleFavorite(theme)
            assert(restored.favoriteIDs == expected)
            let data = restored.favoriteIDsJSON.data(using: .utf8)!
            assert(try! JSONDecoder().decode([String].self, from: data) == expected.sorted())
            let reloaded = Harness()
            reloaded.favoriteIDsJSON = restored.favoriteIDsJSON
            assert(reloaded.favoriteIDs == expected)
        }
    }
    print("PASS: invalid JSON getters preserve stored strings, explicit toggle writes valid JSON, 14 empty/space/case/Unicode/escaped identities, repeated toggles, sorted encoding and fresh-harness persistence round trips; fixture String storage only")
}

static func verifySelectionRecovery() {
    let empty = Harness()
    empty.selectedRemoteID = ""
    empty.readyRemotePreviewID = "filled-empty-preview"
    empty.synchronizeRemoteSelection()
    assert(empty.selectedRemoteID.isEmpty && empty.readyRemotePreviewID.isEmpty)

    let blank = Harness()
    blank.remoteGallery.themes = [RemoteDockGalleryTheme(id: "", frameCount: 1)]
    blank.shuffledRemoteIDs = [""]
    blank.selectedRemoteID = ""
    blank.readyRemotePreviewID = "valid-blank-preview"
    blank.synchronizeRemoteSelection()
    assert(blank.selectedRemoteTheme?.id == "")
    assert(blank.selectedRemoteID.isEmpty && blank.readyRemotePreviewID == "valid-blank-preview")

    let h = Harness()
    let s1 = RemoteDockGalleryTheme(id: "memory-s1", frameCount: 1)
    let s2 = RemoteDockGalleryTheme(id: "memory-s2", frameCount: 1)
    let l1 = RemoteDockGalleryTheme(id: "memory-l1", frameCount: 17)
    let l2 = RemoteDockGalleryTheme(id: "memory-l2", frameCount: 17)
    h.remoteGallery.themes = [s1, s2, l1, l2]
    h.shuffledRemoteIDs = [s1.id, s2.id, l1.id, l2.id]
    h.selectedRemoteID = s2.id
    h.toggleFavorite(s1)
    h.toggleFavorite(l1)
    h.selectMediaFilter(.live)
    assert(h.selectedRemoteID == l1.id)
    h.stepRemote(1)
    assert(h.selectedRemoteID == l2.id)
    h.selectMediaFilter(.favorites)
    assert(h.selectedRemoteID == s1.id)
    h.stepRemote(1)
    assert(h.selectedRemoteID == l1.id)
    h.selectMediaFilter(.still)
    assert(h.selectedRemoteID == s2.id)
    h.selectMediaFilter(.live)
    assert(h.selectedRemoteID == l2.id)
    h.selectMediaFilter(.favorites)
    assert(h.selectedRemoteID == l1.id)

    h.selectMediaFilter(.still)
    h.toggleFavorite(l1)
    assert(h.favoriteIDs == [s1.id])
    assert(h.rememberedSelections.restoredID(for: .favorites) == l1.id)
    h.readyRemotePreviewID = "removed-favorite-preview"
    h.selectMediaFilter(.favorites)
    assert(h.selectedRemoteID == s1.id && h.readyRemotePreviewID.isEmpty)
    // Replay the still-recorded, now-missing ID without the category-change
    // reset, so synchronization itself must clear a populated preview.
    h.selectedRemoteID = h.rememberedSelections.restoredID(for: .favorites) ?? ""
    h.readyRemotePreviewID = "replayed-removed-favorite-preview"
    h.synchronizeRemoteSelection()
    assert(h.selectedRemoteID == s1.id && h.readyRemotePreviewID.isEmpty)

    print("PASS: selection recovery clears an empty-catalog preview even for an unchanged empty ID, retains a valid empty-ID preview, restores Static/Live/Saves selections and recovers a removed remembered favorite through actual screen helpers; inert fixture storage only")
}
}
Harness.verify()
Harness.verifyFavoritePersistence()
Harness.verifySelectionRecovery()
'''
with tempfile.TemporaryDirectory(prefix="eagle-filter-test-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(harness)
    binary = Path(temporary) / "verify-dock-gallery-filters"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
        "-strict-concurrency=complete", "-warnings-as-errors",
        *map(str, core_sources), str(path), "-o", str(binary),
    ], check=True, timeout=55)
    subprocess.run([str(binary)], check=True, timeout=55)
print("PASS: unchanged selection scenarios use the actual owned Foundation theme/filter/favorites/collection/selection/visit-order/memory/session/synchronization "
      "and screen aliases; temporary host fixtures cleaned; no UI/app/native engine/IPA")
