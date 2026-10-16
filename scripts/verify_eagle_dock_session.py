#!/usr/bin/env python3
"""Verify the owned session value and exact screen storage bridges."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

from verify_eagle_dock_builtin_theme import compact, declaration
from verify_eagle_dock_synchronization import inline_synchronization
from verify_eagle_dock_interactions import inline_interactions


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGallerySession.swift"
SESSION_DEPENDENCIES = (
    "lara/EagleCore/DockGallery/EagleDockGalleryFavorites.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryMediaFilter.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySelectionMemory.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySelection.swift",
    MODEL_PATH,
    "lara/EagleCore/DockGallery/EagleDockGalleryVisitOrder.swift",
    "lara/EagleCore/DockGallery/EagleDockGallerySynchronization.swift",
    "lara/EagleCore/DockGallery/EagleDockGalleryInteractions.swift",
)
CORE_PATHS = ("lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift", *SESSION_DEPENDENCIES)
VIEW_MARKER = "struct DockGalleryView: View"
OWNED_MARKER = "nonisolated struct EagleDockGallerySession: Sendable"
SESSION_BINDING = "@State private var session: EagleDockGallerySession = .init()"
FIELDS = {
    "selectedRemoteID": ("String", '@State private var selectedRemoteID = ""'),
    "mediaFilter": ("MediaFilter", "@State private var mediaFilter: MediaFilter = .still"),
    "rememberedSelections": ("EagleDockGallerySelectionMemory", "@State private var rememberedSelections: EagleDockGallerySelectionMemory = .init()"),
    "shuffledRemoteIDs": ("[String]", "@State private var shuffledRemoteIDs: [String] = []"),
    "visitStarted": ("Bool", "@State private var visitStarted = false"),
    "readyRemotePreviewID": ("String", '@State private var readyRemotePreviewID = ""'),
}
BEGIN_MARKER = "private func beginGalleryVisit()"
OLD_BEGIN = """private func beginGalleryVisit() {
        visitStarted = true
        shuffledRemoteIDs = []
        selectedRemoteID = ""
        readyRemotePreviewID = ""
        rememberedSelections = .init()
        mediaFilter = .still
        synchronizeRemoteSelection()
    }"""
NEW_BEGIN = """private func beginGalleryVisit() {
        session.beginVisit()
        synchronizeRemoteSelection()
    }"""
CATEGORY_MARKER = "private func selectMediaFilter(_ filter: MediaFilter)"
CATEGORY_CORE_MARKER = "mutating func selectCategory(_ filter: EagleDockGalleryMediaFilter, remembering selectedThemeID: String?)"
CATEGORY_GUARD = "        guard mediaFilter != filter, !isApplying, remoteGallery.downloadingID == nil else { return }\n"
CATEGORY_BODY = """        rememberedSelections.remember(id: selectedRemoteTheme?.id, for: mediaFilter)
        readyRemotePreviewID = ""
        mediaFilter = filter
        selectedRemoteID = rememberedSelections.restoredID(for: filter) ?? ""
"""
CATEGORY_EFFECTS = """        synchronizeRemoteSelection()
        UISelectionFeedbackGenerator().selectionChanged()
"""
OLD_CATEGORY = CATEGORY_MARKER + " {\n" + CATEGORY_GUARD + CATEGORY_BODY + CATEGORY_EFFECTS + "    }"
NEW_CATEGORY = CATEGORY_MARKER + " {\n" + CATEGORY_GUARD + """        let selectedThemeID = selectedRemoteTheme?.id
        session.selectCategory(filter, remembering: selectedThemeID)
""" + CATEGORY_EFFECTS + "    }"
STEP_MARKER = "private func stepRemote(_ step: Int)"
STEP_CORE_MARKER = "mutating func step(_ step: Int, in themes: [EagleDockGalleryTheme])"
STEP_GUARDS = """        guard !isApplying, remoteGallery.downloadingID == nil else { return }
        let themes = visibleRemoteThemes
        guard themes.count > 1 else { return }
"""
STEP_BODY = """        let current = EagleDockGallerySelection.currentIndex(in: themes, selectedID: selectedRemoteID)
        let next = EagleDockGallerySelection.nextIndex(current: current, step: step, count: themes.count)
        readyRemotePreviewID = ""
        selectedRemoteID = themes[next].id
