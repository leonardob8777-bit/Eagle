#!/usr/bin/env python3
"""Public Aura saved-state reconciliation with recording preferences and no native calls."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioReconciliation.swift"
MARKER = "private func reconcilePersistedActiveState("
BRIDGE = "private func reconcilePersistedActiveState(currentPID providedPID: Int32? = nil) {\n        EagleAuraStudioReconciliation(\n            lookupCurrentPID: {\n                \"SpringBoard\".withCString { find_process_pid($0) }\n            },\n            decodeFlags: { EagleStoredThemeValues.flags($0) },\n            supportedFlags: Flag.supported,\n            deviceSupportedFlags: { deviceSupportedFlags },\n            islandFlag: Flag.island,\n            dockFlag: Flag.dock,\n            read: { field in\n                switch field {\n                case .flags: return activeFlagsRaw\n                case .legacyMode: return activeModeRaw\n                case .islandMode: return activeIslandModeRaw\n                case .dockMode: return activeDockModeRaw\n                case .dockGalleryStyle: return activeDockGalleryStyleRaw\n                case .springBoardPID: return activeSpringBoardPID\n                }\n            },\n            write: { field, value in\n                switch field {\n                case .flags: activeFlagsRaw = value\n                case .legacyMode: activeModeRaw = value\n                case .islandMode: activeIslandModeRaw = value\n                case .dockMode: activeDockModeRaw = value\n                case .dockGalleryStyle: activeDockGalleryStyleRaw = value\n                case .springBoardPID: activeSpringBoardPID = value\n                }\n            },\n            diagnosticsToken: { islandCompatibility.diagnosticsToken },\n            log: { AuraStudioDiagnostics.log($0, $1) }\n        ).reconcilePersistedActiveState(currentPID: providedPID)\n    }"
PREFIX = "import Foundation\n\n/// Reconciles saved Aura metadata without owning preferences or querying the system.\n@MainActor\nstruct EagleAuraStudioReconciliation {\n    enum Field: CaseIterable {\n        case flags, legacyMode, islandMode, dockMode, dockGalleryStyle, springBoardPID\n    }\n\n    let lookupCurrentPID: () -> Int32\n    let decodeFlags: (Int) -> UInt32\n    let supportedFlags: UInt32\n    let deviceSupportedFlags: () -> UInt32\n    let islandFlag: UInt32\n    let dockFlag: UInt32\n    let read: (Field) -> Int\n    let write: (Field, Int) -> Void\n    let diagnosticsToken: () -> String\n    let log: (String, String) -> Void\n\n    "
SUBSTITUTIONS = [["private func","func",1],["\"SpringBoard\".withCString {\n            find_process_pid($0)\n        }","lookupCurrentPID()",1],["EagleStoredThemeValues.flags","decodeFlags",1],["Flag.supported","supportedFlags",1],["deviceSupportedFlags","deviceSupportedFlags()",1],["Flag.island","islandFlag",2],["Flag.dock","dockFlag",2],["AuraStudioDiagnostics.log","log",2],["islandCompatibility.diagnosticsToken","diagnosticsToken()",1],["activeFlagsRaw = Int(savedFlags)","write(.flags, Int(savedFlags))",1],["activeIslandModeRaw = activeModeRaw","write(.islandMode, read(.legacyMode))",1],["activeDockModeRaw = activeModeRaw","write(.dockMode, read(.legacyMode))",1],["activeFlagsRaw = 0","write(.flags, 0)",2],["activeModeRaw = 0","write(.legacyMode, 0)",3],["activeIslandModeRaw = 0","write(.islandMode, 0)",4],["activeDockModeRaw = 0","write(.dockMode, 0)",3],["activeDockGalleryStyleRaw = 0","write(.dockGalleryStyle, 0)",3],["activeSpringBoardPID = 0","write(.springBoardPID, 0)",2],["activeFlagsRaw","read(.flags)",1],["activeModeRaw","read(.legacyMode)",0],["activeIslandModeRaw","read(.islandMode)",1],["activeDockModeRaw","read(.dockMode)",1],["activeDockGalleryStyleRaw","read(.dockGalleryStyle)",0],["activeSpringBoardPID","read(.springBoardPID)",3]]


def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=Path(__file__).resolve().parents[1], text=True)


def original():
    return declaration(public_file(), MARKER)


def inline_reconciliation(view):
    from verify_eagle_aura_entry_flow import inline_entry
    view = inline_entry(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    source = original()
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated screen/reconciliation binding changed"
    assert compact(core) == compact(expected_core()), "Saved-state sequencing changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "case .flags: return activeFlagsRaw", "case .flags: return activeModeRaw"),
        (0, "case .dockMode: activeDockModeRaw = value", "case .dockMode: activeIslandModeRaw = value"),
        (0, "deviceSupportedFlags: { deviceSupportedFlags }", "deviceSupportedFlags: { Flag.supported }"),
        (0, "diagnosticsToken: { islandCompatibility.diagnosticsToken }", 'diagnosticsToken: { "missing" }'),
        (0, '"eagle.auraStudio.independentProfilesMigrated"', '"changed.migration"'),
        (1, "providedPID ?? lookupCurrentPID()", "lookupCurrentPID()"),
        (1, "rawSavedFlags & deviceSupportedFlags()", "rawSavedFlags"),
        (1, "if rawSavedFlags != savedFlags", "if false"),
        (1, "guard savedFlags != 0", "guard true"),
        (1, "currentPID == Int32(read(.springBoardPID))", "currentPID != Int32(read(.springBoardPID))"),
        (1, '"state.expired"', '"changed.expired"'),
        (1, "if savedFlags & islandFlag == 0", "if savedFlags & dockFlag == 0"),
        (1, "read(.islandMode) == 0", "read(.islandMode) != 0"),
        (1, "write(.dockMode, read(.legacyMode))", "write(.islandMode, read(.legacyMode))"),
        (1, "let savedFlags = rawSavedFlags & deviceSupportedFlags()", "let savedFlags = decodeFlags(read(.flags)) & deviceSupportedFlags()"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in BRIDGE:
            # Shared field names occur in other extracted adapters too. Exercise
            # the exact reconciliation binding while retaining full-screen parity.
            texts[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: complete public reconciliation, exact bindings/full-screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, member in (("PublicHost", original()), ("OwnedHost", BRIDGE)):
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     "func run(_ pid: Int32?) { reconcilePersistedActiveState(currentPID: pid) }\n"
                     + member + "\n}\n")
    properties = []
    for index, name in enumerate(["activeFlagsRaw", "activeModeRaw", "activeIslandModeRaw",
                                  "activeDockModeRaw", "activeDockGalleryStyleRaw", "activeSpringBoardPID"]):
        properties.append(f"var {name}: Int {{ get {{ context.read({index}) }} nonmutating set {{ context.write({index}, newValue) }} }}")
    fixture = (repo / "scripts/verify_eagle_aura_reconciliation.swift").read_text()
    fixture += "\nextension Host {\n" + "\n".join(properties) + "\n}\n" + "\n".join(hosts)
    with tempfile.TemporaryDirectory(prefix="eagle-aura-reconciliation-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(repo / "lara/classes/EagleStoredThemeValues.swift"), str(source), "-o", str(binary)],
                           check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
