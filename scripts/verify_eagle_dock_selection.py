#!/usr/bin/env python3
"""Check pure selection/index parity and inert screen effects against public code.

Only the actual Foundation theme/selection and generated benign fixtures compile.
No original view/app target, applying/access backend, simulator or IPA is built.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_selection_memory import PUBLIC_REPLACEMENT
from verify_eagle_dock_session import (
    MODEL_PATH as SESSION_MODEL_PATH, STEP_CORE_MARKER,
    add_session_sources, project_session_step, screen_bindings, session_aliases,
    verify_contract as verify_session_contract,
)


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift"
CORE_PATHS = ("lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift", MODEL_PATH)
VIEW_MARKER = "struct DockGalleryView: View"
SELECTED_MARKER = "private var selectedRemoteTheme: RemoteDockGalleryTheme?"
POSITION_MARKER = "private var remotePositionText: String"
STEP_MARKER = "private func stepRemote(_ step: Int)"
OWNED_MARKER = "nonisolated enum EagleDockGallerySelection"
REMEMBER_MARKER = "private func rememberViewedTheme()"
LAST_VIEWED_MARKER = "static func lastViewed(_ theme: EagleDockGalleryTheme?) -> LastViewed?"
LAST_VIEWED_VALUE = """enum LastViewed: Sendable {
        case still(String)
        case live(String)
    }"""
REMEMBER_CALLER = """private func rememberViewedTheme() {
        guard let lastViewed = EagleDockGallerySelection.lastViewed(selectedRemoteTheme) else { return }
        switch lastViewed {
        case .live(let id):
            lastViewedLiveID = id
        case .still(let id):
            lastViewedStaticID = id
        }
    }"""
PUBLIC_CURRENT = "let current = themes.firstIndex(where: { $0.id == selectedRemoteID }) ?? 0"
PUBLIC_NEXT = "let next = (current + step + themes.count) % themes.count"
OWNED_CURRENT = "let current = EagleDockGallerySelection.currentIndex(in: themes, selectedID: selectedRemoteID)"
OWNED_NEXT = "let next = EagleDockGallerySelection.nextIndex(current: current, step: step, count: themes.count)"
SELECTED_GETTER = """private var selectedRemoteTheme: RemoteDockGalleryTheme? {
        EagleDockGallerySelection.selected(in: visibleRemoteThemes, selectedID: selectedRemoteID)
    }"""


def replace_counted(source, old, new, label, count=1):
    assert source.count(old) == count, f"Counted selection boundary changed: {label}"
    return source.replace(old, new)


def expected_metadata(public_view):
    remembered = declaration(public_view, REMEMBER_MARKER)
    remembered = replace_counted(remembered, REMEMBER_MARKER, LAST_VIEWED_MARKER, "last-viewed explicit value input/result")
    remembered = replace_counted(remembered, "guard let theme = selectedRemoteTheme else { return }",
                                 "guard let theme else { return nil }", "nil theme leaves preferences untouched")
    remembered = replace_counted(remembered, "lastViewedLiveID = theme.id", "return .live(theme.id)", "live preference update value")
    remembered = replace_counted(remembered, "lastViewedStaticID = theme.id", "return .still(theme.id)", "static preference update value")
    selected = declaration(public_view, SELECTED_MARKER)
    selected = replace_counted(selected, SELECTED_MARKER,
                               "static func selected(in themes: [EagleDockGalleryTheme], selectedID: String) -> EagleDockGalleryTheme?",
                               "explicit selected value input/result")
    selected = replace_counted(selected, "visibleRemoteThemes", "themes", "snapshot parameter", count=2)
    selected = replace_counted(selected, "selectedRemoteID", "selectedID", "selected identity parameter")
    position = declaration(public_view, POSITION_MARKER)
    step = declaration(public_view, STEP_MARKER)
    assert position.count(PUBLIC_CURRENT) == step.count(PUBLIC_CURRENT) == 1, "Public current-index rules diverged"
    assert step.count(PUBLIC_NEXT) == 1, "Public next-index arithmetic changed"
    current_expression = PUBLIC_CURRENT.removeprefix("let current = ")
    current_expression = replace_counted(current_expression, "selectedRemoteID", "selectedID", "index identity input")
    next_expression = PUBLIC_NEXT.removeprefix("let next = ")
    next_expression = replace_counted(next_expression, "themes.count", "count", "count value input", count=2)
    current = "static func currentIndex(in themes: [EagleDockGalleryTheme], selectedID: String) -> Int {\n" + current_expression + "\n}"
    following = "static func nextIndex(current: Int, step: Int, count: Int) -> Int {\n" + next_expression + "\n}"
    sync = declaration(public_view, "private func synchronizeRemoteSelection()")
    assert sync.count(PUBLIC_REPLACEMENT) == 1, "Public replacement branch changed"
    recovery = PUBLIC_REPLACEMENT
    recovery = replace_counted(recovery, '            readyRemotePreviewID = ""\n', "", "preview reset remains in screen")
    recovery = replace_counted(recovery, "selectedRemoteID = ", "return ", "replacement value result")
    recovery = replace_counted(recovery, "visibleRemoteThemes", "themes", "recovery list snapshot", count=2)
    recovery = replace_counted(recovery, "selectedRemoteID", "selectedID", "recovery identity input")
    replacement = "static func replacementID(in themes: [EagleDockGalleryTheme], selectedID: String) -> String? {\n" + recovery + "\nreturn nil\n}"
    return OWNED_MARKER + " {\n" + LAST_VIEWED_VALUE + "\n" + remembered + "\n" + selected + "\n" + current + "\n" + following + "\n" + replacement + "\n}"


def project_last_viewed(source):
    """Only the exact last-viewed helper changes; AppStorage/call sites stay put."""
    original = declaration(source, REMEMBER_MARKER)
    return replace_counted(source, original, REMEMBER_CALLER, "complete last-viewed delegation")


def project_view_selection(source):
    """Three exact declaration projections; no general selection/UI exemption."""
    selected = declaration(source, SELECTED_MARKER)
    result = replace_counted(source, selected, SELECTED_GETTER, "selected theme delegation")
    position = declaration(result, POSITION_MARKER)
    projected_position = replace_counted(position, PUBLIC_CURRENT, OWNED_CURRENT, "position current-index delegation")
    result = replace_counted(result, position, projected_position, "complete position getter")
    step = declaration(result, STEP_MARKER)
    projected_step = replace_counted(step, PUBLIC_CURRENT, OWNED_CURRENT, "step current-index delegation")
    projected_step = replace_counted(projected_step, PUBLIC_NEXT, OWNED_NEXT, "step arithmetic delegation")
    return replace_counted(result, step, projected_step, "complete guarded step")


def _verify_contract(public_view, current, model, session):
    from verify_eagle_dock_interactions import inline_interactions
    expanded = inline_interactions(current)
    # Accepted Dock/Island visual alignment: two-digit counter, same indices.
    expanded = replace_counted(expanded,
        'return String(format: "%02d", current + 1) + " / " + String(format: "%02d", themes.count)',
        'return "\\(current + 1) / \\(themes.count)"', 'two-digit display only')
    code = re.sub(r"//[^\n]*", "", model)
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_metadata(public_view)), (
        "Selection differs from public first-match/fallback/current-index or exact next-index arithmetic"
    )
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], (
        "Selection gained imports, shared state or external code"
    )
    expected = project_last_viewed(project_session_step(project_view_selection(public_view)))
    for marker in (SELECTED_MARKER, POSITION_MARKER, STEP_MARKER, REMEMBER_MARKER):
        assert compact(declaration(expanded, marker)) == compact(declaration(expected, marker)), (
            f"Selection caller changed snapshot/inputs/guards/display/effect order: {marker}"
        )
    verify_session_contract(public_view, current, session)


def verify_sources(repo):
    """Import-safe source-only boundary, also used by the whole model gate."""
    repo = Path(repo)
    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    values = {"public_view": declaration(public, VIEW_MARKER),
              "current": (repo / VIEW_PATH).read_text(), "model": (repo / MODEL_PATH).read_text(),
              "session": (repo / SESSION_MODEL_PATH).read_text()}
    _verify_contract(**values)
    return values


def verify_memory_negatives(values):
    cases = [
        ("model", None, "themes.first(where:", "themes.last(where:"),
        ("model", None, "themes.first\n", "themes.last\n"),
        ("model", None, "$0.id == selectedID", "$0.title == selectedID", 3),
        ("model", None, "themes.firstIndex(where:", "themes.lastIndex(where:"),
        ("model", None, "?? 0", "?? 1"),
        ("model", None, "$0.id == selectedID", "$0.id.lowercased() == selectedID.lowercased()", 3),
        ("model", None, "themes.first\n", "nil\n"),
        ("model", None, "(current + step + count) % count", "(current + count + step) % count"),
        ("model", None, "(current + step + count) % count", "((current + step) % count + count) % count"),
        ("model", None, "(current + step + count) % count", "abs(current + step + count) % count"),
        ("model", None, "(current + step + count) % count", "max(0, current + step) % count"),
        ("model", None, "(current + step + count) % count", "(current &+ step &+ count) % count"),
        ("model", None, "(current + step + count) % count", "guard count > 1 else { return 0 }; return (current + step + count) % count"),
        ("model", None, "import Foundation", "import Foundation\nimport SwiftUI"),
        ("model", None, "import Foundation", "import Foundation\nvar sharedSelectedID = \"\""),
        ("current", SELECTED_MARKER, "in: visibleRemoteThemes", "in: remoteGallery.themes"),
        ("current", SELECTED_MARKER, "selectedID: selectedRemoteID", "selectedID: activeRemoteID"),
        ("current", POSITION_MARKER, "selectedID: selectedRemoteID", "selectedID: \"\""),
        ("current", POSITION_MARKER, "let themes = visibleRemoteThemes", "let themes = remoteGallery.themes"),
        ("current", POSITION_MARKER, 'String(format: "%02d", current + 1)', 'String(format: "%02d", current)'),
        ("current", STEP_MARKER, "isApplying: { isApplying }", "isApplying: { false }"),
        ("current", STEP_MARKER, "downloadingID: { remoteGallery.downloadingID }", "downloadingID: { nil }"),
        ("session", STEP_CORE_MARKER, "selectedID: selectedRemoteID", 'selectedID: ""'),
        ("session", STEP_CORE_MARKER, "current: current, step: step, count: themes.count", "current: current, step: 1, count: themes.count"),
        ("session", STEP_CORE_MARKER, "count: themes.count", "count: shuffledRemoteIDs.count"),
        ("session", STEP_CORE_MARKER, 'readyRemotePreviewID = ""\n        selectedRemoteID = themes[next].id', 'selectedRemoteID = themes[next].id\n        readyRemotePreviewID = ""'),
        ("current", STEP_MARKER, "writeSession: { session = $0 }", "writeSession: { _ in }"),
        ("current", STEP_MARKER, "rememberViewedTheme: { rememberViewedTheme() }", "rememberViewedTheme: {}"),
        ("current", STEP_MARKER, "            step,", "            1,"),
        ("current", STEP_MARKER, "visibleThemes: { visibleRemoteThemes }", "visibleThemes: { remoteGallery.themes }"),
        ("current", STEP_MARKER, "readSession: { session }", "readSession: { EagleDockGallerySession() }"),
        ("session", STEP_CORE_MARKER, "selectedRemoteID = themes[next].id", "selectedRemoteID = themes[next].id\n        mediaFilter = .still"),
        ("session", STEP_CORE_MARKER, "selectedRemoteID = themes[next].id", "selectedRemoteID = themes[next].id\n        rememberedSelections = .init()"),
    ]
    for case in cases:
        field, marker, old, new, *counts = case
        altered = values.copy()
        region = declaration(altered[field], marker) if marker else altered[field]
        mutation = replace_counted(region, old, new, f"negative {field}/{marker}", count=counts[0] if counts else 1)
        altered[field] = replace_counted(altered[field], region, mutation, "negative declaration") if marker else mutation
        try:
            _verify_contract(**altered)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Changed selection source escaped rejection: {old}")
    return len(cases)


def screen_fixture(source, name, owned):
    """Exact benign getters/step with state/event spies, not real UI observers."""
    parts = []
    for marker in (SELECTED_MARKER, POSITION_MARKER, STEP_MARKER):
        part = declaration(source, marker)
        part = replace_counted(part, marker, marker.removeprefix("private "), "fixture visibility")
        if marker == STEP_MARKER:
            part = replace_counted(part, "UIImpactFeedbackGenerator(style: .soft).impactOccurred()",
                                   'events.append("haptic")', "inert feedback spy")
        parts.append(part)
    if owned:
        fields = "var session = EagleDockGallerySession()\n" + "\n".join(session_aliases(source, host_class=True))
    else:
        fields = 'var selectedRemoteID = ""\nvar readyRemotePreviewID = ""\n'
    return "final class " + name + " {\n" + r'''
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    typealias MediaFilter = EagleDockGalleryMediaFilter
    struct Store { var downloadingID: String? }
    var remoteGallery = Store()
    var themes: [EagleDockGalleryTheme] = []
    var snapshotReads = 0
    var listReadStates: [[[UInt8]]] = []
    var visibleRemoteThemes: [EagleDockGalleryTheme] {
        snapshotReads += 1
        listReadStates.append([Array(selectedRemoteID.utf8), Array(readyRemotePreviewID.utf8)])
        return themes
    }
    var events: [String] = []
    var rememberStates: [[[UInt8]]] = []
    var isApplying = false
    func rememberViewedTheme() {
        rememberStates.append([Array(selectedRemoteID.utf8), Array(readyRemotePreviewID.utf8)])
        events.append("remember:" + readyRemotePreviewID + ":" + selectedRemoteID)
    }
''' + fields + "\n" + "\n".join(parts) + "\n}\n"


def runtime_projection(values):
    reference = replace_counted(expected_metadata(values["public_view"]), OWNED_MARKER,
                                "enum BaselineDockGallerySelection", "public helper fixture name/actor")
    return ("import Foundation\n\n" + reference + "\n" +
            screen_fixture(values["public_view"], "BaselineSelectionScreenFixture", False) +
            screen_fixture(values["current"], "OwnedSelectionScreenFixture", True))


def swiftui_projection(values):
    view = declaration(values["current"], VIEW_MARKER)
    bindings = screen_bindings(view, ("selectedRemoteID", "readyRemotePreviewID", "isApplying"))
    return "import Foundation\nimport SwiftUI\nimport UIKit\n\nprivate struct SelectionBindingFixture: View {\n" + """
    private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    private struct Store { var downloadingID: String? }
    private var remoteGallery = Store()
    private var visibleRemoteThemes: [EagleDockGalleryTheme] { [] }
    private func rememberViewedTheme() {}
