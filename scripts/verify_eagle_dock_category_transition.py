#!/usr/bin/env python3
"""Compare the owned category transition to the public helper with inert spies.

Only benign Foundation sources, extracted category helpers and small
host/iOS fixtures compile. No original app, native backend, simulator or IPA.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import declaration
from verify_eagle_dock_session import (
    PUBLIC_COMMIT, VIEW_PATH, VIEW_MARKER, MODEL_PATH, CORE_PATHS,
    CATEGORY_MARKER, CATEGORY_CORE_MARKER, CATEGORY_GUARD,
    replace_counted, verify_contract, session_aliases, screen_bindings,
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
        ("model", CATEGORY_CORE_MARKER, "for: mediaFilter", "for: filter"),
        ("model", CATEGORY_CORE_MARKER, "id: selectedThemeID", 'id: selectedThemeID ?? ""'),
        ("model", CATEGORY_CORE_MARKER, 'readyRemotePreviewID = ""', 'readyRemotePreviewID = selectedRemoteID'),
        ("model", CATEGORY_CORE_MARKER, 'readyRemotePreviewID = ""\n        mediaFilter = filter', 'mediaFilter = filter\n        readyRemotePreviewID = ""'),
        ("model", CATEGORY_CORE_MARKER, "restoredID(for: filter)", "restoredID(for: .still)"),
        ("model", CATEGORY_CORE_MARKER, '?? ""', "?? selectedRemoteID"),
        ("model", CATEGORY_CORE_MARKER, "mediaFilter = filter", "mediaFilter = filter\n        shuffledRemoteIDs = []"),
        ("model", CATEGORY_CORE_MARKER, "mediaFilter = filter", "mediaFilter = filter\n        visitStarted = false"),
        ("current", CATEGORY_MARKER, "readSession: { session }", "readSession: { EagleDockGallerySession() }"),
        ("current", CATEGORY_MARKER, "isApplying: { isApplying }", "isApplying: { false }"),
        ("current", CATEGORY_MARKER, "downloadingID: { remoteGallery.downloadingID }", "downloadingID: { nil }"),
        ("current", CATEGORY_MARKER, "writeSession: { session = $0 }", "writeSession: { _ in }"),
        ("current", CATEGORY_MARKER, "selectedThemeID: { selectedRemoteTheme?.id }", "selectedThemeID: { selectedRemoteID }"),
        ("current", CATEGORY_MARKER, "            filter,", "            .still,"),
        ("current", CATEGORY_MARKER, "selectedThemeID: { selectedRemoteTheme?.id }", "selectedThemeID: { nil }"),
        ("current", CATEGORY_MARKER, "synchronize: { synchronizeRemoteSelection() }", "synchronize: {}"),
        ("current", CATEGORY_MARKER, "synchronize: { synchronizeRemoteSelection() }", "synchronize: { UISelectionFeedbackGenerator().selectionChanged() }"),
        ("current", CATEGORY_MARKER, "feedback: { UISelectionFeedbackGenerator().selectionChanged() }", "feedback: {}"),
    ]
    for field, marker, old, new in cases:
        altered = values.copy()
        region = declaration(altered[field], marker)
        mutation = replace_counted(region, old, new, "negative category region")
        altered[field] = replace_counted(altered[field], region, mutation, "negative category declaration")
        try:
            verify_contract(**altered)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Category mutation escaped rejection: {field}/{old}")
    return len(cases)


def screen_fixture(source, name, owned):
    helper = declaration(source, CATEGORY_MARKER)
    helper = replace_counted(helper, "private func", "func", "fixture access")
    helper = replace_counted(helper, "UISelectionFeedbackGenerator().selectionChanged()",
                             'events.append("feedback")', "inert feedback spy")
    if owned:
        fields = "var session = EagleDockGallerySession()\n" + "\n".join(session_aliases(source, host_class=True))
        initialize = "session = input.state"
        memory = "MediaFilter.allCases.map { rememberedSelections.restoredID(for: $0) }"
    else:
        fields = """
    var selectedRemoteID = ""
    var mediaFilter = MediaFilter.still
    var rememberedSelections: [MediaFilter: String] = [:]
    var readyRemotePreviewID = ""
    var shuffledRemoteIDs: [String] = []
    var visitStarted = false
