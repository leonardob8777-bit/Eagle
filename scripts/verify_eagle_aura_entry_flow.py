#!/usr/bin/env python3
"""Aura entry/channel lifecycle coordination compared with public observer bodies."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioEntryFlow.swift"
MARKERS = [".onAppear {", ".onChange(of: releaseChannelRaw)"]
BRIDGES = [".onAppear {\n            entryFlow.prepareForAppearance()\n#if DEBUG\n            if !AuraStudioNativeContract.invariantsHold {\n                AuraStudioDiagnostics.log(\n                    \"contract.self-test\",\n                    \"result=failed engine=\\(auraEngineBuild)\"\n                )\n            }\n#endif\n        }",".onChange(of: releaseChannelRaw) { _ in\n            entryFlow.releaseChannelChanged()\n        }"]
CONTROLLER = "private var entryFlow: EagleAuraStudioEntryFlow {\n        EagleAuraStudioEntryFlow(\n            readMigrated: { independentProfilesMigrated },\n            readLegacyMode: { legacySelectedModeRaw },\n            writeIslandMode: { islandModeRaw = $0 },\n            writeDockMode: { dockModeRaw = $0 },\n            markMigrated: { independentProfilesMigrated = true },\n            normalizeDraftModes: { normalizeDraftModesForPolicy() },\n            islandAvailable: { islandProfileAvailable },\n            readSelectedTarget: { selectedTargetRaw },\n            writeSelectedTarget: { selectedTargetRaw = $0 },\n            islandTargetRaw: AuraStudioTarget.island.rawValue,\n            dockTargetRaw: AuraStudioTarget.dock.rawValue,\n            reconcileActiveState: { reconcilePersistedActiveState() },\n            safetyLocked: { mgr.rcSafetyLocked },\n            markSafetyBlocked: { applySafetyBlocked = true },\n            isApplying: { isApplying }\n        )\n    }"
PREFIX = "import Foundation\n\n/// Orders Aura entry and channel-change preparation; UI, storage and safety checks stay injected.\n@MainActor\nstruct EagleAuraStudioEntryFlow {\n    let readMigrated: () -> Bool\n    let readLegacyMode: () -> Int\n    let writeIslandMode: (Int) -> Void\n    let writeDockMode: (Int) -> Void\n    let markMigrated: () -> Void\n    let normalizeDraftModes: () -> Void\n    let islandAvailable: () -> Bool\n    let readSelectedTarget: () -> Int\n    let writeSelectedTarget: (Int) -> Void\n    let islandTargetRaw: Int\n    let dockTargetRaw: Int\n    let reconcileActiveState: () -> Void\n    let safetyLocked: () -> Bool\n    let markSafetyBlocked: () -> Void\n    let isApplying: () -> Bool\n\n"
SUBSTITUTIONS = [["independentProfilesMigrated = true","markMigrated()",1],["!independentProfilesMigrated","!readMigrated()",1],["legacySelectedModeRaw","readLegacyMode()",1],["islandModeRaw = legacyMode.rawValue","writeIslandMode(legacyMode.rawValue)",1],["dockModeRaw = (legacyMode == .tint ? AuraStudioMode.glow : legacyMode).rawValue","writeDockMode((legacyMode == .tint ? AuraStudioMode.glow : legacyMode).rawValue)",1],["AuraStudioMode","EagleAuraStudioMode",2],["normalizeDraftModesForPolicy()","normalizeDraftModes()",1],["!islandProfileAvailable","!islandAvailable()",1],["selectedTargetRaw = AuraStudioTarget.dock.rawValue","writeSelectedTarget(dockTargetRaw)",1],["selectedTargetRaw == AuraStudioTarget.island.rawValue","readSelectedTarget() == islandTargetRaw",1],["reconcilePersistedActiveState()","reconcileActiveState()",1],["mgr.rcSafetyLocked","safetyLocked()",1],["applySafetyBlocked = true","markSafetyBlocked()",1]]


def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=Path(__file__).resolve().parents[1], text=True)


def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]


def inline_entry(view):
    from verify_eagle_aura_operation_ui import inline_operation_ui
    view = inline_operation_ui(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "    " + CONTROLLER + "\n\n", "")


def expected_core():
    appear, change = originals()
    source = appear[appear.index("{") + 1:appear.index("#if DEBUG")]
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    change = change[change.index("_ in") + 4:change.rindex("}")]
    change = replace_once(change, "!isApplying", "!isApplying()")
    change = replace_once(change, "normalizeDraftModesForPolicy()", "normalizeDraftModes()")
    return PREFIX + "func prepareForAppearance() {" + source + "}\nfunc releaseChannelChanged() {" + change + "}\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated screen, debug guard or callback changed"
    assert compact(core) == compact(expected_core()), "Entry/channel ordering changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "readLegacyMode: { legacySelectedModeRaw }", "readLegacyMode: { islandModeRaw }"),
        (0, "writeDockMode: { dockModeRaw = $0 }", "writeDockMode: { islandModeRaw = $0 }"),
        (0, "markMigrated: { independentProfilesMigrated = true }", "markMigrated: { independentProfilesMigrated = false }"),
        (0, "safetyLocked: { mgr.rcSafetyLocked }", "safetyLocked: { false }"),
        (0, "isApplying: { isApplying }", "isApplying: { false }"),
        (0, "if !AuraStudioNativeContract.invariantsHold", "if false"),
        (0, '"eagle.auraStudio.independentProfilesMigrated"', '"changed.migration"'),
        (1, "if !readMigrated()", "if true"),
        (1, "?? .glow", "?? .rainbow"),
        (1, "legacyMode == .tint", "legacyMode == .pulse"),
        (1, "writeIslandMode(legacyMode.rawValue)", "writeIslandMode(1)"),
        (1, "if !islandAvailable()", "if islandAvailable()"),
        (1, "readSelectedTarget() == islandTargetRaw", "readSelectedTarget() == dockTargetRaw"),
        (1, "if safetyLocked() { markSafetyBlocked() }", "markSafetyBlocked()"),
        (1, "guard !isApplying() else { return }", "guard true else { return }"),
        (1, "reconcileActiveState()\n        if safetyLocked()", "if safetyLocked()"),
    ]
    for index, before, after in cases:
        texts = [view, core]; texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: public entry/channel bodies, preserved debug guard, exact callbacks/screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, members in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        appear = members[0][members[0].index("{") + 1:members[0].rindex("}")]
        change = members[1][members[1].index("_ in") + 4:members[1].rindex("}")]
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     + "func appear() {" + appear + "}\nfunc channel() {" + change + "}\n"
                     + (CONTROLLER if name == "OwnedHost" else "") + "\n}\n")
    fixture = (repo / "scripts/verify_eagle_aura_entry_flow.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="eagle-aura-entry-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture + "\n" + "\n".join(hosts))
        for flags in (["-Onone", "-D", "DEBUG"], ["-O"]):
            binary = Path(temporary) / ("debug" if "-D" in flags else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", *flags, str(repo / CORE),
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioModePolicy.swift"),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
