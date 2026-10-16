#!/usr/bin/env python3
"""Verify Aura profile identity, lazy stored selection and flags against public source."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift"
MARKERS = ["private enum AuraStudioTarget:", "private var selectedTarget:",
           "private var selectedFlags:", "private func flag(for target:"]
BRIDGES = ["private typealias AuraStudioTarget = EagleAuraStudioTarget", '''private var selectedTarget: AuraStudioTarget {
        get {
            EagleAuraStudioTarget.storedSelection(
                rawValue: selectedTargetRaw,
                islandProfileAvailable: { islandProfileAvailable }
            )
        }
        nonmutating set { selectedTargetRaw = newValue.rawValue }
    }''', '''private var selectedFlags: UInt32 {
        selectedTarget.flag(islandFlag: Flag.island, dockFlag: Flag.dock)
    }''', '''private func flag(for target: AuraStudioTarget) -> UInt32 {
        target.flag(islandFlag: Flag.island, dockFlag: Flag.dock)
    }''']
PREFIX = "import Foundation\n\n/// Profile identity and stored-selection rules; storage and hardware availability remain with the caller.\n"
SELECTION_SIGNATURE = '''static func storedSelection(
        rawValue: Int,
        islandProfileAvailable: () -> Bool
    ) -> EagleAuraStudioTarget {'''
FLAG_SIGNATURE = '''func flag(
        islandFlag: @autoclosure () -> UInt32,
        dockFlag: @autoclosure () -> UInt32
    ) -> UInt32 {'''

def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]

def inline_target(view):
    from verify_eagle_aura_diagnostics_presentation import inline_diagnostics_presentation
    view = inline_diagnostics_presentation(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return view

def expected_core():
    target, selection, selected_flags, flag = originals()
    target = replace_once(target, "private enum AuraStudioTarget: Int, CaseIterable, Identifiable {",
                          "nonisolated enum EagleAuraStudioTarget: Int, CaseIterable, Identifiable, Sendable {")
    getter = declaration(selection, "        get {")
    getter = replace_once(getter, "        get {", SELECTION_SIGNATURE)
    getter = replace_once(getter, "AuraStudioTarget(rawValue: selectedTargetRaw)", "EagleAuraStudioTarget(rawValue: rawValue)")
    getter = replace_once(getter, "!islandProfileAvailable", "!islandProfileAvailable()")
    flag = replace_once(flag, "private func flag(for target: AuraStudioTarget) -> UInt32 {", FLAG_SIGNATURE)
    flag = replace_once(flag, "target == .island ? Flag.island : Flag.dock", "self == .island ? islandFlag() : dockFlag()")
    assert "selectedTarget == .island ? Flag.island : Flag.dock" in selected_flags
    return PREFIX + target[:-1] + getter + "\n\n" + flag + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Storage key/default, hardware rules, native code or screen changed"
    assert compact(core) == compact(expected_core()), "Profile identity or selection rules changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, BRIDGES[0], "private typealias AuraStudioTarget = OtherTarget"),
        (0, "islandProfileAvailable: { islandProfileAvailable }", "islandProfileAvailable: { true }"),
        (0, "nonmutating set { selectedTargetRaw = newValue.rawValue }", "nonmutating set { selectedTargetRaw = 1 }"),
        (0, '"eagle.auraStudio.editingTarget"', '"eagle.auraStudio.otherTarget"'),
        (0, "private var selectedTargetRaw = AuraStudioTarget.island.rawValue", "private var selectedTargetRaw = AuraStudioTarget.dock.rawValue"),
        (0, BRIDGES[2], BRIDGES[2].replace("Flag.island", "Flag.dock")),
        (0, BRIDGES[3], BRIDGES[3].replace("Flag.dock", "Flag.island")),
        (1, "case island = 1", "case island = 3"),
        (1, "case dock = 2", "case dock = 4"),
        (1, 'return "Dynamic Island"', 'return "Island"'),
        (1, "?? .dock", "?? .island"),
        (1, "stored == .island && !islandProfileAvailable()", "!islandProfileAvailable() && stored == .island"),
        (1, "? .dock : stored", "? .island : stored"),
        (1, "self == .island ? islandFlag() : dockFlag()", "self == .island ? dockFlag() : islandFlag()"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0 and before == "islandProfileAvailable: { islandProfileAvailable }":
            values[0] = replace_once(view, BRIDGES[1], replace_once(BRIDGES[1], before, after))
        else:
            values[index] = replace_once(values[index], before, after)
        try: verify_texts(*values)
        except AssertionError: continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: public target/selection/flag members, unchanged storage/hardware/native source; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_target.swift").read_text()
    target, *members = originals()
    fixture += "\n" + target.replace("private enum AuraStudioTarget", "nonisolated enum PublicTarget") + "\n"
    for name, owned in [("PublicHost", False), ("OwnedHost", True)]:
        source = "\n".join(BRIDGES[1:] if owned else members).replace("private var ", "var ").replace("private func ", "func ")
        if not owned: source = source.replace("AuraStudioTarget", "PublicTarget")
        fixture += f"\n@MainActor struct {name}: Host {{\nlet context: Context\n{source}\n}}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-target-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__": main()
