#!/usr/bin/env python3
"""Verify Aura progress/deadline and step flow against public code with a virtual clock."""
from pathlib import Path
import subprocess
import tempfile
import textwrap

from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

PROGRESS = "lara/EagleCore/AuraStudio/EagleAuraStudioStepProgress.swift"
FLOW = "lara/EagleCore/AuraStudio/EagleAuraStudioStepFlow.swift"
BEGIN = '''            guard let step = EagleAuraStudioStepFlow.begin(
                index: index,
                steps: steps,
                operationID: operationID,
                readOperationID: { activeOperationID },
                readApplying: { isApplying },
                writeStepIndex: { operationStepIndex = $0 },
                writeStage: { applyStage = $0 },
                localizedText: { LaraL10n.text(en: $0, es: $1) },
                log: { AuraStudioDiagnostics.log($0, $1) },
                complete: { completeSuccess() }
            ) else { return }'''
NATIVE = '''                EagleAuraStudioStepFlow.nativeStarted(
                    operationID: operationID,
                    step: step,
                    operation: operation,
                    targetPID: targetPID,
                    writeStage: { applyStage = $0 },
                    localizedText: { LaraL10n.text(en: $0, es: $1) },
                    log: { AuraStudioDiagnostics.log($0, $1) }
                )'''
PROGRESS_INIT = '''                let progress = EagleAuraStudioStepProgress(
                    operationID: operationID,
                    step: step,
                    readOperationID: { activeOperationID },
                    readApplying: { isApplying },
                    readFinished: { nativeFinished },
                    writeStage: { applyStage = $0 },
                    writeDeadlineExceeded: { hardDeadlineExceeded = $0 },
                    localizedText: { LaraL10n.text(en: $0, es: $1) },
                    log: { AuraStudioDiagnostics.log($0, $1) },
                    quarantine: { mgr.quarantineRemoteCall(reason: $0) },
                    writeSafetyBlocked: { applySafetyBlocked = $0 },
                    lockGate: { AuraStudioApplyGate.lock() }
                )'''
ADVANCE = '''EagleAuraStudioStepFlow.advance(
    index: index,
    deadlineExceeded: hardDeadlineExceeded,
    complete: { completeSuccess(deadlineWarning: $0) },
    runNext: { runStep($0) }
)'''
OLD_ADVANCE = '''if hardDeadlineExceeded {
    completeSuccess(deadlineWarning: true)
} else {
    runStep(index + 1)
}'''
PROGRESS_PREFIX = '''import Foundation

/// Progress and deadline effects for one step. Scheduling and cancellation stay with the caller.
@MainActor
struct EagleAuraStudioStepProgress {
    let operationID: String
    let step: EagleAuraStudioOperationStep
    let readOperationID: () -> String?
    let readApplying: () -> Bool
    let readFinished: () -> Bool
    let writeStage: (String) -> Void
    let writeDeadlineExceeded: (Bool) -> Void
    let localizedText: (String, String) -> String
    let log: (String, String) -> Void
    let quarantine: (String) -> Void
    let writeSafetyBlocked: (Bool) -> Void
    let lockGate: () -> Void
'''
FLOW_PREFIX = '''import Foundation

/// Step selection, progress presentation and continuation; native work remains caller-owned.
@MainActor
enum EagleAuraStudioStepFlow {
'''
BEGIN_SIGNATURE = '''    static func begin(
        index: Int,
        steps: [EagleAuraStudioOperationStep],
        operationID: String,
        readOperationID: () -> String?,
        readApplying: () -> Bool,
        writeStepIndex: (Int) -> Void,
        writeStage: (String) -> Void,
        localizedText: (String, String) -> String,
        log: (String, String) -> Void,
        complete: () -> Void
    ) -> EagleAuraStudioOperationStep? {'''
NATIVE_SIGNATURE = '''    static func nativeStarted(
        operationID: String,
        step: EagleAuraStudioOperationStep,
        operation: EagleAuraStudioOperation,
        targetPID: Int32,
        writeStage: (String) -> Void,
        localizedText: (String, String) -> String,
        log: (String, String) -> Void
    ) {'''
ADVANCE_SIGNATURE = '''    static func advance(
        index: Int,
        deadlineExceeded: Bool,
        complete: (Bool) -> Void,
        runNext: (Int) -> Void
    ) {'''


