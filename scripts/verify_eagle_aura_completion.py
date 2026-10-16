#!/usr/bin/env python3
"""Compare complete Aura completion sequencing against actual public source."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioCompletion.swift"
MARKER = "func completeSuccess("
BRIDGE = "func completeSuccess(deadlineWarning: Bool = false) {\n            EagleAuraStudioCompletion(\n                retainedVerified: retainedVerified,\n                newlyApplied: newlyApplied,\n                removedFlags: removedFlags,\n                requestedFlags: requestedFlags,\n                operationIsRemoving: operation.isRemoving,\n                operationSpringBoardPID: operationSpringBoardPID,\n                operationID: operationID,\n                mode: mode,\n                motionDegraded: motionDegraded,\n                firstUnavailableResult: firstUnavailableResult,\n                verifiedFallbackResult: verifiedFallbackResult,\n                writeActiveFlags: { activeFlagsRaw = $0 },\n                readIslandMode: { activeIslandModeRaw },\n                writeActiveMode: { activeModeRaw = $0 },\n                writeIslandMode: { activeIslandModeRaw = $0 },\n                writeDockMode: { activeDockModeRaw = $0 },\n                writeSpringBoardPID: { activeSpringBoardPID = $0 },\n                log: { AuraStudioDiagnostics.log($0, $1) },\n                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },\n                resetOperationUI: { resetOperationUI() },\n                endGate: { AuraStudioApplyGate.end() },\n                errorMessage: { message(for: $0) },\n                successMessage: {\n                    successMessage(\n                        appliedFlags: $0, requestedFlags: $1, restoring: $2,\n                        motionDegraded: $3, appliedMode: $4\n                    )\n                },\n                localizedText: { LaraL10n.text(en: $0, es: $1) },\n                informationKind: EagleNoticeKind.information,\n                errorKind: EagleNoticeKind.error,\n                successKind: EagleNoticeKind.success,\n                showNotification: { EagleNotifications.shared.show(title: $0, message: $1, kind: $2) }\n            ).completeSuccess(deadlineWarning: deadlineWarning)\n        }"
PREFIX = "import Foundation\n\n/// Commits presentation state after the caller has classified native outcomes.\n/// Does not execute, verify, retry or unlock native operations.\n@MainActor\nstruct EagleAuraStudioCompletion<NoticeKind> {\n    let retainedVerified: UInt32\n    let newlyApplied: UInt32\n    let removedFlags: UInt32\n    let requestedFlags: UInt32\n    let operationIsRemoving: Bool\n    let operationSpringBoardPID: Int32\n    let operationID: String\n    let mode: Int\n    let motionDegraded: Bool\n    let firstUnavailableResult: Int32?\n    let verifiedFallbackResult: Int32?\n    let writeActiveFlags: (Int) -> Void\n    let readIslandMode: () -> Int\n    let writeActiveMode: (Int) -> Void\n    let writeIslandMode: (Int) -> Void\n    let writeDockMode: (Int) -> Void\n    let writeSpringBoardPID: (Int) -> Void\n    let log: (String, String) -> Void\n    let recordDiagnostics: (String) -> Void\n    let resetOperationUI: () -> Void\n    let endGate: () -> Void\n    let errorMessage: (Int32) -> String\n    let successMessage: (UInt32, UInt32, Bool, Bool, EagleAuraStudioMode?) -> String\n    let localizedText: (String, String) -> String\n    let informationKind: NoticeKind\n    let errorKind: NoticeKind\n    let successKind: NoticeKind\n    let showNotification: (String, String, NoticeKind) -> Void\n\n    "
SUBSTITUTIONS = [["activeFlagsRaw = Int(finalFlags)","writeActiveFlags(Int(finalFlags))",1],["activeModeRaw = activeIslandModeRaw","writeActiveMode(readIslandMode())",1],["activeSpringBoardPID = 0","writeSpringBoardPID(0)",1],["activeModeRaw = 0","writeActiveMode(0)",1],["activeIslandModeRaw = 0","writeIslandMode(0)",1],["activeDockModeRaw = 0","writeDockMode(0)",1],["activeSpringBoardPID = Int(operationSpringBoardPID)","writeSpringBoardPID(Int(operationSpringBoardPID))",1],["operation.isRemoving","operationIsRemoving",7],["AuraStudioDiagnostics.log(","log(",1],["diagnosticsURL = makeDiagnosticsReport(summary: diagnosticsSummary)","recordDiagnostics(diagnosticsSummary)",1],["AuraStudioApplyGate.end()","endGate()",1],["message(for: ","errorMessage(",2],["appliedFlags: ","",1],["requestedFlags: ","",1],["restoring: ","",1],["motionDegraded: ","",1],["appliedMode: ","",1],["AuraStudioMode(rawValue:","EagleAuraStudioMode(rawValue:",1],["LaraL10n.text(","localizedText(",1],["en: \"","\"",1],["es: \"","\"",1],["let kind: EagleNoticeKind","let kind: NoticeKind",1],["? .information","? informationKind",1],["? .error : .success","? errorKind : successKind",1],["EagleNotifications.shared.show(title: \"Aura Studio\", message: resultMessage, kind: kind)","showNotification(\"Aura Studio\", resultMessage, kind)",1]]

def original():
    return declaration(public_file(), MARKER)

def inline_completion(view):
    from verify_eagle_aura_recovery_flow import inline_recovery_flow
    view = inline_recovery_flow(view)
    return replace_once(view, BRIDGE, original())

def expected_core():
    source = "\n".join(line[4:] if index else line for index, line in enumerate(original().split("\n")))
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated native/UI/callback boundary changed"
    assert compact(core) == compact(expected_core()), "Completion decisions or sequencing changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "retainedVerified: retainedVerified", "retainedVerified: 0"),
        (0, "newlyApplied: newlyApplied", "newlyApplied: removedFlags"),
        (0, "readIslandMode: { activeIslandModeRaw }", "readIslandMode: { activeDockModeRaw }"),
        (0, "writeDockMode: { activeDockModeRaw = $0 }", "writeDockMode: { activeIslandModeRaw = $0 }"),
        (0, "endGate: { AuraStudioApplyGate.end() }", "endGate: {}"),
        (0, "errorKind: EagleNoticeKind.error", "errorKind: EagleNoticeKind.success"),
        (0, "beginGate: { AuraStudioApplyGate.begin() }", "beginGate: { true }"),
        (1, "retainedVerified | newlyApplied", "retainedVerified & newlyApplied"),
        (1, "if finalFlags == 0", "if finalFlags != 0"),
        (1, "if !deadlineWarning", "if deadlineWarning"),
        (1, "if let verifiedFallbackResult", "if let verifiedFallbackResult = firstUnavailableResult"),
        (1, "errorMessage(firstUnavailableResult)", "errorMessage(0)"),
        (1, "writeActiveMode(readIslandMode())", "writeActiveMode(0)"),
        (1, "resetOperationUI()\n        if", "if"),
        (1, "deadlineWarning || motionDegraded || verifiedFallbackResult != nil",
             "deadlineWarning || motionDegraded"),
        (1, "showNotification(\"Aura Studio\", resultMessage, kind)", "showNotification(\"Aura Studio\", \"\", kind)"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in BRIDGE:
            texts[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: full public completion body and whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_completion.swift").read_text()
    fields = ["activeFlagsRaw", "activeModeRaw", "activeIslandModeRaw", "activeDockModeRaw", "activeSpringBoardPID"]
    fixture += "\nextension Host {\n"
    for name in fields:
        fixture += f'var {name}: Int {{ get {{ context.read("{name}") }} nonmutating set {{ context.write("{name}", newValue) }} }}\n'
    fixture += 'var diagnosticsURL: URL? { get { context.url } nonmutating set { context.url = newValue; context.events.append("write.report:" + (newValue?.absoluteString ?? "nil")) } }\n}\n'
    for name, method in (("PublicHost", original()), ("OwnedHost", BRIDGE)):
        fixture += "@MainActor struct " + name + ": Host {\nlet context: Context\nlet input: Input\n" + method + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-completion-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__":
    main()

