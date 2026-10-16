#!/usr/bin/env python3
"""Verify the public order boundary, lazy history reads and catalog refreshes.

Builds Foundation Core sources and a tiny iOS binding fixture only.
The original app, native executor, preferences and random UI runtime are excluded.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_selection_memory import project_selection_replacement
from verify_eagle_dock_session import add_session_sources, project_session_reconciliation, screen_bindings
from verify_eagle_dock_synchronization import inline_synchronization


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryVisitOrder.swift"
CORE_PATHS = (
    "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift",
    MODEL_PATH,
)
VIEW_MARKER = "struct DockGalleryView: View"
SYNC_MARKER = "private func synchronizeRemoteSelection()"
OWNED_MARKER = "nonisolated enum EagleDockGalleryVisitOrder"
LOOP_MARKER = "for (filter, lastID)"
PENDING_HEADER = """static func pendingUpdate(
        themes: [EagleDockGalleryTheme],
        orderedIDs: [String]
    ) -> PendingUpdate"""
AVOIDING_HEADER = """static func avoidingLastViewed(
        order initialOrder: [String],
        lastViewedStaticID: String,
        lastViewedLiveID: String,
        themes: [EagleDockGalleryTheme]
    ) -> [String]"""
RESOLVED_ORDER = """func resolvedOrder(
            shuffledAdditions: [String],
            lastViewedStaticID: @autoclosure () -> String,
            lastViewedLiveID: @autoclosure () -> String,
            themes: @autoclosure () -> [EagleDockGalleryTheme]
        ) -> [String] {
            let order = retainedIDs + shuffledAdditions
            guard retainedIDs.isEmpty else { return order }
            return EagleDockGalleryVisitOrder.avoidingLastViewed(
                order: order,
                lastViewedStaticID: lastViewedStaticID(),
                lastViewedLiveID: lastViewedLiveID(),
                themes: themes()
            )
        }"""
NEW_RULES = """        let update = EagleDockGalleryVisitOrder.pendingUpdate(
            themes: remoteGallery.themes,
            orderedIDs: shuffledRemoteIDs
        )
        let additions = update.additions.shuffled()
        let order = update.resolvedOrder(
            shuffledAdditions: additions,
            lastViewedStaticID: lastViewedStaticID,
            lastViewedLiveID: lastViewedLiveID,
            themes: remoteGallery.themes
        )
"""


def replace_counted(source, old, new, label):
    assert source.count(old) == 1, f"Counted visit-order boundary changed: {label}"
    return source.replace(old, new, 1)


def public_parts(source):
    sync = declaration(source, SYNC_MARKER)
    start = sync.index("        let catalogIDs = ")
    setup_end = sync.index("        var order = retainedIDs + additions")
    rules_end = sync.index("        if shuffledRemoteIDs != order")
    return sync, sync[start:setup_end], sync[start:rules_end]


def expected_metadata(public_view):
    sync, setup, _ = public_parts(public_view)
    setup = replace_counted(setup, "remoteGallery.themes", "themes", "catalog value input")
    setup = replace_counted(setup, "shuffledRemoteIDs", "orderedIDs", "existing order value input")
    setup = replace_counted(setup, ".shuffled()", "", "randomization stays in screen")
    loop = declaration(sync, LOOP_MARKER)
    loop = replace_counted(loop, "MediaFilter.still", "EagleDockGalleryMediaFilter.still", "owned category type")
    loop = replace_counted(loop, "remoteGallery.themes", "themes", "single category catalog snapshot")
    return OWNED_MARKER + " {\n" + """
    struct PendingUpdate: Sendable {
        let retainedIDs: [String]
        let additions: [String]
""" + RESOLVED_ORDER + "\n}\n" + PENDING_HEADER + " {\n" + setup + """
        return PendingUpdate(retainedIDs: retainedIDs, additions: additions)
    }
""" + AVOIDING_HEADER + " {\nvar order = initialOrder\n" + loop + "\nreturn order\n}\n}"


def project_view_visit_order(source):
    """One exact order-prefix replacement, leaving all following effects intact."""
    sync, _, rules = public_parts(source)
    projected = replace_counted(sync, rules, NEW_RULES, "order planning and category delegation")
    return replace_counted(source, sync, projected, "complete synchronization method")


def verify_sources(repo):
    repo = Path(repo)
    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    public_view = declaration(public, VIEW_MARKER)
    current = (repo / VIEW_PATH).read_text()
    code = re.sub(r"//[^\n]*", "", (repo / MODEL_PATH).read_text())
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_metadata(public_view)), (
        "Visit order differs from public retention, additions or sequential category swaps"
    )
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], (
        "Visit order gained imports or external state"
    )
    expected_view = project_session_reconciliation(project_selection_replacement(project_view_visit_order(public_view)))
    assert compact(declaration(inline_synchronization(current), SYNC_MARKER)) == compact(declaration(expected_view, SYNC_MARKER)), (
        "Visit order caller changed randomization, branch, value-read order or selection/preview/remember effects"
    )
    return current


def swiftui_projection(current):
    bindings = screen_bindings(current, ("shuffledRemoteIDs", "selectedRemoteID", "readyRemotePreviewID", "lastViewedStaticID", "lastViewedLiveID"))
    return "import Foundation\nimport SwiftUI\n\nprivate struct VisitOrderBindingFixture: View {\n" + """
    private struct Store { var themes: [EagleDockGalleryTheme] = [] }
    private var remoteGallery = Store()
    private var visibleRemoteThemes: [EagleDockGalleryTheme] { [] }
    private func rememberViewedTheme() {}
""" + "\n".join(bindings) + "\n" + declaration(current, SYNC_MARKER) + "\n" + """
    var body: some View {
        Button("Refresh order") { synchronizeRemoteSelection() }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    current = verify_sources(repo)
    print("PASS: public-derived visit-order implementation and complete synchronization caller", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [str(repo / path) for path in add_session_sources(CORE_PATHS)]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-visit-order-") as directory:
        work = Path(directory)
        binary = work / "verify-visit-order"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", *sources,
             str(repo / "scripts/verify_eagle_dock_visit_order.swift"), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactVisitOrderSwiftUIBindings.swift"
        fixture.write_text(swiftui_projection(current))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, *sources, str(fixture)],
            check=True, timeout=55,
        )
    print("PASS: actual synchronization/State/AppStorage bindings typecheck in inert iOS fixture; temporary outputs cleaned; no app/backend/IPA", flush=True)


if __name__ == "__main__":
    main()