def originals():
    source = public_file()
    a = source.index("        func runStep(_ index: Int) {")
    a = source.index("            guard activeOperationID", a)
    b = source.index("\n            mgr.prepareFreshRemoteCall(", a)
    c = source.index("                applyStage = LaraL10n.text(\n                    en: operation.isRemoving", b)
    d = source.index("\n                let started = Date()", c)
    e = source.index("                let softProgressWork = DispatchWorkItem {", d)
    f = source.index("\n\n                DispatchQueue.global", e)
    return source[a:b], source[c:d], source[e:f]


def schedule_bridge():
    source = originals()[2]
    for name, method in (("softProgressWork", "reportProgress"), ("hardDeadlineWork", "deadlineReached")):
        marker = f"                let {name} = DispatchWorkItem {{"
        source = replace_once(source, declaration(source, marker), marker + f"\n                    progress.{method}()\n                }}")
    return PROGRESS_INIT + "\n" + source


def changes():
    begin, native, schedule = originals()
    return [(begin, BEGIN, 1), (native, NATIVE, 1), (schedule, schedule_bridge(), 1),
            *[(textwrap.indent(OLD_ADVANCE, " " * indent), textwrap.indent(ADVANCE, " " * indent), count)
              for indent, count in ((28, 3), (24, 1))]]


def replace_exact_lines(source, before, after, count):
    # The two continuation indent levels share suffixes; include a newline boundary.
    before, after = "\n" + before, "\n" + after
    assert source.count(before) == count, (before, source.count(before), count)
    return source.replace(before, after)


def inline_step_lifecycle(view):
    from verify_eagle_aura_result_consumption import inline_result_consumption
    view = inline_result_consumption(view)
    for before, after, count in changes():
        view = replace_exact_lines(view, after, before, count)
    return view


def body(text):
    return textwrap.indent(textwrap.dedent(text), "        ")


def presentation(source):
    source = replace_once(source, "applyStage = LaraL10n.text(", "writeStage(localizedText(")
    source = replace_once(source, "en: ", "")
    source = replace_once(source, "es: ", "")
    source = source.replace("AuraStudioDiagnostics.log(", "log(")
    # Close the additional writeStage call, preserving all actual string content.
    source = replace_once(source, "        )\n        log(", "        ))\n        log(")
    return source


def expected_sources():
    begin, native, schedule = originals()
    begin = body(begin)
    begin = replace_once(begin, "activeOperationID", "readOperationID()")
    begin = replace_once(begin, "isApplying", "readApplying()")
    assert begin.count("return") == 2
    begin = begin.replace("return", "return nil")
    begin = replace_once(begin, "completeSuccess()", "complete()")
    begin = replace_once(begin, "operationStepIndex = index + 1", "writeStepIndex(index + 1)")
    begin = presentation(begin) + "\n        return step"
    native = presentation(body(native))
    advance = body(OLD_ADVANCE).replace("hardDeadlineExceeded", "deadlineExceeded").replace("completeSuccess(deadlineWarning: true)", "complete(true)").replace("runStep(", "runNext(")
    flow = FLOW_PREFIX + BEGIN_SIGNATURE + "\n" + begin + "\n    }\n\n" + NATIVE_SIGNATURE + "\n" + native + "\n    }\n\n" + ADVANCE_SIGNATURE + "\n" + advance + "\n    }\n}\n"
    methods = []
    for name, method in (("softProgressWork", "reportProgress"), ("hardDeadlineWork", "deadlineReached")):
        block = declaration(schedule, f"                let {name} = DispatchWorkItem {{")
        value = body(block.split("{\n", 1)[1].rsplit("\n", 1)[0])
        for old, new in (("activeOperationID", "readOperationID()"), ("isApplying", "readApplying()"), ("!nativeFinished", "!readFinished()")):
            value = replace_once(value, old, new)
        if name == "softProgressWork":
            value = presentation(value)
        else:
            value = replace_once(value, "hardDeadlineExceeded = true", "writeDeadlineExceeded(true)")
            value = replace_once(value, "applyStage = LaraL10n.text(", "writeStage(localizedText(")
            value = replace_once(value, "en: ", "")
            value = replace_once(value, "es: ", "")
            value = replace_once(value, "        )\n        mgr.quarantineRemoteCall(reason: reason)", "        ))\n        quarantine(reason)")
            value = replace_once(value, "AuraStudioDiagnostics.log(", "log(")
            value = replace_once(value, "applySafetyBlocked = true", "writeSafetyBlocked(true)")
            value = replace_once(value, "AuraStudioApplyGate.lock()", "lockGate()")
        methods.append("    func " + method + "() {\n" + value + "\n    }")
    progress = PROGRESS_PREFIX + "\n" + "\n\n".join(methods) + "\n}\n"
    return progress, flow