"""
STEP_EFFECTS = """        rememberViewedTheme()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
"""
OLD_STEP = STEP_MARKER + " {\n" + STEP_GUARDS + STEP_BODY + STEP_EFFECTS + "    }"
NEW_STEP = STEP_MARKER + " {\n" + STEP_GUARDS + "        session.step(step, in: themes)\n" + STEP_EFFECTS + "    }"
SYNC_MARKER = "private func synchronizeRemoteSelection()"
RECOVERY_CORE_MARKER = "func reconcilingSelection(in themes: [EagleDockGalleryTheme]) -> Self?"
ORDER_CORE_MARKER = "func adoptingOrder(_ order: [String]) -> Self?"
OLD_ORDER_ADOPTION = "if shuffledRemoteIDs != order { shuffledRemoteIDs = order }"
NEW_ORDER_ADOPTION = """if let reorderedSession = session.adoptingOrder(order) {
            session = reorderedSession
        }"""
PUBLIC_REPLACEMENT = """if !visibleRemoteThemes.contains(where: { $0.id == selectedRemoteID }) {
            readyRemotePreviewID = ""
            selectedRemoteID = visibleRemoteThemes.first?.id ?? ""
        }"""
OLD_RECOVERY = """if let replacementID = EagleDockGallerySelection.replacementID(in: visibleRemoteThemes, selectedID: selectedRemoteID) {
            readyRemotePreviewID = ""
            selectedRemoteID = replacementID
        }"""
NEW_RECOVERY = """let themes = visibleRemoteThemes
        if let updatedSession = session.reconcilingSelection(in: themes) {
            session = updatedSession
        }"""


def reconciliation_tail(source):
    if "EagleDockGallerySynchronization.synchronize(" in declaration(source, SYNC_MARKER):
        source = inline_synchronization(source)
    sync = declaration(source, SYNC_MARKER)
    markers = ["        " + marker for marker in (OLD_ORDER_ADOPTION, NEW_ORDER_ADOPTION) if marker in sync]
    assert len(markers) == 1, "Expected one known order-adoption boundary"
    marker = markers[0]
    assert sync.count(marker) == 1, "Conditional order adoption changed"
    return sync[sync.index(marker):]


def reconciliation_statement(source):
    if "EagleDockGallerySynchronization.synchronize(" in declaration(source, SYNC_MARKER):
        source = inline_synchronization(source)
    sync = declaration(source, SYNC_MARKER)
    assert sync.count(NEW_RECOVERY) == 1, "Exact order-read/reconcile/commit sequence changed"
    return NEW_RECOVERY


def replace_counted(source, old, new, label):
    assert source.count(old) == 1, f"Counted session boundary changed: {label}"
    return source.replace(old, new, 1)


def expected_alias(field):
    field_type = FIELDS[field][0]
    return f"""private var {field}: {field_type} {{
        get {{ session.{field} }}
        nonmutating set {{ session.{field} = newValue }}
    }}"""


def session_aliases(view, host_class=False):
    result = []
    for field in FIELDS:
        actual = declaration(view, f"private var {field}:")
        assert compact(actual) == compact(expected_alias(field)), f"Incorrect session bridge: {field}"
        if host_class:
            actual = replace_counted(actual, "private var ", "var ", "host fixture visibility")
            actual = replace_counted(actual, "nonmutating set", "set", "host class setter syntax")
        result.append(actual)
    return result


def screen_bindings(view, fields):
    """Project actual State plus exact requested bridges for inert UI fixtures."""
    result = []
    if any(field in FIELDS for field in fields):
        assert view.count(SESSION_BINDING) == 1, "Expected one owned session State"
        result.append(SESSION_BINDING)
    for field in fields:
        if field in FIELDS:
            actual = declaration(view, f"private var {field}:")
            assert compact(actual) == compact(expected_alias(field)), f"Incorrect binding bridge: {field}"
            result.append(actual)
        else:
            lines = [line.strip() for line in view.splitlines() if " private var " + field in line and "@" in line]
            assert len(lines) == 1, f"Expected one actual external binding: {field}"
            result.append(lines[0])
    return result


def add_session_sources(paths):
    return tuple(dict.fromkeys((*paths, *SESSION_DEPENDENCIES)))


def project_session_begin(source):
    begin = declaration(source, BEGIN_MARKER)
    assert compact(begin) == compact(OLD_BEGIN), "Pre-session visit reset changed"
    return replace_counted(source, begin, NEW_BEGIN, "visit-reset ownership")


def project_session_category(source):
    category = declaration(source, CATEGORY_MARKER)
    assert compact(category) == compact(OLD_CATEGORY), "Pre-transition category helper changed"
    return replace_counted(source, category, NEW_CATEGORY, "category-transition ownership")


def expected_category(public_view):
    category = declaration(public_view, CATEGORY_MARKER)
    category = replace_counted(category, "rememberedSelections[mediaFilter] = selectedRemoteTheme?.id",
                               "rememberedSelections.remember(id: selectedRemoteTheme?.id, for: mediaFilter)", "owned memory assignment")
    category = replace_counted(category, 'rememberedSelections[filter] ?? ""',
                               'rememberedSelections.restoredID(for: filter) ?? ""', "owned memory lookup")
    assert compact(category) == compact(OLD_CATEGORY), "Public category guards/order/effects changed"
    category = replace_counted(category, CATEGORY_MARKER, CATEGORY_CORE_MARKER, "explicit data transition signature")
    category = replace_counted(category, CATEGORY_GUARD, "", "guard stays before snapshot in UI")
    category = replace_counted(category, "selectedRemoteTheme?.id", "selectedThemeID", "displayed ID snapshot input")
    return replace_counted(category, CATEGORY_EFFECTS, "", "sync and feedback stay outside Core")


def project_session_step(source):
    step = declaration(source, STEP_MARKER)
    assert compact(step) == compact(OLD_STEP), "Pre-transition navigation helper changed"
    return replace_counted(source, step, NEW_STEP, "navigation-transition ownership")


def expected_step(public_view):
    step = declaration(public_view, STEP_MARKER)
    step = replace_counted(step, "let current = themes.firstIndex(where: { $0.id == selectedRemoteID }) ?? 0",
                          "let current = EagleDockGallerySelection.currentIndex(in: themes, selectedID: selectedRemoteID)", "owned index rule")
    step = replace_counted(step, "let next = (current + step + themes.count) % themes.count",
                          "let next = EagleDockGallerySelection.nextIndex(current: current, step: step, count: themes.count)", "owned arithmetic rule")
    assert compact(step) == compact(OLD_STEP), "Public navigation guards/order/effects changed"
    step = replace_counted(step, STEP_MARKER, STEP_CORE_MARKER, "explicit navigation data signature")
    step = replace_counted(step, STEP_GUARDS, "", "operation/count guards and snapshot stay in UI")
    return replace_counted(step, STEP_EFFECTS, "", "persistence and feedback stay outside Core")


def project_session_reconciliation(source):
    sync = declaration(source, SYNC_MARKER)
    projected = replace_counted(sync, OLD_RECOVERY, NEW_RECOVERY, "owned reconciliation and explicit snapshot")
    projected = replace_counted(projected, OLD_ORDER_ADOPTION, NEW_ORDER_ADOPTION, "owned conditional order adoption")
    return replace_counted(source, sync, projected, "complete synchronization declaration")


def expected_order_adoption(public_view):
    sync = declaration(public_view, SYNC_MARKER)
    assert sync.count(OLD_ORDER_ADOPTION) == 1, "Public conditional order adoption changed"
    return ORDER_CORE_MARKER + """ {
        guard shuffledRemoteIDs != order else { return nil }
        var updated = self
        updated.shuffledRemoteIDs = order
        return updated
    }"""


def expected_reconciliation(public_view):
    sync = declaration(public_view, SYNC_MARKER)
    assert sync.count(PUBLIC_REPLACEMENT) == 1, "Public missing-selection recovery changed"
    mutations = PUBLIC_REPLACEMENT.split("{\n", 1)[1].rsplit("}", 1)[0]
    mutations = replace_counted(mutations, 'selectedRemoteID = visibleRemoteThemes.first?.id ?? ""',
                                "updated.selectedRemoteID = replacementID", "explicit replacement result")
    mutations = replace_counted(mutations, "readyRemotePreviewID", "updated.readyRemotePreviewID", "value-copy preview reset")
    return RECOVERY_CORE_MARKER + " {\n" + """
        guard let replacementID = EagleDockGallerySelection.replacementID(in: themes, selectedID: selectedRemoteID) else { return nil }
        var updated = self
