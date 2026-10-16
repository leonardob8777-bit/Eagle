#!/usr/bin/env python3
"""Pure Aura operation values/step planning against actual public declarations."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift"
BRIDGES = ["private typealias AuraStudioOperation = EagleAuraStudioOperation","private typealias AuraStudioOperationStep = EagleAuraStudioOperationStep\n\nprivate extension EagleAuraStudioOperationStep {\n    var localizedName: String {\n        localizedName(localizedText: { LaraL10n.text(en: $0, es: $1) })\n    }\n}","        let requestedProfileMode = operation.requestedProfileMode","        let steps = EagleAuraStudioOperation.steps(\n            for: requestedFlags,\n            islandFlag: Flag.island,\n            dockFlag: Flag.dock\n        )"]
PREFIX = "import Foundation\n\n/// Operation values and ordered descriptors only; authorization and native execution stay in the caller.\n"
PROPERTY = "    var requestedProfileMode: EagleAuraStudioMode {\n        switch self {\n        case .apply(let profileMode):\n            return profileMode\n        case .remove:\n            return .glow\n        }\n    }"
SIGNATURE = "    static func steps(\n        for requestedFlags: UInt32,\n        islandFlag: UInt32,\n        dockFlag: UInt32\n    ) -> [EagleAuraStudioOperationStep] {"
def originals():
    source = public_file()
    a = source.index("        var steps: [AuraStudioOperationStep]")
    b = source.index("\n\n        let selectedRGB", a)
    c = source.index("        let requestedProfileMode: AuraStudioMode")
    d = source.index("\n        let requestedFlags", c)
    return [declaration(source, "private enum AuraStudioOperation {"),
            declaration(source, "private struct AuraStudioOperationStep {"), source[c:d], source[a:b]]
def inline_operation_plan(view):
    from verify_eagle_aura_preview import inline_preview
    view = inline_preview(view)
    for bridge, old in zip(BRIDGES, originals()): view = replace_once(view, bridge, old)
    return view
def expected_core():
    operation, step, request, steps = originals()
    operation = replace_once(operation, "private enum AuraStudioOperation {", "nonisolated enum EagleAuraStudioOperation: Sendable {")
    operation = replace_once(operation, "AuraStudioMode", "EagleAuraStudioMode")
    # Compare the new property to the original switch (not an independently copied rule).
    expected_property = request.replace("        let requestedProfileMode: AuraStudioMode\n", "").replace("switch operation", "switch self").replace("requestedProfileMode =", "return")
    expected_property = "    var requestedProfileMode: EagleAuraStudioMode {\n" + expected_property + "\n    }"
    assert compact(PROPERTY) == compact(expected_property)
    steps = steps.replace("AuraStudioOperationStep", "EagleAuraStudioOperationStep").replace("Flag.island", "islandFlag").replace("Flag.dock", "dockFlag")
    operation = operation[:-1] + "\n" + PROPERTY + "\n\n" + SIGNATURE + "\n" + steps + "\n        return steps\n    }\n}"
    step = replace_once(step, "private struct AuraStudioOperationStep {", "nonisolated struct EagleAuraStudioOperationStep: Sendable {")
    step = replace_once(step, "var localizedName: String {", "func localizedName(localizedText: (String, String) -> String) -> String {")
    step = replace_once(step, "LaraL10n.text(en: englishName, es: spanishName)", "localizedText(englishName, spanishName)")
    return PREFIX + operation + "\n\n" + step + "\n"
def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Native gates/calls or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Operation values/step planning changed"
def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "let requestedProfileMode = context.requestedProfileMode", "let requestedProfileMode = AuraStudioMode.glow"),
        (0, BRIDGES[3], BRIDGES[3].replace("Flag.island", "Flag.dock")),
        (0, "flagForTarget: { flag(for: $0) }", "flagForTarget: { _ in Flag.island }"),
        (1, "case .remove: return 0", "case .remove: return 1"),
        (1, "return .glow", "return .rainbow"),
        (1, "if case .remove = self { return true }", "if case .remove = self { return false }"),
        (1, "requestedFlags & islandFlag", "requestedFlags & dockFlag"),
        (1, 'englishName: "Dock"', 'englishName: "Island"'),
        (1, "return steps", "return steps.reversed()"),
        (1, "localizedText(englishName, spanishName)", "localizedText(spanishName, englishName)"),
    ]
    for index, before, after in cases:
        texts = [view, core]; texts[index] = replace_once(texts[index], before, after)
        try: verify_texts(*texts)
        except AssertionError: continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: public declarations/request switch/steps and full-screen reversal; {len(cases)} rejected mutations", flush=True)
    op, step, requested, steps = originals()
    fixture = (repo / "scripts/verify_eagle_aura_operation_plan.swift").read_text()
    fixture += "\n" + op.replace("private enum AuraStudioOperation", "enum PublicOperation") + "\n"
    fixture += step.replace("private struct AuraStudioOperationStep", "@MainActor struct PublicStep") + "\n"
    fixture += "@MainActor enum PublicPlan {\nstatic func requested(_ operation: PublicOperation) -> AuraStudioMode {\n" + requested + "\nreturn requestedProfileMode\n}\n"
    fixture += "static func steps(_ requestedFlags: UInt32) -> [PublicStep] {\n" + steps.replace("AuraStudioOperationStep", "PublicStep") + "\nreturn steps\n}\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-operation-plan-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                            "-parse-as-library", mode, str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
if __name__ == "__main__": main()

