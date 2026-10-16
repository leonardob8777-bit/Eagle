#!/usr/bin/env python3
"""Check category memory and missing-selection recovery with inert fixtures."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_interactions import inline_interactions
from verify_eagle_dock_session import (
    PUBLIC_REPLACEMENT, MODEL_PATH as SESSION_PATH,
    add_session_sources, project_session_begin, project_session_category,
    project_session_reconciliation, reconciliation_tail, reconciliation_statement,
    screen_bindings, verify_contract as verify_session_contract,
)


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MEMORY_PATH = "lara/EagleCore/DockGallery/EagleDockGallerySelectionMemory.swift"
CORE_PATHS = (
    "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift",
    MEMORY_PATH,
)
VIEW_MARKER = "struct DockGalleryView: View"
FILTER_MARKER = "private func selectMediaFilter(_ filter: MediaFilter)"
BEGIN_MARKER = "private func beginGalleryVisit()"
SYNC_MARKER = "private func synchronizeRemoteSelection()"
PUBLIC_BINDING = "@State private var rememberedSelections: [MediaFilter: String] = [:]"
OWNED_BINDING = "@State private var rememberedSelections: EagleDockGallerySelectionMemory = .init()"
OWNED_MARKER = "nonisolated struct EagleDockGallerySelectionMemory: Sendable"
REPLACEMENT = """if let replacementID = EagleDockGallerySelection.replacementID(in: visibleRemoteThemes, selectedID: selectedRemoteID) {
            readyRemotePreviewID = ""
            selectedRemoteID = replacementID
        }"""


def replace_counted(source, old, new, label):
    assert source.count(old) == 1, f"Counted selection-memory boundary changed: {label}"
    return source.replace(old, new, 1)


def expected_memory(public_view):
    switch = declaration(public_view, FILTER_MARKER)
    assert public_view.count(PUBLIC_BINDING) == 1, "Public per-visit memory binding changed"
    state = PUBLIC_BINDING.replace("@State ", "").replace("rememberedSelections", "ids").replace("MediaFilter", "EagleDockGalleryMediaFilter")
    remember = "rememberedSelections[mediaFilter] = selectedRemoteTheme?.id"
    restore = 'rememberedSelections[filter] ?? ""'
    assert switch.count(remember) == switch.count(restore) == 1, "Public memory assignment/lookup changed"
    remember = remember.replace("rememberedSelections", "ids").replace("mediaFilter", "filter").replace("selectedRemoteTheme?.id", "id")
    restore = restore.removesuffix(' ?? ""').replace("rememberedSelections", "ids")
    return OWNED_MARKER + " {\n" + state + "\n" + """
    mutating func remember(id: String?, for filter: EagleDockGalleryMediaFilter) {
""" + remember + "\n}\n" + """
    func restoredID(for filter: EagleDockGalleryMediaFilter) -> String? {
""" + restore + "\n}\n}"


def project_selection_replacement(source):
    """Exact recovery branch only; used by the complete visit-order contract."""
    sync = declaration(source, SYNC_MARKER)
    # The condition contains a closure; the generic declaration reader stops
    # at that closure. Anchor the entire known public branch instead.
    projected = replace_counted(sync, PUBLIC_REPLACEMENT, REPLACEMENT, "complete replacement decision delegation")
    return replace_counted(source, sync, projected, "synchronization recovery branch")


def project_view_selection_memory(source):
    result = replace_counted(source, PUBLIC_BINDING, OWNED_BINDING, "value-owned State binding")
    switch = declaration(result, FILTER_MARKER)
    projected = replace_counted(switch, "rememberedSelections[mediaFilter] = selectedRemoteTheme?.id",
                                "rememberedSelections.remember(id: selectedRemoteTheme?.id, for: mediaFilter)", "record old category")
    projected = replace_counted(projected, 'rememberedSelections[filter] ?? ""',
                                'rememberedSelections.restoredID(for: filter) ?? ""', "restore new category")
    result = replace_counted(result, switch, projected, "complete filter switch")
    begin = declaration(result, BEGIN_MARKER)
    projected = replace_counted(begin, "rememberedSelections = [:]", "rememberedSelections = .init()", "new-visit reset")
    result = replace_counted(result, begin, projected, "complete visit start")
    return project_selection_replacement(result)


def verify_sources(repo):
    repo = Path(repo)
    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    public_view = declaration(public, VIEW_MARKER)
    current = (repo / VIEW_PATH).read_text()
    code = re.sub(r"//[^\n]*", "", (repo / MEMORY_PATH).read_text())
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_memory(public_view)), "Memory ownership changed public dictionary assignment/lookup semantics"
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], "Memory gained imports/shared state/external code"
    expected = project_session_reconciliation(project_session_category(project_session_begin(project_view_selection_memory(public_view))))
    assert OWNED_BINDING not in current and PUBLIC_BINDING not in current, "Screen still duplicates category memory State"
    screen_bindings(current, ("rememberedSelections",))
    expanded = inline_interactions(current)
    for marker in (FILTER_MARKER, BEGIN_MARKER):
        assert compact(declaration(expanded, marker)) == compact(declaration(expected, marker)), (
            f"Category/recovery wiring changed beyond the exact delegation: {marker}"
        )
    assert compact(reconciliation_tail(current)) == compact(reconciliation_tail(expected)), "Recovery tail changed order/read/write/persistence sequence"
    verify_session_contract(public_view, current, (repo / SESSION_PATH).read_text())
    return current


def swiftui_projection(current):
    bindings = screen_bindings(current, ("isApplying", "visitStarted", "mediaFilter", "shuffledRemoteIDs", "selectedRemoteID", "readyRemotePreviewID", "rememberedSelections"))
    return "import Foundation\nimport SwiftUI\nimport UIKit\n\nprivate struct SelectionMemoryBindingFixture: View {\n" + """
    private typealias MediaFilter = EagleDockGalleryMediaFilter
    private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    private struct Store { var downloadingID: String? }
    private var remoteGallery = Store()
    private var visibleRemoteThemes: [EagleDockGalleryTheme] { [] }
    private func synchronizeRemoteSelection() {}
""" + "\n".join(bindings) + "\n" + "\n".join(
        declaration(current, marker) for marker in (
            "private var selectedRemoteTheme: RemoteDockGalleryTheme?", FILTER_MARKER, BEGIN_MARKER,
        )
    ) + "\nprivate func reconcileFixture() {\n" + reconciliation_statement(current) + "\n}\n" + """
    var body: some View {
        Button("Live") { selectMediaFilter(.live) }
        Button("New visit") { beginGalleryVisit() }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    current = verify_sources(repo)
    print("PASS: public-derived memory ownership, category switch/visit reset and explicit replacement wiring", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [str(repo / path) for path in add_session_sources(CORE_PATHS)]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-selection-memory-") as directory:
        work = Path(directory)
        binary = work / "verify-selection-memory"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", *sources,
             str(repo / "scripts/verify_eagle_dock_selection_memory.swift"), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactSelectionMemorySwiftUIBindings.swift"
        fixture.write_text(swiftui_projection(current))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, *sources, str(fixture)],
            check=True, timeout=55,
        )
    print("PASS: actual category/visit/State/replacement declarations typecheck in inert iOS fixture; temporary outputs cleaned; no app/backend/IPA", flush=True)


if __name__ == "__main__":
    main()
