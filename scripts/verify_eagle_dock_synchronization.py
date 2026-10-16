#!/usr/bin/env python3
"""Verify owned synchronization, exact screen wiring and inert effect traces.

Only Foundation Gallery values, the coordinator and generated host/SwiftUI
fixtures compile. No full app, native executor, real preferences or IPA runs.
The inline reference is the previous owned synchronization, not the original
public implementation's earlier multiple visible/category catalog reads.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGallerySynchronization.swift"
SYNC_MARKER = "private func synchronizeRemoteSelection()"
CORE_MARKER = "@MainActor\nenum EagleDockGallerySynchronization"
CORE_HEADER = """static func synchronize(
        catalog: () -> [EagleDockGalleryTheme],
        readSession: () -> EagleDockGallerySession,
        writeSession: (EagleDockGallerySession) -> Void,
        shuffle: ([String]) -> [String],
        lastViewedStaticID: () -> String,
        lastViewedLiveID: () -> String,
        visibleThemes: () -> [EagleDockGalleryTheme],
        rememberViewedTheme: () -> Void
    )"""
INLINE_SYNC = """private func synchronizeRemoteSelection() {
        let update = EagleDockGalleryVisitOrder.pendingUpdate(
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
        if let reorderedSession = session.adoptingOrder(order) {
            session = reorderedSession
        }
        let themes = visibleRemoteThemes
        if let updatedSession = session.reconcilingSelection(in: themes) {
            session = updatedSession
        }
        rememberViewedTheme()
    }"""
SCREEN_SYNC = """private func synchronizeRemoteSelection() {
        EagleDockGallerySynchronization.synchronize(
            catalog: { remoteGallery.themes },
            readSession: { session },
            writeSession: { session = $0 },
            shuffle: { $0.shuffled() },
            lastViewedStaticID: { lastViewedStaticID },
            lastViewedLiveID: { lastViewedLiveID },
            visibleThemes: { visibleRemoteThemes },
            rememberViewedTheme: { rememberViewedTheme() }
        )
    }"""
SOURCES = tuple("lara/EagleCore/DockGallery/" + name + ".swift" for name in (
    "EagleDockGalleryTheme", "EagleDockGalleryMediaFilter",
    "EagleDockGallerySelectionMemory", "EagleDockGallerySelection",
    "EagleDockGallerySession", "EagleDockGalleryVisitOrder",
    "EagleDockGalleryCollection", "EagleDockGallerySynchronization",
))


def replace_counted(source, old, new, label, count=1):
    assert source.count(old) == count, f"Counted synchronization boundary changed: {label}"
    return source.replace(old, new)


def expected_core():
    """Map only the previous inline storage/randomness boundaries to closures."""
    body = replace_counted(INLINE_SYNC, SYNC_MARKER, CORE_HEADER, "owned signature")
    for old, new, count in (
        ("remoteGallery.themes", "catalog()", 2),
        ("orderedIDs: shuffledRemoteIDs", "orderedIDs: readSession().shuffledRemoteIDs", 1),
        ("update.additions.shuffled()", "shuffle(update.additions)", 1),
        ("lastViewedStaticID: lastViewedStaticID,", "lastViewedStaticID: lastViewedStaticID(),", 1),
        ("lastViewedLiveID: lastViewedLiveID,", "lastViewedLiveID: lastViewedLiveID(),", 1),
        ("session.adoptingOrder(order)", "readSession().adoptingOrder(order)", 1),
        ("session = reorderedSession", "writeSession(reorderedSession)", 1),
        ("let themes = visibleRemoteThemes", "let themes = visibleThemes()", 1),
        ("session.reconcilingSelection(in: themes)", "readSession().reconcilingSelection(in: themes)", 1),
        ("session = updatedSession", "writeSession(updatedSession)", 1),
    ):
        body = replace_counted(body, old, new, old, count)
    return "import Foundation\n\n" + CORE_MARKER + " {\n    " + body + "\n}\n"


def verify_core(source):
    code = re.sub(r"//[^\n]*", "", source)
    assert compact(code) == compact(expected_core()), (
        "Synchronization must retain the exact synchronous MainActor closure API, "
        "lazy reads, one shuffle, optional commits and final persistence"
    )


def inline_synchronization(source):
    """Expand one exact screen call only after checking the owned implementation.

    This is a leaf helper: existing public-derived gates can import it without
    importing session, memory or visit-order verification modules in a cycle.
    """
    current = declaration(source, SYNC_MARKER)
    assert compact(current) == compact(SCREEN_SYNC), "Synchronization screen storage/randomness wiring changed"
    repo = Path(__file__).resolve().parents[1]
    verify_core((repo / CORE_PATH).read_text())
    return replace_counted(source, current, INLINE_SYNC, "single synchronization expansion")


def verify_sources(repo):
    repo = Path(repo)
    current = (repo / VIEW_PATH).read_text()
    core = (repo / CORE_PATH).read_text()
    verify_core(core)
    inline_synchronization(current)
    return {"current": current, "core": core}


def verify_public_predecessor(repo):
    # These imports must stay local: the older gates import our leaf expansion.
    from verify_eagle_dock_visit_order import project_view_visit_order, verify_sources as verify_order
    from verify_eagle_dock_selection_memory import project_selection_replacement
    from verify_eagle_dock_session import project_session_reconciliation, verify_sources as verify_session

    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    public_view = declaration(public, "struct DockGalleryView: View")
    previous = project_session_reconciliation(project_selection_replacement(project_view_visit_order(public_view)))
    assert compact(declaration(previous, SYNC_MARKER)) == compact(INLINE_SYNC), (
        "Inline reference no longer matches the counted public-derived ownership projections"
    )
    verify_order(repo)
    verify_session(repo)


def verify_negatives(values):
    cases = [
        ("core", "import Foundation", "import Foundation\nimport SwiftUI"),
        ("core", "@MainActor\nenum", "nonisolated enum"),
        ("core", "catalog: () ->", "catalog: @escaping () ->"),
        ("core", "shuffle(update.additions)", "shuffle(shuffle(update.additions))"),
        ("core", "shuffle(update.additions)", "shuffle(update.retainedIDs)"),
        ("core", "let additions = shuffle(update.additions)", "let last = lastViewedStaticID()\n        let additions = shuffle(update.additions)"),
        ("core", "lastViewedStaticID: lastViewedStaticID(),", "lastViewedStaticID: lastViewedLiveID(),"),
        ("core", "themes: catalog()", "themes: []", 2),
        ("core", "writeSession(reorderedSession)", "writeSession(EagleDockGallerySession())"),
        ("core", "        let themes = visibleThemes()", "        let themes = catalog()"),
        ("core", "readSession().reconcilingSelection(in: themes)", "readSession().reconcilingSelection(in: visibleThemes())"),
        ("core", "writeSession(updatedSession)", "rememberViewedTheme()\n            writeSession(updatedSession)"),
        ("core", "        rememberViewedTheme()\n", ""),
        ("current", "catalog: { remoteGallery.themes }", "catalog: { [] }"),
        ("current", "readSession: { session }", "readSession: { EagleDockGallerySession() }"),
        ("current", "writeSession: { session = $0 }", "writeSession: { _ in }"),
        ("current", "shuffle: { $0.shuffled() }", "shuffle: { $0 }"),
        ("current", "visibleThemes: { visibleRemoteThemes }", "visibleThemes: { remoteGallery.themes }"),
        ("current", "rememberViewedTheme: { rememberViewedTheme() }", "rememberViewedTheme: {}"),
    ]
    for field, old, new, *counts in cases:
        # Other owned actions also use storage callbacks. Mutate only the
        # synchronization method whose wiring this gate is responsible for.
        region = declaration(values[field], SYNC_MARKER) if field == "current" else values[field]
        changed = replace_counted(region, old, new, "negative " + old, counts[0] if counts else 1)
        try:
            if field == "core":
                verify_core(changed)
            else:
                inline_synchronization(changed)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Synchronization mutation escaped rejection: {old}")
    return len(cases)


def host_fixture(current):
    helpers = []
    for marker, replacement in (
        ("private var visibleRemoteThemes: [RemoteDockGalleryTheme]", "func computeVisible() -> [RemoteDockGalleryTheme]"),
        ("private var selectedRemoteTheme: RemoteDockGalleryTheme?", "func computeSelected() -> RemoteDockGalleryTheme?"),
        ("private func rememberViewedTheme()", "func computeRemember()"),
    ):
        helpers.append(replace_counted(declaration(current, marker), marker, replacement, "host read/effect instrumentation"))
    previous = replace_counted(INLINE_SYNC, "update.additions.shuffled()", "shuffle(update.additions)", "reference deterministic shuffle")
    screen = replace_counted(declaration(current, SYNC_MARKER), "$0.shuffled()", "shuffle($0)", "screen deterministic shuffle")
    return "import Foundation\n\nextension SynchronizationStorage {\n" + "\n".join(helpers) + "\n}\n" + "\n".join(
        "final class " + name + ": SynchronizationStorage {\n" + body + "\n"
        "    override func run() { synchronizeRemoteSelection() }\n}\n"
        for name, body in (("PreviousSynchronizationFixture", previous), ("ScreenSynchronizationFixture", screen))
    )


def swiftui_fixture(current):
    from verify_eagle_dock_session import screen_bindings
    bindings = screen_bindings(current, ("shuffledRemoteIDs", "lastViewedStaticID", "lastViewedLiveID"))
    return "import Foundation\nimport SwiftUI\n\nprivate struct SynchronizationBindingFixture: View {\n" + """
    private struct Store { var themes: [EagleDockGalleryTheme] = [] }
    private var remoteGallery = Store()
    private var visibleRemoteThemes: [EagleDockGalleryTheme] { [] }
    private func rememberViewedTheme() {}
""" + "\n".join(bindings) + "\n" + declaration(current, SYNC_MARKER) + "\n" + """
    var body: some View {
        Button("Synchronize") { synchronizeRemoteSelection() }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    verify_public_predecessor(repo)
    negatives = verify_negatives(values)
    print(f"PASS: exact public-derived synchronization ownership and screen closure wiring; {negatives} mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [str(repo / path) for path in SOURCES]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-synchronization-") as directory:
        work = Path(directory)
        fixture = work / "ExactSynchronizationHosts.swift"
        fixture.write_text(host_fixture(values["current"]))
        binary = work / "verify-synchronization"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(fixture),
                        str(repo / "scripts/verify_eagle_dock_synchronization.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
        binding = work / "ExactSynchronizationBindings.swift"
        binding.write_text(swiftui_fixture(values["current"]))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck", "-target", "arm64-apple-ios16.0",
                        "-sdk", sdk, *sources, str(binding)], check=True, timeout=55)
    print("PASS: actual coordinator, prior inline and screen wiring traces; actual State/AppStorage closures typecheck; no app/backend/preferences execution/IPA", flush=True)


if __name__ == "__main__":
    main()