def verify_texts(view, progress, flow, schedule=None):
    from verify_eagle_aura_request_preparation import verify_texts as verify_preparation, CORE as PREPARATION
    repo = Path(__file__).resolve().parents[1]
    verify_preparation(view, (repo / PREPARATION).read_text())
    assert (progress, flow) == expected_sources(), "Progress/deadline or step flow diverged from public code"
    from verify_eagle_aura_progress_scheduling import verify_sources, CORE, ADAPTER
    verify_sources(schedule if schedule is not None else (repo / CORE).read_text(), (repo / ADAPTER).read_text())


def main():
    repo = Path(__file__).resolve().parents[1]
    import verify_eagle_aura_progress_scheduling as scheduling
    values = [(repo / path).read_text() for path in (VIEW, PROGRESS, FLOW, scheduling.CORE)]
    verify_texts(*values)
    for index, before, after in [
        (3, "scheduleAfter(10, softProgressWork)", "scheduleAfter(9, softProgressWork)"),
        (3, "scheduleAfter(60, hardDeadlineWork)", "scheduleAfter(59, hardDeadlineWork)"),
        (3, "progress.reportProgress()", "progress.deadlineReached()"),
        (0, "writeDeadlineExceeded: { hardDeadlineExceeded = $0 }", "writeDeadlineExceeded: { hardDeadlineExceeded = false }"),
        (0, "readDeadlineExceeded: { hardDeadlineExceeded }", "readDeadlineExceeded: { false }"),
        (1, "!readFinished()", "readFinished()"),
        (1, "writeDeadlineExceeded(true)", "writeDeadlineExceeded(false)"),
        (1, "        lockGate()", "        // lockGate()"),
        (2, "index < steps.count", "index <= steps.count"),
        (2, "writeStepIndex(index + 1)", "writeStepIndex(index)"),
        (2, "if deadlineExceeded", "if !deadlineExceeded"),
        (2, "runNext(index + 1)", "runNext(index)"),
    ]:
        mutated = values.copy()
        assert before in mutated[index]
        mutated[index] = mutated[index].replace(before, after, 1)
        try:
            verify_texts(*mutated)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    from verify_eagle_aura_result_admission import BRIDGE as RESULT_BRIDGE, original as public_result, CORE as RESULT_CORE
    fixture = (repo / "scripts/verify_eagle_aura_step_lifecycle.swift").read_text()
    old_begin, old_native, old_schedule = originals()
    for name, owned in (("PublicHost", False), ("OwnedHost", True)):
        fixture += "\n@MainActor struct " + name + ": Host { let context: Context\n"
        fixture += "func begin(index: Int, steps: [EagleAuraStudioOperationStep], operationID: String) {\n" + (BEGIN if owned else old_begin) + '\ncontext.events.append("selected.\\(step.flag)")\n}\n'
        fixture += "func start(operationID: String, step: EagleAuraStudioOperationStep, operation: EagleAuraStudioOperation, targetPID: Int32) {\n" + (NATIVE if owned else old_native) + "\n" + (scheduling.schedule_bridge() if owned else old_schedule)
        fixture += ("\ncontext.progressSchedule = progressSchedule\ncontext.soft = context.jobs[0].1\ncontext.hard = context.jobs[1].1" if owned else "\ncontext.soft = softProgressWork\ncontext.hard = hardDeadlineWork") + "\n}\n"
        fixture += "func advance(index: Int) {\n" + (ADVANCE if owned else OLD_ADVANCE) + "\n}\n"
        fixture += "func receive(process: Session, processError: String?, result: Int32, operationID: String, operationSpringBoardPID: Int32, targetPID: Int32, springBoardPID: Int32, step: EagleAuraStudioOperationStep) {\n"
        fixture += (scheduling.result_bridge() if owned else public_result())
        fixture += '\ncontext.events.append("result.accepted.\\(result)")\ncontext.consumed += 1\nadvance(index: 0)\n}\n}\n'
    with tempfile.TemporaryDirectory(prefix="eagle-aura-step-lifecycle-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in (("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])):
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                *[str(repo / path) for path in (PROGRESS, FLOW, RESULT_CORE, scheduling.CORE, scheduling.ADAPTER,
                  "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift", "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift")],
                str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: exact public progress, deadlines, all four continuations and full screen; 12 rejected mutations")


if __name__ == "__main__":
    main()
