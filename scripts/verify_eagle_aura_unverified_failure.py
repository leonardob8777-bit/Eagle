#!/usr/bin/env python3
"""Public fail-closed Aura state/presentation parity; native effects are recorded, never executed."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioUnverifiedFailure.swift"
MARKER = "func failAfterNativeCall("
BRIDGE = "func failAfterNativeCall(\n            _ reason: String,\n            result: Int32? = nil,\n            userDetail: String? = nil\n        ) {\n            EagleAuraStudioUnverifiedFailure(\n                operationID: operationID,\n                retainedVerified: retainedVerified,\n                newlyApplied: newlyApplied,\n                removedFlags: removedFlags,\n                islandFlag: Flag.island,\n                dockFlag: Flag.dock,\n                targetTitle: { operationTarget.title },\n                writeActiveFlags: { activeFlagsRaw = $0 },\n                readActiveFlags: { activeFlagsRaw },\n                writeActiveMode: { activeModeRaw = $0 },\n                writeIslandMode: { activeIslandModeRaw = $0 },\n                writeDockMode: { activeDockModeRaw = $0 },\n                writeSpringBoardPID: { activeSpringBoardPID = $0 },\n                currentSpringBoardPID: { \"SpringBoard\".withCString { find_process_pid($0) } },\n                quarantine: { mgr.quarantineRemoteCall(reason: $0) },\n                writeSafetyBlocked: { applySafetyBlocked = $0 },\n                lockGate: { AuraStudioApplyGate.lock() },\n                log: { AuraStudioDiagnostics.log($0, $1) },\n                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },\n                resetOperationUI: { resetOperationUI() },\n                localizedText: { LaraL10n.text(en: $0, es: $1) },\n                showNotice: { notice = AuraStudioNotice(message: $0) }\n            ).failAfterNativeCall(reason, result: result, userDetail: userDetail)\n        }"
PREFIX = "import Foundation\n\n/// Fail-closed presentation/state coordination after the caller reports an unverified outcome.\n/// Native verification, quarantine implementation and session ownership stay injected.\n@MainActor\nstruct EagleAuraStudioUnverifiedFailure {\n    let operationID: String\n    let retainedVerified: UInt32\n    let newlyApplied: UInt32\n    let removedFlags: UInt32\n    let islandFlag: UInt32\n    let dockFlag: UInt32\n    let targetTitle: () -> String\n    let writeActiveFlags: (Int) -> Void\n    let readActiveFlags: () -> Int\n    let writeActiveMode: (Int) -> Void\n    let writeIslandMode: (Int) -> Void\n    let writeDockMode: (Int) -> Void\n    let writeSpringBoardPID: (Int) -> Void\n    let currentSpringBoardPID: () -> Int32\n    let quarantine: (String) -> Void\n    let writeSafetyBlocked: (Bool) -> Void\n    let lockGate: () -> Void\n    let log: (String, String) -> Void\n    let recordDiagnostics: (String) -> Void\n    let resetOperationUI: () -> Void\n    let localizedText: (String, String) -> String\n    let showNotice: (String) -> Void\n\n    "
SUBSTITUTIONS = [["AuraStudioDiagnostics.log(","log(",1],["activeFlagsRaw = Int(retainedVerified | newlyApplied)","writeActiveFlags(Int(retainedVerified | newlyApplied))",1],["activeFlagsRaw","readActiveFlags()",3],["Flag.island","islandFlag",1],["Flag.dock","dockFlag",1],["activeModeRaw = 0","writeActiveMode(0)",1],["activeIslandModeRaw = 0","writeIslandMode(0)",1],["activeDockModeRaw = 0","writeDockMode(0)",1],["activeSpringBoardPID = Int(\n                \"SpringBoard\".withCString { find_process_pid($0) }\n            )","writeSpringBoardPID(Int(currentSpringBoardPID()))",1],["activeSpringBoardPID = 0","writeSpringBoardPID(0)",1],["mgr.quarantineRemoteCall(reason: reason)","quarantine(reason)",1],["applySafetyBlocked = true","writeSafetyBlocked(true)",1],["AuraStudioApplyGate.lock()","lockGate()",1],["diagnosticsURL = makeDiagnosticsReport(summary: reason)","recordDiagnostics(reason)",1],["LaraL10n.text(","localizedText(",1],["en: \"","\"",1],["es: \"","\"",1],["operationTarget.title","targetTitle()",2],["notice = AuraStudioNotice(message: baseMessage + detailSuffix)","showNotice(baseMessage + detailSuffix)",1]]

def original():
    return declaration(public_file(), MARKER)

def inline_unverified_failure(view):
    from verify_eagle_aura_diagnostics_report import inline_diagnostics_report
    view = inline_diagnostics_report(view)
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
    assert restored == public_file(), "Native guards/calls or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Fail-closed state/presentation sequence changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "readActiveFlags: { activeFlagsRaw }", "readActiveFlags: { 33 }"),
        (0, "quarantine: { mgr.quarantineRemoteCall(reason: $0) }", "quarantine: { _ in }"),
        (0, "writeSafetyBlocked: { applySafetyBlocked = $0 }", "writeSafetyBlocked: { applySafetyBlocked = false }"),
        (0, "lockGate: { AuraStudioApplyGate.lock() }", "lockGate: { AuraStudioApplyGate.end() }"),
        (0, 'currentSpringBoardPID: { "SpringBoard".withCString { find_process_pid($0) } }', "currentSpringBoardPID: { 0 }"),
        (0, "writeIslandMode: { activeIslandModeRaw = $0 }", "writeIslandMode: { activeDockModeRaw = $0 }"),
        (0, "beginGate: { AuraStudioApplyGate.begin() }", "beginGate: { true }"),
        (1, "retainedVerified | newlyApplied", "retainedVerified & newlyApplied"),
        (1, "readActiveFlags() == 0", "readActiveFlags() != 0"),
        (1, "writeSafetyBlocked(true)", "writeSafetyBlocked(false)"),
        (1, "quarantine(reason)", ""),
        (1, "lockGate()", ""),
        (1, "writeIslandMode(0)", ""),
        (1, "writeDockMode(0)", ""),
        (1, "recordDiagnostics(reason)\n        resetOperationUI()", "resetOperationUI()\n        recordDiagnostics(reason)"),
        (1, "baseMessage + detailSuffix", "baseMessage"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in BRIDGE:
            texts[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try: verify_texts(*texts)
        except AssertionError: continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: entire public unverified-failure body, exact bindings and whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_unverified_failure.swift").read_text()
    fields = ["activeModeRaw", "activeIslandModeRaw", "activeDockModeRaw", "activeSpringBoardPID"]
    fixture += "\nextension Host {\n"
    for name in fields:
        fixture += f'var {name}: Int {{ get {{ context.fields["{name}"]! }} nonmutating set {{ context.fields["{name}"] = newValue; context.events.append("write.{name}:\\(newValue)") }} }}\n'
    fixture += "}\n"
    for name, method in (("PublicHost", original()), ("OwnedHost", BRIDGE)):
        fixture += "@MainActor struct " + name + ": Host {\nlet context: Context\nlet input: Input\n" + method + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-unverified-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__": main()