""" + "\n".join(bindings) + "\n" + "\n".join(
        declaration(view, marker) for marker in (SELECTED_MARKER, POSITION_MARKER, STEP_MARKER)
    ) + "\n" + """
    var body: some View {
        Text(remotePositionText)
        Text(selectedRemoteTheme?.id ?? "")
        Button("Next") { stepRemote(1) }
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    negative_count = verify_memory_negatives(values)
    print(f"PASS: exact public/owned selection and four complete callers; {negative_count} negative mutations rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [repo / path for path in add_session_sources(CORE_PATHS)]
    runner = repo / "scripts/verify_eagle_dock_selection.swift"
    assert runner.is_file(), "Standalone selection runner required"
    with tempfile.TemporaryDirectory(prefix="eagle-dock-selection-") as directory:
        work = Path(directory)
        reference = work / "ExactPublicDockGallerySelection.swift"
        reference.write_text(runtime_projection(values))
        binary = work / "verify-dock-selection"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", *map(str, sources), str(reference), str(runner), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactSelectionSwiftUIBindings.swift"
        fixture.write_text(swiftui_projection(values))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, *map(str, sources), str(fixture)],
            check=True, timeout=55,
        )
    print("PASS: actual selection getters/State/guarded step typecheck in inert iOS SwiftUI/UIKit fixture; temporary outputs cleaned; no app/native backend/IPA", flush=True)


if __name__ == "__main__":
    main()
