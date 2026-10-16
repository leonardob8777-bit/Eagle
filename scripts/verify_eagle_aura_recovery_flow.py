#!/usr/bin/env python3
"""Two Aura presentation flows: preflight rejection and already-verified rollback."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW

CORES = ["lara/EagleCore/AuraStudio/EagleAuraStudioPreflightFailure.swift","lara/EagleCore/AuraStudio/EagleAuraStudioVerifiedRollback.swift"]
MARKERS = ["func failBeforeNativeCall(", "func finishVerifiedRollback("]
BRIDGES = ["func failBeforeNativeCall(_ reason: String) {\n            EagleAuraStudioPreflightFailure(\n                operationID: operationID,\n                targetTitle: { operationTarget.title },\n                log: { AuraStudioDiagnostics.log($0, $1) },\n                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },\n                resetOperationUI: { resetOperationUI() },\n                endGate: { AuraStudioApplyGate.end() },\n                localizedText: { LaraL10n.text(en: $0, es: $1) },\n                showNotice: { notice = AuraStudioNotice(message: $0) }\n            ).failBeforeNativeCall(reason)\n        }","func finishVerifiedRollback(\n            _ result: Int32,\n            step: AuraStudioOperationStep,\n            reason: String\n        ) {\n            EagleAuraStudioVerifiedRollback(\n                previouslyVerified: previouslyVerified,\n                newlyApplied: newlyApplied,\n                operationSpringBoardPID: operationSpringBoardPID,\n                operationID: operationID,\n                readRetained: { retainedVerified },\n                writeRetained: { retainedVerified = $0 },\n                writeActiveFlags: { activeFlagsRaw = $0 },\n                writeSpringBoardPID: { activeSpringBoardPID = $0 },\n                log: { AuraStudioDiagnostics.log($0, $1) },\n                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },\n                resetOperationUI: { resetOperationUI() },\n                endGate: { AuraStudioApplyGate.end() },\n                errorMessage: { message(for: $0) },\n                localizedText: { LaraL10n.text(en: $0, es: $1) },\n                showNotice: { notice = AuraStudioNotice(message: $0) }\n            ).finishVerifiedRollback(\n                result,\n                stepFlag: step.flag,\n                stepEnglishName: step.englishName,\n                reason: reason\n            )\n        }"]
PREFIXES = ["import Foundation\n\n/// Presentation cleanup when the caller rejects an operation before any native mutation.\n@MainActor\nstruct EagleAuraStudioPreflightFailure {\n    let operationID: String\n    let targetTitle: () -> String\n    let log: (String, String) -> Void\n    let recordDiagnostics: (String) -> Void\n    let resetOperationUI: () -> Void\n    let endGate: () -> Void\n    let localizedText: (String, String) -> String\n    let showNotice: (String) -> Void\n\n    ","import Foundation\n\n/// Commits presentation state only after the caller has verified native rollback.\n/// This component does not perform rollback, verify a session or retry an operation.\n@MainActor\nstruct EagleAuraStudioVerifiedRollback {\n    let previouslyVerified: UInt32\n    let newlyApplied: UInt32\n    let operationSpringBoardPID: Int32\n    let operationID: String\n    let readRetained: () -> UInt32\n    let writeRetained: (UInt32) -> Void\n    let writeActiveFlags: (Int) -> Void\n    let writeSpringBoardPID: (Int) -> Void\n    let log: (String, String) -> Void\n    let recordDiagnostics: (String) -> Void\n    let resetOperationUI: () -> Void\n    let endGate: () -> Void\n    let errorMessage: (Int32) -> String\n    let localizedText: (String, String) -> String\n    let showNotice: (String) -> Void\n\n    "]
SUBSTITUTIONS = [[["AuraStudioDiagnostics.log(","log(",1],["diagnosticsURL = makeDiagnosticsReport(summary: reason)","recordDiagnostics(reason)",1],["AuraStudioApplyGate.end()","endGate()",1],["LaraL10n.text(","localizedText(",1],["en: \"","\"",1],["es: \"","\"",1],["operationTarget.title","targetTitle()",2],["notice = AuraStudioNotice(message: localizedText(","showNotice(localizedText(",1]],[["step: AuraStudioOperationStep,","stepFlag: UInt32,\n        stepEnglishName: String,",1],["retainedVerified |= previouslyVerified & step.flag","writeRetained(readRetained() | (previouslyVerified & stepFlag))",1],["let finalFlags = retainedVerified | newlyApplied","let finalFlags = readRetained() | newlyApplied",1],["activeFlagsRaw = Int(finalFlags)","writeActiveFlags(Int(finalFlags))",1],["activeSpringBoardPID = finalFlags == 0\n            ? 0\n            : Int(operationSpringBoardPID)","writeSpringBoardPID(finalFlags == 0\n            ? 0\n            : Int(operationSpringBoardPID))",1],["step.englishName","stepEnglishName",1],["AuraStudioDiagnostics.log(","log(",1],["diagnosticsURL = makeDiagnosticsReport(summary: reason)","recordDiagnostics(reason)",1],["AuraStudioApplyGate.end()","endGate()",1],["LaraL10n.text(","localizedText(",1],["en: \"","\"",1],["es: \"","\"",1],["notice = AuraStudioNotice(\n            message: message(for: result)","showNotice(\n            errorMessage(result)",1]]]

def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]

def inline_recovery_flow(view):
    from verify_eagle_aura_unverified_failure import inline_unverified_failure
    view = inline_unverified_failure(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return view

def expected_core(index):
    source = "\n".join(line[4:] if n else line for n, line in enumerate(originals()[index].split("\n")))
    for before, after, count in SUBSTITUTIONS[index]:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIXES[index] + source + "\n}\n"

def verify_texts(view, preflight, rollback):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated UI/native/rollback verification or callback changed"
    for index, core in enumerate((preflight, rollback)):
        assert compact(core) == compact(expected_core(index)), "Recovery presentation sequencing changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, preflight, rollback = [(repo / p).read_text() for p in (VIEW, *CORES)]
    verify_texts(view, preflight, rollback)
    cases = [
        (0, 0, "targetTitle: { operationTarget.title }", 'targetTitle: { "Dock" }'),
        (0, 0, "recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) }", "recordDiagnostics: { _ in }"),
        (0, 0, "endGate: { AuraStudioApplyGate.end() }", "endGate: {}"),
        (0, 0, "showNotice: { notice = AuraStudioNotice(message: $0) }", "showNotice: { _ in }"),
        (0, 1, "readRetained: { retainedVerified }", "readRetained: { previouslyVerified }"),
        (0, 1, "writeRetained: { retainedVerified = $0 }", "writeRetained: { _ in }"),
        (0, 1, "previouslyVerified: previouslyVerified", "previouslyVerified: 0"),
        (0, 1, "newlyApplied: newlyApplied", "newlyApplied: 0"),
        (0, 1, "stepFlag: step.flag", "stepFlag: 0"),
        (0, 1, "writeSpringBoardPID: { activeSpringBoardPID = $0 }", "writeSpringBoardPID: { activeSpringBoardPID = 0 }"),
        (0, 1, "errorMessage: { message(for: $0) }", 'errorMessage: { _ in "Success" }'),
        (0, -1, "beginGate: { AuraStudioApplyGate.begin() }", "beginGate: { true }"),
        (1, -1, "resetOperationUI()\n        endGate()", "endGate()\n        resetOperationUI()"),
        (1, -1, "recordDiagnostics(reason)", 'recordDiagnostics("")'),
        (1, -1, "targetTitle()", '"Island"'),
        (2, -1, "previouslyVerified & stepFlag", "previouslyVerified | stepFlag"),
        (2, -1, "readRetained() | newlyApplied", "readRetained() & newlyApplied"),
        (2, -1, "writeActiveFlags(Int(finalFlags))", "writeActiveFlags(0)"),
        (2, -1, "finalFlags == 0", "finalFlags != 0"),
        (2, -1, "endGate()", ""),
        (2, -1, "errorMessage(result)", '""'),
        (2, -1, "resetOperationUI()\n        endGate()", "endGate()\n        resetOperationUI()"),
    ]
    for index, bridgeIndex, before, after in cases:
        texts = [view, preflight, rollback]
        if bridgeIndex >= 0:
            bridge = BRIDGES[bridgeIndex]
            texts[0] = replace_once(view, bridge, replace_once(bridge, before, after))
        elif index == 1 and before == "targetTitle()":
            assert texts[index].count(before) == 2
            texts[index] = texts[index].replace(before, after)
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: both complete public recovery bodies, exact bindings and whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_recovery_flow.swift").read_text()
    for name, methods in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        fixture += "@MainActor struct " + name + ": Host {\nlet context: Context\nlet input: Input\n" + "\n".join(methods) + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-recovery-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode,
                            *[str(repo / core) for core in CORES], str(source), "-o", str(binary)],
                           check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__":
    main()

