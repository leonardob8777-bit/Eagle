#!/usr/bin/env python3
"""Check optional session reconciliation and order/read/commit/persistence seams.

Compiles only Foundation Core sources and inert host fixtures. The reference
tail preserves prior owned recovery rules; exact coordinator expansion and public
source gates verify those rules. Full coordination runs in its dedicated suite.
No app, native executor, preferences, UI observers, simulator or IPA is run.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import declaration
from verify_eagle_dock_session import (
    PUBLIC_COMMIT, VIEW_PATH, VIEW_MARKER, MODEL_PATH, CORE_PATHS,
    SYNC_MARKER, RECOVERY_CORE_MARKER, PUBLIC_REPLACEMENT, OLD_RECOVERY,
    ORDER_CORE_MARKER,
    replace_counted, verify_contract, reconciliation_tail, session_aliases,
)


def source_values(repo):
    public = subprocess.check_output(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"],
                                     cwd=repo, text=True, timeout=55)
    values = {"public_view": declaration(public, VIEW_MARKER),
              "current": (repo / VIEW_PATH).read_text(), "model": (repo / MODEL_PATH).read_text()}
    verify_contract(**values)
    return values


def verify_negatives(values):
    cases = [
        ("model", RECOVERY_CORE_MARKER, "return nil", "return self"),
        ("model", RECOVERY_CORE_MARKER, "selectedID: selectedRemoteID", 'selectedID: ""'),
        ("model", RECOVERY_CORE_MARKER, 'updated.readyRemotePreviewID = ""', "updated.readyRemotePreviewID = readyRemotePreviewID"),
        ("model", RECOVERY_CORE_MARKER, "updated.selectedRemoteID = replacementID", "updated.selectedRemoteID = selectedRemoteID"),
        ("model", RECOVERY_CORE_MARKER, 'updated.readyRemotePreviewID = ""\n        updated.selectedRemoteID = replacementID',
         'updated.selectedRemoteID = replacementID\n        updated.readyRemotePreviewID = ""'),
        ("model", RECOVERY_CORE_MARKER, "return updated", "return self"),
        ("model", RECOVERY_CORE_MARKER, "var updated = self", "var updated = self\n        updated.rememberedSelections = .init()"),
        ("model", RECOVERY_CORE_MARKER, "var updated = self", "var updated = self\n        updated.mediaFilter = .still"),
        ("model", RECOVERY_CORE_MARKER, "var updated = self", "var updated = self\n        updated.shuffledRemoteIDs = []"),
        ("model", RECOVERY_CORE_MARKER, "var updated = self", "var updated = self\n        updated.visitStarted = false"),
        ("current", SYNC_MARKER, "readSession: { session }", "readSession: { EagleDockGallerySession() }"),
        ("current", SYNC_MARKER, "visibleThemes: { visibleRemoteThemes }", "visibleThemes: { remoteGallery.themes }"),
        ("current", SYNC_MARKER, "shuffle: { $0.shuffled() }", "shuffle: { $0 }"),
        ("current", SYNC_MARKER, "rememberViewedTheme: { rememberViewedTheme() }", "rememberViewedTheme: {}"),
        ("current", SYNC_MARKER, "writeSession: { session = $0 }", "writeSession: { _ in }"),
        ("current", SYNC_MARKER, "lastViewedStaticID: { lastViewedStaticID }", "lastViewedStaticID: { lastViewedLiveID }"),
        ("current", SYNC_MARKER, "catalog: { remoteGallery.themes }", "catalog: { [] }"),
        ("model", ORDER_CORE_MARKER, "return nil", "return self"),
        ("model", ORDER_CORE_MARKER, "shuffledRemoteIDs != order", "shuffledRemoteIDs == order"),
        ("model", ORDER_CORE_MARKER, "updated.shuffledRemoteIDs = order", "updated.shuffledRemoteIDs = order.sorted()"),
        ("model", ORDER_CORE_MARKER, "var updated = self", "var updated = Self()"),
    ]
    for field, marker, old, new in cases:
        altered = values.copy()
        region = declaration(altered[field], marker)
        changed = replace_counted(region, old, new, "negative reconciliation region")
        altered[field] = replace_counted(altered[field], region, changed, "negative reconciliation declaration")
        try:
            verify_contract(**altered)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Reconciliation mutation escaped rejection: {field}/{old}")
    return len(cases)


def screen_fixture(values, name, owned):
    if owned:
        tail = reconciliation_tail(values["current"])
    else:
        tail = replace_counted(reconciliation_tail(values["public_view"]), PUBLIC_REPLACEMENT,
                               OLD_RECOVERY, "previous owned replacement rule/single-list read")
    getter = declaration(values["current"], "private var visibleRemoteThemes: [RemoteDockGalleryTheme]")
    getter = replace_counted(getter, "private var visibleRemoteThemes: [RemoteDockGalleryTheme]",
                             "func computeVisible() -> [RemoteDockGalleryTheme]", "instrument getter access only")
    return "final class " + name + " {\n" + """
    typealias MediaFilter = EagleDockGalleryMediaFilter
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    struct Store { var themes: [EagleDockGalleryTheme] = [] }
    var remoteGallery = Store()
    var favoriteIDs: Set<String> = []
    var writes = 0
    var events: [String] = []
    var visibleStates: [ReconciliationSnapshot] = []
    var rememberStates: [ReconciliationSnapshot] = []
    var session = EagleDockGallerySession() { didSet { writes += 1 } }
    var visibleRemoteThemes: [EagleDockGalleryTheme] {
        events.append("visible")
        visibleStates.append(ReconciliationSnapshot(session))
        return computeVisible()
    }
    func rememberViewedTheme() {
        events.append("remember")
        rememberStates.append(ReconciliationSnapshot(session))
    }
""" + "\n".join(session_aliases(values["current"], host_class=True)) + "\n" + getter + "\n" + "func synchronizeFixture(order: [String]) {\n" + tail + "\n}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = source_values(repo)
    negatives = verify_negatives(values)
    print(f"PASS: public-derived optional reconciliation and exact order/read/commit/persistence tail; {negatives} negative mutations rejected", flush=True)
    if args.source_only:
        return
    sources = [str(repo / path) for path in (*CORE_PATHS, "lara/EagleCore/DockGallery/EagleDockGalleryCollection.swift")]
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-reconciliation-") as directory:
        work = Path(directory)
        fixture = work / "ExactReconciliationFixtures.swift"
        fixture.write_text("import Foundation\n" + screen_fixture(values, "PreviousReconciliationFixture", False) +
                           "\n" + screen_fixture(values, "OwnedReconciliationFixture", True))
        binary = work / "verify-reconciliation"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(fixture),
                        str(repo / "scripts/verify_eagle_dock_reconciliation.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: temporary benign host fixtures cleaned; no full app/native backend/real State observers/preferences/IPA", flush=True)


if __name__ == "__main__":
    main()
