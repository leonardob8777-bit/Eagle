#!/usr/bin/env python3
"""Verify late/invalid result rejection without running native code or timers."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioResultAdmission.swift"
BRIDGE = '''                        guard EagleAuraStudioResultAdmission(
                            currentPID: { "SpringBoard".withCString { find_process_pid($0) } },
                            readOperationID: { activeOperationID },
                            readApplying: { isApplying },
                            readFinished: { nativeFinished },
                            writeFinished: { nativeFinished = $0 },
                            cancelSoftProgress: { softProgressWork.cancel() },
                            cancelHardDeadline: { hardDeadlineWork.cancel() },
                            endExclusive: { mgr.endExclusiveRemoteCall(label: $0) },
                            log: { AuraStudioDiagnostics.log($0, $1) },
                            writeActiveFlags: { activeFlagsRaw = $0 },
                            writeActiveMode: { activeModeRaw = $0 },
                            writeIslandMode: { activeIslandModeRaw = $0 },
                            writeDockMode: { activeDockModeRaw = $0 },
                            writeSpringBoardPID: { activeSpringBoardPID = $0 },
                            readRetained: { retainedVerified },
                            writeRetained: { retainedVerified = $0 },
                            writeNewlyApplied: { newlyApplied = $0 },
                            readHealthy: { process.isHealthy },
                            readTimedOut: { process.lastCallTimedOut },
                            localizedText: { LaraL10n.text(en: $0, es: $1) },
                            failAfter: { failAfterNativeCall($0, result: $1, userDetail: $2) }
                        ).admit(
                            result: result,
                            processError: processError,
                            operationID: operationID,
                            operationSpringBoardPID: operationSpringBoardPID,
                            targetPID: targetPID,
                            springBoardPID: springBoardPID,
                            stepFlag: step.flag,
                            stepEnglishName: step.englishName,
                            stepSpanishName: step.spanishName
                        ) else { return }'''
PREFIX = '''import Foundation

/// Decides whether an existing result may be consumed; native calls and timers remain caller-owned.
@MainActor
struct EagleAuraStudioResultAdmission {
    let currentPID: () -> Int32
    let readOperationID: () -> String?
    let readApplying: () -> Bool
    let readFinished: () -> Bool
    let writeFinished: (Bool) -> Void
    let cancelSoftProgress: () -> Void
    let cancelHardDeadline: () -> Void
    let endExclusive: (String) -> Void
    let log: (String, String) -> Void
    let writeActiveFlags: (Int) -> Void
    let writeActiveMode: (Int) -> Void
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let writeNewlyApplied: (UInt32) -> Void
    let readHealthy: () -> Bool
    let readTimedOut: () -> Bool
    let localizedText: (String, String) -> String
    let failAfter: (String, Int32, String?) -> Void

    func admit(
        result: Int32,
        processError: String?,
        operationID: String,
        operationSpringBoardPID: Int32,
        targetPID: Int32,
        springBoardPID: Int32,
        stepFlag: UInt32,
        stepEnglishName: String,
        stepSpanishName: String
    ) -> Bool {
'''


def original():
    source = public_file()
    start = source.index('                        let liveSpringBoardPID = "SpringBoard".withCString {')
    end = source.index("\n                        if operation.isRemoving {", start)
    return source[start:end]


def inline_result_admission(view):
    from verify_eagle_aura_step_lifecycle import inline_step_lifecycle
    view = inline_step_lifecycle(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    source = "\n".join(line[16:] if line.startswith("                ") else line for line in original().splitlines())
    changes = [
        ('''"SpringBoard".withCString {
            find_process_pid($0)
        }''', "currentPID()", 1),
        ("activeOperationID", "readOperationID()", 1),
        ("isApplying", "readApplying()", 1),
        ("!nativeFinished", "!readFinished()", 1),
        ("nativeFinished = true", "writeFinished(true)", 1),
        ("softProgressWork.cancel()", "cancelSoftProgress()", 1),
        ("hardDeadlineWork.cancel()", "cancelHardDeadline()", 1),
        ("AuraStudioDiagnostics.log", "log", 1),
        ("step.englishName", "stepEnglishName", 6),
        ("step.spanishName", "stepSpanishName", 1),
        ('''mgr.endExclusiveRemoteCall(
                label: "Aura \\(stepEnglishName) \\(operationID)"
            )''', '''endExclusive("Aura \\(stepEnglishName) \\(operationID)")''', 1),
        ('''mgr.endExclusiveRemoteCall(
            label: "Aura \\(stepEnglishName) \\(operationID)"
        )''', '''endExclusive("Aura \\(stepEnglishName) \\(operationID)")''', 1),
        *[(old + " = 0", new + "(0)", count) for old, new, count in (
            ("activeFlagsRaw", "writeActiveFlags", 2), ("activeModeRaw", "writeActiveMode", 2),
            ("activeIslandModeRaw", "writeIslandMode", 2), ("activeDockModeRaw", "writeDockMode", 2),
            ("activeSpringBoardPID", "writeSpringBoardPID", 2),
            ("retainedVerified", "writeRetained", 1), ("newlyApplied", "writeNewlyApplied", 1))],
        ("retainedVerified &= ~step.flag", "writeRetained(readRetained() & ~stepFlag)", 2),
        ("process.isHealthy", "readHealthy()", 1),
        ("process.lastCallTimedOut", "readTimedOut()", 2),
        ("failAfterNativeCall(", "failAfter(", 2),
        ("result: result\n", "result, nil\n", 1),
        ("result: result,\n", "result,\n", 1),
        ("userDetail: LaraL10n.text(\n                    en: ", "localizedText(\n                    ", 1),
        ('\n                    es: ', '\n                    ', 1),
        ("return", "return false", 3),
    ]
    for before, after, count in changes:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n        return true\n    }\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_request_preparation import verify_texts as verify_preparation, CORE as PREPARATION
    repo = Path(__file__).resolve().parents[1]
    verify_preparation(view, (repo / PREPARATION).read_text())
    assert core == expected_core(), "Late results, health/PID checks, cancellation, state writes or messages changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    from verify_eagle_aura_progress_scheduling import result_bridge
    actual_bridge = result_bridge()
    mutations = [
        (0, "readFinished: { nativeFinished }", "readFinished: { false }"),
        (0, "cancelSoftProgress: { progressSchedule.cancelSoftProgress() }", "cancelSoftProgress: {}"),
        (0, "readHealthy: { process.isHealthy }", "readHealthy: { true }"),
        (0, "springBoardPID: springBoardPID", "springBoardPID: targetPID"),
        (1, "!readFinished()", "readFinished()"),
        (1, "writeFinished(true)", "writeFinished(false)"),
        (1, "cancelHardDeadline()", "cancelSoftProgress()"),
        (1, "springBoardPID != targetPID", "springBoardPID == targetPID"),
        (1, "~stepFlag", "stepFlag"),
        (1, "!readHealthy()", "readHealthy()"),
        (1, "processError?.isEmpty == false", "processError?.isEmpty == true"),
        (1, "targetPID != operationSpringBoardPID", "false"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, actual_bridge, replace_once(actual_bridge, before, after))
        else:
            assert before in core, before
            values[1] = core.replace(before, after, 1)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_result_admission.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host { let context: Context\ninit(_ context: Context) { self.context = context }\n"
        fixture += "func consume(process: Session, processError: String?, result: Int32, operationID: String, operationSpringBoardPID: Int32, targetPID: Int32, springBoardPID: Int32, step: Step) {\n" + body
        fixture += '\ncontext.events.append("consume.\\(result)")\ncontext.consumed += 1\n}\n}\n'
    with tempfile.TemporaryDirectory(prefix="eagle-aura-result-admission-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in [("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])]:
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / CORE), str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: public result admission, unchanged continuation, twelve rejected mutations", flush=True)


if __name__ == "__main__":
    main()
