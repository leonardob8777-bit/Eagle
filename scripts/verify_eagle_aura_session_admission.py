#!/usr/bin/env python3
"""Compare generic session admission with the frozen public callback; no native code runs."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioSessionAdmission.swift"
BRIDGE = '''                guard let admitted = EagleAuraStudioSessionAdmission(
                    readOperationID: { activeOperationID },
                    readApplying: { isApplying },
                    readPID: { $0.pid },
                    readIsolated: { $0.creatingExtraThread },
                    currentPID: { "SpringBoard".withCString { find_process_pid($0) } },
                    beginExclusive: { mgr.beginExclusiveRemoteCall(label: $0, expectedSession: $1) },
                    readRetained: { retainedVerified },
                    writeRetained: { retainedVerified = $0 },
                    writeNewlyApplied: { newlyApplied = $0 },
                    writeActiveFlags: { activeFlagsRaw = $0 },
                    writeActiveMode: { activeModeRaw = $0 },
                    writeIslandMode: { activeIslandModeRaw = $0 },
                    writeDockMode: { activeDockModeRaw = $0 },
                    writeSpringBoardPID: { activeSpringBoardPID = $0 },
                    failBefore: { failBeforeNativeCall($0) },
                    failAfter: { failAfterNativeCall($0) }
                ).admit(
                    process: process,
                    sessionError: sessionError,
                    operationID: operationID,
                    operationSpringBoardPID: operationSpringBoardPID,
                    stepFlag: step.flag,
                    stepEnglishName: step.englishName
                ) else { return }
                let process = admitted.process
                let targetPID = admitted.targetPID'''
PREFIX = '''import Foundation

/// Validates a prepared handle without owning or creating a native session.
@MainActor
struct EagleAuraStudioAdmittedSession<Session> {
    let process: Session
    let targetPID: Int32
}

@MainActor
struct EagleAuraStudioSessionAdmission<Session> {
    let readOperationID: () -> String?
    let readApplying: () -> Bool
    let readPID: (Session) -> Int32
    let readIsolated: (Session) -> Bool
    let currentPID: () -> Int32
    let beginExclusive: (String, Session) -> Bool
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let writeNewlyApplied: (UInt32) -> Void
    let writeActiveFlags: (Int) -> Void
    let writeActiveMode: (Int) -> Void
    let writeIslandMode: (Int) -> Void
    let writeDockMode: (Int) -> Void
    let writeSpringBoardPID: (Int) -> Void
    let failBefore: (String) -> Void
    let failAfter: (String) -> Void

    func admit(
        process: Session?,
        sessionError: String?,
        operationID: String,
        operationSpringBoardPID: Int32,
        stepFlag: UInt32,
        stepEnglishName: String
    ) -> EagleAuraStudioAdmittedSession<Session>? {
'''


def original():
    source = public_file()
    start = source.index("                guard activeOperationID == operationID, isApplying else { return }\n                guard let process else {")
    end = source.index("\n\n                applyStage = LaraL10n.text(", start)
    return source[start:end]


def inline_session_admission(view):
    from verify_eagle_aura_result_admission import inline_result_admission
    view = inline_result_admission(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    source = "\n".join(line[8:] if line.startswith("        ") else line for line in original().splitlines())
    changes = [
        ("activeOperationID", "readOperationID()", 1),
        ("isApplying", "readApplying()", 1),
        ("return", "return nil", 5),
        ("process.pid", "readPID(process)", 1),
        ('"SpringBoard".withCString { find_process_pid($0) }', "currentPID()", 1),
        ("process.creatingExtraThread", "readIsolated(process)", 2),
        ("failBeforeNativeCall", "failBefore", 3),
        ("failAfterNativeCall", "failAfter", 2),
        ("retainedVerified &= ~step.flag", "writeRetained(readRetained() & ~stepFlag)", 1),
        ("step.englishName", "stepEnglishName", 3),
        ('''mgr.beginExclusiveRemoteCall(
            label: "Aura \\(stepEnglishName) \\(operationID)", expectedSession: process
        )''', '''beginExclusive("Aura \\(stepEnglishName) \\(operationID)", process)''', 1),
        *[(old + " = 0", new + "(0)", 1) for old, new in (
            ("retainedVerified", "writeRetained"), ("newlyApplied", "writeNewlyApplied"),
            ("activeFlagsRaw", "writeActiveFlags"), ("activeModeRaw", "writeActiveMode"),
            ("activeIslandModeRaw", "writeIslandMode"), ("activeDockModeRaw", "writeDockMode"),
            ("activeSpringBoardPID", "writeSpringBoardPID"))],
    ]
    for before, after, count in changes:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n        return EagleAuraStudioAdmittedSession(process: process, targetPID: targetPID)\n    }\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_request_preparation import verify_texts as verify_preparation, CORE as PREPARATION
    repo = Path(__file__).resolve().parents[1]
    # This recursively reconstructs the complete public screen, not just this block.
    verify_preparation(view, (repo / PREPARATION).read_text())
    assert core == expected_core(), "Session guard ordering, state writes, failure classification or handle changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "readOperationID: { activeOperationID }", "readOperationID: { operationID }"),
        (0, "readApplying: { isApplying }", "readApplying: { true }"),
        (0, "writeDockMode: { activeDockModeRaw = $0 }", "writeDockMode: { activeIslandModeRaw = $0 }"),
        (0, "expectedSession: $1", "expectedSession: process!"),
        (0, "stepFlag: step.flag", "stepFlag: 0"),
        (1, "targetPID > 0", "targetPID >= 0"),
        (1, "currentPID == targetPID", "currentPID != targetPID"),
        (1, "readApplying()", "true"),
        (1, "~stepFlag", "stepFlag"),
        (1, '"safety locked"', '"safety unlocked"'),
        (1, "writeNewlyApplied(0)", "writeNewlyApplied(1)"),
        (1, "targetPID == operationSpringBoardPID", "true"),
        (1, "targetPID: targetPID", "targetPID: operationSpringBoardPID"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            # Some expressions repeat; replace only the first to exercise exact rejection.
            assert before in core, before
            values[1] = core.replace(before, after, 1)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_session_admission.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host { let context: Context\ninit(_ context: Context) { self.context = context }\n"
        fixture += "func consume(process: Session?, sessionError: String?, operationID: String, operationSpringBoardPID: Int32, step: Step) {\n" + body
        fixture += '\ncontext.events.append("admitted.\\(process.token).\\(targetPID)")\ncontext.admitted = process\ncontext.admittedPID = targetPID\n}\n}\n'
    with tempfile.TemporaryDirectory(prefix="eagle-aura-session-") as temporary:
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
    print("PASS: public session admission, exact screen/native continuation, thirteen rejected mutations", flush=True)


if __name__ == "__main__":
    main()
