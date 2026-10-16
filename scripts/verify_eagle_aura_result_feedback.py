#!/usr/bin/env python3
"""Exact public Aura result wording/decisions, callbacks and source boundary parity."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioResultFeedback.swift"
MARKERS = ["private func successMessage(", "private func message(for result:", "private func names(for flags:"]
BRIDGES = ["private func successMessage(\n        appliedFlags: UInt32,\n        requestedFlags: UInt32,\n        restoring: Bool,\n        motionDegraded: Bool,\n        appliedMode: AuraStudioMode?\n    ) -> String {\n        resultFeedback.successMessage(\n            appliedFlags: appliedFlags,\n            requestedFlags: requestedFlags,\n            restoring: restoring,\n            motionDegraded: motionDegraded,\n            appliedMode: appliedMode\n        )\n    }","private func message(for result: Int32) -> String {\n        resultFeedback.message(for: result)\n    }","private func names(for flags: UInt32) -> [String] {\n        resultFeedback.names(for: flags)\n    }"]
CONTROLLER = "private var resultFeedback: EagleAuraStudioResultFeedback {\n        EagleAuraStudioResultFeedback(\n            islandFlag: Flag.island,\n            screenFlag: Flag.screen,\n            batteryFlag: Flag.battery,\n            dockFlag: Flag.dock,\n            lockFlag: Flag.lock,\n            modeTitle: { $0.title },\n            localizedText: { LaraL10n.text(en: $0, es: $1) }\n        )\n    }"
PREFIX = "import Foundation\n\n/// Result wording only. Native verification and result classification remain at the caller.\n@MainActor\nstruct EagleAuraStudioResultFeedback {\n    let islandFlag: UInt32\n    let screenFlag: UInt32\n    let batteryFlag: UInt32\n    let dockFlag: UInt32\n    let lockFlag: UInt32\n    let modeTitle: (EagleAuraStudioMode) -> String\n    let localizedText: (String, String) -> String\n\n    "
SUBSTITUTIONS = [["private func","func",3],["AuraStudioMode","EagleAuraStudioMode",1],["appliedMode.title","modeTitle(appliedMode)",1],["Flag.island","islandFlag",1],["Flag.screen","screenFlag",1],["Flag.battery","batteryFlag",1],["Flag.dock","dockFlag",1],["Flag.lock","lockFlag",1],["LaraL10n.text(","localizedText(",35],["en: \"","\"",35],["es: \"","\"",35]]

def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=Path(__file__).resolve().parents[1], text=True)

def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]

def inline_feedback(view):
    from verify_eagle_aura_completion import inline_completion
    view = inline_completion(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")

def expected_core():
    source = "\n\n    ".join(originals())
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated UI/native/result-classification logic changed"
    assert compact(core) == compact(expected_core()), "Result decision or wording changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "islandFlag: Flag.island", "islandFlag: Flag.dock"),
        (0, "dockFlag: Flag.dock", "dockFlag: Flag.island"),
        (0, "resultFeedback.message(for: result)", "resultFeedback.message(for: 0)"),
        (0, "resultFeedback.names(for: flags)", "resultFeedback.names(for: 0)"),
        (0, "beginGate: { AuraStudioApplyGate.begin() }", "beginGate: { true }"),
        (1, "if restoring {", "if !restoring {"),
        (1, "if motionDegraded {", "if !motionDegraded {"),
        (1, "if appliedFlags != 0, let appliedMode", "if appliedFlags == 0, let appliedMode"),
        (1, "case -24:", "case -25:"),
        (1, "modeTitle(appliedMode)", '""'),
        (1, 'names.append("Dock")', 'names.append("Island")'),
        (1, "No unavailable surface was reported as active.", "All surfaces are active."),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in CONTROLLER:
            texts[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: complete public result text/decision parity; whole-screen/native reversal; {len(cases)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_result_feedback.swift").read_text()
    for name, members in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        # Expose only these exact source methods to the comparison fixture.
        body = "\n".join(members).replace("private func", "func")
        fixture += "\n@MainActor struct " + name + " {\n" + body + "\n" + (CONTROLLER if name == "OwnedHost" else "") + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-result-feedback-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__":
    main()

