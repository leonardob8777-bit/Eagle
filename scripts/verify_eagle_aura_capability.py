#!/usr/bin/env python3
"""Preserve Aura capability text/button decisions and lazy state reads, without authorizing native operations."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioCapability.swift"
MARKERS = ["private var selectedCapabilityTitle:", "private var selectedCapabilityDescription:", "private var isApplyButtonDisabled:"]
BRIDGES = ["private var selectedCapabilityTitle: String {\n        capabilityPresentation.selectedCapabilityTitle\n    }","private var selectedCapabilityDescription: String {\n        capabilityPresentation.selectedCapabilityDescription\n    }","private var isApplyButtonDisabled: Bool {\n        capabilityPresentation.isApplyButtonDisabled\n    }"]
CONTROLLER = "private var capabilityPresentation: EagleAuraStudioCapability {\n        EagleAuraStudioCapability(\n            localSafetyBlocked: { applySafetyBlocked },\n            remoteSafetyLocked: { mgr.rcSafetyLocked },\n            accessIsReady: { mgr.dsready },\n            operationInProgress: { isApplying },\n            requestedFlags: { selectedFlags },\n            selectedTargetTitle: { selectedTarget.title },\n            selectedTargetIsIsland: { selectedTarget == .island },\n            selectedMode: { selectedMode },\n            localizedText: { LaraL10n.text(en: $0, es: $1) }\n        )\n    }"
PREFIX = "import Foundation\n\n/// Read-only capability messages and button presentation; native authorization remains in the caller.\n@MainActor\nstruct EagleAuraStudioCapability {\n    let localSafetyBlocked: () -> Bool\n    let remoteSafetyLocked: () -> Bool\n    let accessIsReady: () -> Bool\n    let operationInProgress: () -> Bool\n    let requestedFlags: () -> UInt32\n    let selectedTargetTitle: () -> String\n    let selectedTargetIsIsland: () -> Bool\n    let selectedMode: () -> EagleAuraStudioMode\n    let localizedText: (String, String) -> String\n\n    "
SUBSTITUTIONS = [["private var","var",3],["applySafetyBlocked","localSafetyBlocked()",3],["mgr.rcSafetyLocked","remoteSafetyLocked()",3],["mgr.dsready","accessIsReady()",3],["isApplying","operationInProgress()",1],["selectedFlags","requestedFlags()",1],["selectedTarget.title","selectedTargetTitle()",2],["switch selectedTarget {\n        case .island:","if selectedTargetIsIsland() {",1],["        case .dock:","        } else {",1],["selectedMode == .tint","selectedMode() == .tint",1],["LaraL10n.text(","localizedText(",8],["en: ","",8],["es: ","",8]]

def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]

def inline_capability(view):
    from verify_eagle_aura_target import inline_target
    view = inline_target(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")

def expected_core():
    source = "\n\n".join(originals())
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before))
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Native authorization, bindings or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Messages, button decision or lazy reads changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "localSafetyBlocked: { applySafetyBlocked }", "localSafetyBlocked: { false }"),
        (0, "remoteSafetyLocked: { mgr.rcSafetyLocked }", "remoteSafetyLocked: { false }"),
        (0, "accessIsReady: { mgr.dsready }", "accessIsReady: { true }"),
        (0, "operationInProgress: { isApplying }", "operationInProgress: { false }"),
        (0, "requestedFlags: { selectedFlags }", "requestedFlags: { 1 }"),
        (0, "selectedTargetIsIsland: { selectedTarget == .island }", "selectedTargetIsIsland: { selectedTarget == .dock }"),
        (0, "flagForTarget: { flag(for: $0) }", "flagForTarget: { _ in Flag.island }"),
        (1, "localSafetyBlocked() || remoteSafetyLocked()", "remoteSafetyLocked() || localSafetyBlocked()"),
        (1, "if !accessIsReady()", "if accessIsReady()"),
        (1, "selectedMode() == .tint", "selectedMode() == .glow"),
        (1, "requestedFlags() == 0", "requestedFlags() != 0"),
        (1, "operationInProgress() || !accessIsReady()", "!accessIsReady() || operationInProgress()"),
        (1, "Safety lock active", "Ready"),
        (1, "Bloqueo de seguridad activo", "Listo"),
        (1, "if selectedTargetIsIsland()", "if !selectedTargetIsIsland()"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        assert before in values[index]
        values[index] = values[index].replace(before, after)
        try: verify_texts(*values)
        except AssertionError: continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: three public capability/button members, exact callbacks and whole-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_capability.swift").read_text()
    for name, owned in [("PublicHost", False), ("OwnedHost", True)]:
        members = BRIDGES if owned else originals()
        body = "\n".join(members + ([CONTROLLER] if owned else []))
        fixture += "\n@MainActor struct " + name + ": CapabilityHost {\nlet context: Context\n" + body.replace("private var ", "var ") + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-capability-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__": main()