"""
        initialize = """
        selectedRemoteID = input.state.selectedRemoteID
        mediaFilter = input.state.mediaFilter
        readyRemotePreviewID = input.state.readyRemotePreviewID
        shuffledRemoteIDs = input.state.shuffledRemoteIDs
        visitStarted = input.state.visitStarted
        for filter in MediaFilter.allCases {
            rememberedSelections[filter] = input.state.rememberedSelections.restoredID(for: filter)
        }
"""
        memory = "MediaFilter.allCases.map { rememberedSelections[$0] }"
    return "final class " + name + " {\n" + """
    typealias MediaFilter = EagleDockGalleryMediaFilter
    var isApplying = false
    var remoteGallery = CategoryStore()
    var displayedID: String?
    var events: [String] = []
    var readSnapshots: [CategorySnapshot] = []
    var syncSnapshots: [CategorySnapshot] = []
    var selectedRemoteTheme: CategoryTheme? {
        events.append("read")
        readSnapshots.append(snapshot())
        return displayedID.map { CategoryTheme(id: $0) }
    }
    func synchronizeRemoteSelection() {
        events.append("sync")
        syncSnapshots.append(snapshot())
    }
""" + fields + "\ninit(_ input: CategoryInput) {\n" + initialize + """
        isApplying = input.applying
        remoteGallery.downloadingID = input.downloadingID
        displayedID = input.displayedID
    }
    func snapshot() -> CategorySnapshot {
        CategorySnapshot(filter: mediaFilter, selected: selectedRemoteID,
                         preview: readyRemotePreviewID, order: shuffledRemoteIDs,
                         started: visitStarted, memory: """ + memory + ")\n}\n" + helper + "\n}\n"


def host_projection(values):
    return "import Foundation\n" + screen_fixture(values["public_view"], "BaselineCategoryFixture", False) + "\n" + screen_fixture(values["current"], "OwnedCategoryFixture", True)


def swiftui_projection(current):
    return "import SwiftUI\nimport UIKit\nprivate struct CategoryBindingFixture: View {\n" + """
    private typealias MediaFilter = EagleDockGalleryMediaFilter
    private struct Theme { let id: String }
    private struct Store { var downloadingID: String? }
    private var remoteGallery = Store()
    private var selectedRemoteTheme: Theme? { Theme(id: selectedRemoteID) }
    private func synchronizeRemoteSelection() {}
""" + "\n".join(screen_bindings(current, ("mediaFilter", "selectedRemoteID", "isApplying"))) + "\n" + declaration(current, CATEGORY_MARKER) + """
    var body: some View {
        Button("Live") { selectMediaFilter(.live) }
        Button("Saves") { selectMediaFilter(.favorites) }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = source_values(repo)
    negative_count = verify_negatives(values)
    print(f"PASS: public-derived category transition and exact guarded caller; {negative_count} negative mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [str(repo / path) for path in CORE_PATHS]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-category-") as directory:
        work = Path(directory)
        host = work / "ExactCategoryFixtures.swift"
        host.write_text(host_projection(values))
        binary = work / "verify-category"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(host),
                        str(repo / "scripts/verify_eagle_dock_category_transition.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactCategoryBindings.swift"
        fixture.write_text(swiftui_projection(values["current"]))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck", "-target", "arm64-apple-ios16.0",
                        "-sdk", sdk, *sources, str(fixture)], check=True, timeout=55)
    print("PASS: actual category caller/State bridges typecheck in inert iOS fixture; no UI observer runtime, full app, native backend or IPA", flush=True)


if __name__ == "__main__":
    main()