""" + mutations + "\nreturn updated\n}"


def project_view_session(source):
    result = source
    for field, (_, old) in FIELDS.items():
        if field == "selectedRemoteID":
            result = replace_counted(result, old, SESSION_BINDING, "single session State")
        else:
            result = replace_counted(result, "    " + old + "\n", "", f"owned field {field}")
    anchor = "    @State private var showAccessSetup = false\n"
    aliases = "\n" + "\n\n".join("    " + expected_alias(field) for field in FIELDS) + "\n"
    result = replace_counted(result, anchor, anchor + aliases, "exact screen storage bridges")
    return project_session_begin(result)


def expected_model(public_view):
    declarations = []
    for field, (_, binding) in FIELDS.items():
        public_binding = binding
        if field == "rememberedSelections":
            public_binding = "@State private var rememberedSelections: [MediaFilter: String] = [:]"
        assert public_view.count(public_binding) == 1, f"Public state/default changed: {field}"
        declarations.append(binding.replace("@State private ", "").replace(": MediaFilter", ": EagleDockGalleryMediaFilter"))
    begin = declaration(public_view, BEGIN_MARKER)
    begin = replace_counted(begin, BEGIN_MARKER, "mutating func beginVisit()", "owned reset signature")
    begin = replace_counted(begin, "rememberedSelections = [:]", "rememberedSelections = .init()", "owned memory reset")
    begin = replace_counted(begin, "        synchronizeRemoteSelection()\n", "", "screen synchronization remains outside")
    return OWNED_MARKER + " {\n" + "\n".join(declarations) + "\n" + begin + "\n" + expected_category(public_view) + "\n" + expected_step(public_view) + "\n" + expected_order_adoption(public_view) + "\n" + expected_reconciliation(public_view) + "\n}"


def verify_contract(public_view, current, model):
    inline_synchronization(current)
    expanded = inline_interactions(current)
    code = re.sub(r"//[^\n]*", "", model)
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_model(public_view)), "Session defaults/reset/category/navigation/reconciliation transitions differ from public state"
    assert code.replace(actual, "", 1).split() == ["import", "Foundation"], "Session gained imports/shared state"
    assert current.count(SESSION_BINDING) == 1, "Expected one UI-owned Core session"
    for _, binding in FIELDS.values():
        assert binding not in current, "Duplicated transient State remains in screen"
    session_aliases(current)
    assert compact(declaration(expanded, BEGIN_MARKER)) == compact(NEW_BEGIN), "Visit reset/synchronization order changed"
    assert compact(declaration(expanded, CATEGORY_MARKER)) == compact(NEW_CATEGORY), "Category guard/snapshot/transition/effect order changed"
    assert compact(declaration(expanded, STEP_MARKER)) == compact(NEW_STEP), "Navigation guards/snapshot/transition/effect order changed"
    expected_tail = replace_counted(reconciliation_tail(public_view), PUBLIC_REPLACEMENT, NEW_RECOVERY, "reconciliation tail")
    expected_tail = replace_counted(expected_tail, OLD_ORDER_ADOPTION, NEW_ORDER_ADOPTION, "order adoption tail")
    assert compact(reconciliation_tail(current)) == compact(expected_tail), "Order commit/list snapshot/reconciliation/persistence sequence changed"


def verify_sources(repo):
    repo = Path(repo)
    public = subprocess.check_output(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55)
    public_view = declaration(public, VIEW_MARKER)
    current = (repo / VIEW_PATH).read_text()
    verify_contract(public_view, current, (repo / MODEL_PATH).read_text())
    return current


def host_bridge(current):
    begin = declaration(current, BEGIN_MARKER).replace("private func", "func", 1)
    return "import Foundation\nfinal class SessionBridgeFixture {\n" + """
    typealias MediaFilter = EagleDockGalleryMediaFilter
    var session = EagleDockGallerySession()
    var synchronized: [EagleDockGallerySession] = []
    func synchronizeRemoteSelection() { synchronized.append(session) }
