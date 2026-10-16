#!/usr/bin/env python3
"""Verify scheduling/cancellation extraction, actual bridges and Dispatch work semantics."""
from pathlib import Path
import subprocess
import tempfile
import textwrap

from verify_eagle_dock_apply_flow import replace_once
from verify_eagle_aura_result_feedback import VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioProgressSchedule.swift"
ADAPTER = "lara/EagleAdapters/AuraStudio/EagleAuraStudioProgressScheduler.swift"
BRIDGE = "                let progressSchedule = EagleAuraStudioProgressScheduler.start(progress: progress)"
PREFIX = """import Foundation

/// Owns the two progress jobs, not the native operation. Work creation and timing are injected.
@MainActor
struct EagleAuraStudioProgressSchedule<Work> {
    private let softProgressWork: Work
    private let hardDeadlineWork: Work
    private let cancel: (Work) -> Void

    static func start(
        progress: EagleAuraStudioStepProgress,
        makeWork: (@escaping @MainActor () -> Void) -> Work,
        scheduleAfter: (Int, Work) -> Void,
        cancel: @escaping (Work) -> Void
    ) -> Self {
"""
SUFFIX = """        return Self(
            softProgressWork: softProgressWork,
            hardDeadlineWork: hardDeadlineWork,
            cancel: cancel
        )
    }

    func cancelSoftProgress() {
        cancel(softProgressWork)
    }

    func cancelHardDeadline() {
        cancel(hardDeadlineWork)
    }
}
"""
EXPECTED_ADAPTER = """import Foundation

/// Uses the same main queue and Dispatch work items as the public app; no Task hop or retry.
@MainActor
enum EagleAuraStudioProgressScheduler {
    static func start(
        progress: EagleAuraStudioStepProgress
    ) -> EagleAuraStudioProgressSchedule<DispatchWorkItem> {
        EagleAuraStudioProgressSchedule.start(
            progress: progress,
            makeWork: { action in
                DispatchWorkItem { action() }
            },
            scheduleAfter: { seconds, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: work)
            },
            cancel: { $0.cancel() }
        )
    }
}
"""
CANCELLATIONS = [
    ("cancelSoftProgress: { softProgressWork.cancel() }", "cancelSoftProgress: { progressSchedule.cancelSoftProgress() }"),
    ("cancelHardDeadline: { hardDeadlineWork.cancel() }", "cancelHardDeadline: { progressSchedule.cancelHardDeadline() }"),
]


def old_schedule():
    from verify_eagle_aura_step_lifecycle import PROGRESS_INIT, schedule_bridge
    return replace_once(schedule_bridge(), PROGRESS_INIT + "\n", "")


def schedule_bridge():
    from verify_eagle_aura_step_lifecycle import PROGRESS_INIT
    return PROGRESS_INIT + "\n" + BRIDGE


def result_bridge():
    from verify_eagle_aura_result_admission import BRIDGE
    for before, after in CANCELLATIONS:
        BRIDGE = replace_once(BRIDGE, before, after)
    return BRIDGE


def inline_progress_scheduling(view):
    view = replace_once(view, BRIDGE, old_schedule())
    for before, after in CANCELLATIONS:
        view = replace_once(view, after, before)
    return view


def expected_core():
    source = textwrap.indent(textwrap.dedent(old_schedule()), "        ")
    assert source.count("DispatchWorkItem {") == 2
    source = source.replace("DispatchWorkItem {", "makeWork {")
    for seconds, work in [(10, "softProgressWork"), (60, "hardDeadlineWork")]:
        before = f"""        DispatchQueue.main.asyncAfter(
            deadline: .now() + {seconds},
            execute: {work}
        )"""
        source = replace_once(source, before, f"        scheduleAfter({seconds}, {work})")
    return PREFIX + source + "\n" + SUFFIX


def verify_sources(core, adapter):
    assert core == expected_core(), "Work creation/order, deadlines, retained jobs or cancellation changed"
    assert adapter == EXPECTED_ADAPTER, "Main-queue Dispatch adapter changed"


def verify_texts(view, core, adapter):
    from verify_eagle_aura_request_capture import verify_texts as verify_capture, CORE as CAPTURE
    repo = Path(__file__).resolve().parents[1]
    verify_capture(view, (repo / CAPTURE).read_text())
    verify_sources(core, adapter)


def main():
    repo = Path(__file__).resolve().parents[1]
    values = [(repo / path).read_text() for path in (VIEW, CORE, ADAPTER)]
    verify_texts(*values)
    for index, before, after in [
        (0, BRIDGE, BRIDGE.replace("progress: progress", "progress: wrongProgress")),
        (0, CANCELLATIONS[0][1], CANCELLATIONS[1][1]),
        (0, CANCELLATIONS[1][1], "cancelHardDeadline: {}"),
        (1, "scheduleAfter(10, softProgressWork)", "scheduleAfter(9, softProgressWork)"),
        (1, "scheduleAfter(60, hardDeadlineWork)", "scheduleAfter(59, hardDeadlineWork)"),
        (1, "progress.reportProgress()", "progress.deadlineReached()"),
        (1, "softProgressWork: softProgressWork", "softProgressWork: hardDeadlineWork"),
        (1, "cancel(hardDeadlineWork)", "cancel(softProgressWork)"),
        (1, "cancel(softProgressWork)", "cancel(softProgressWork)\n        cancel(hardDeadlineWork)"),
        (2, "DispatchQueue.main.asyncAfter", "DispatchQueue.global().asyncAfter"),
        (2, ".now() + Double(seconds)", ".now() + 10"),
        (2, "cancel: { $0.cancel() }", "cancel: { _ in }"),
    ]:
        mutated = values.copy()
        mutated[index] = replace_once(mutated[index], before, after)
        try:
            verify_texts(*mutated)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print("PASS: scheduling/cancellation sources, full public reversal and 12 rejected mutations", flush=True)
    # This existing virtual-clock runner now compiles both actual new production
    # sources, including the Dispatch adapter, against recording queue/work types.
    from verify_eagle_aura_step_lifecycle import main as run_virtual_clock
    run_virtual_clock()
    with tempfile.TemporaryDirectory(prefix="eagle-aura-dispatch-") as temporary:
        for profile, flags in (("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])):
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / CORE),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioStepProgress.swift"),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift"),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                str(repo / "scripts/verify_eagle_aura_progress_scheduling.swift"),
                "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=20)


if __name__ == "__main__":
    main()