""" + "\n".join(session_aliases(current, host_class=True)) + "\n" + begin + "\n}\n"


def swiftui_projection(current):
    return "import SwiftUI\nprivate struct SessionBindingFixture: View {\n" + """
    private typealias MediaFilter = EagleDockGalleryMediaFilter
    private func synchronizeRemoteSelection() {}
""" + "\n".join(screen_bindings(current, tuple(FIELDS))) + "\n" + declaration(current, BEGIN_MARKER) + "\n" + """
    var body: some View {
        Text(selectedRemoteID)
        Button("Change") {
            rememberedSelections.remember(id: selectedRemoteID, for: mediaFilter)
            shuffledRemoteIDs.append("fixture")
            mediaFilter = .favorites
            readyRemotePreviewID = selectedRemoteID
            visitStarted = false
        }
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
    print("PASS: public-derived session transitions/reconciliation and exact guarded screen wiring", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
    sources = [str(repo / path) for path in CORE_PATHS]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-session-") as directory:
        work = Path(directory)
        host = work / "ExactSessionBridge.swift"
        host.write_text(host_bridge(current))
        binary = work / "verify-session"
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, str(host),
                        str(repo / "scripts/verify_eagle_dock_session.swift"), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
        fixture = work / "ExactSessionBindings.swift"
        fixture.write_text(swiftui_projection(current))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck", "-target", "arm64-apple-ios16.0",
                        "-sdk", sdk, *sources, str(fixture)], check=True, timeout=55)
    print("PASS: actual unified State/nonmutating bridges/reset typecheck in inert iOS SwiftUI fixture; no observer runtime/app/backend/IPA", flush=True)


if __name__ == "__main__":
    main()
