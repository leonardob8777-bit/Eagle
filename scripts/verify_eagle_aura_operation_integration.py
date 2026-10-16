#!/usr/bin/env python3
"""Connect six Aura operation components through their exact production bridges."""
from pathlib import Path
import subprocess
import tempfile
import verify_eagle_aura_operation_ui as ui
import verify_eagle_aura_result_feedback as feedback
import verify_eagle_aura_completion as completion
import verify_eagle_aura_recovery_flow as recovery
import verify_eagle_aura_unverified_failure as failure
from verify_eagle_dock_apply_flow import declaration

def main():
    repo = Path(__file__).resolve().parents[1]
    view = (repo / ui.VIEW).read_text()
    for check, paths in [(ui, [ui.CORE]), (feedback, [feedback.CORE]),
                         (completion, [completion.CORE]), (recovery, recovery.CORES),
                         (failure, [failure.CORE])]:
        check.verify_texts(view, *[(repo / p).read_text() for p in paths])
    fixture = (repo / "scripts/verify_eagle_aura_operation_integration.swift").read_text()
    for name, owned in [("PublicHost", False), ("OwnedHost", True)]:
        begin, reset, finish = ui.BRIDGES if owned else ui.originals()
        methods = [reset, finish]
        methods += feedback.BRIDGES if owned else feedback.originals()
        methods += [completion.BRIDGE if owned else completion.original()]
        methods += recovery.BRIDGES if owned else recovery.originals()
        methods += [failure.BRIDGE if owned else failure.original()]
        body = "\n".join(methods)
        fixture += "@MainActor struct " + name + ": Host {\nlet context: Context\n"
        fixture += "func begin() {\n" + begin + "\n}\n"
        fixture += "func finishError(_ message: String) { finish(message: message) }\n"
        fixture += body + "\n"
        if owned: fixture += ui.CONTROLLER + "\n" + feedback.CONTROLLER + "\n"
        fixture += "}\n"
    fields = [("Int", s) for s in ["activeFlagsRaw", "activeModeRaw", "activeIslandModeRaw", "activeDockModeRaw",
                                   "activeSpringBoardPID", "operationStepIndex", "operationStepCount"]]
    fields += [("Bool", s) for s in ["applySafetyBlocked", "isApplying", "operationIsRemoval"]]
    fields += [("String", "applyStage"), ("String?", "activeOperationID"), ("UInt32", "retainedVerified")]
    fixture += "\nextension Host {\n"
    for kind, name in fields:
        read_event = '' if name == "retainedVerified" else f'context.events.append("read.{name}"); '
        fixture += f'var {name}: {kind} {{ get {{ {read_event}return context.{name} }} nonmutating set {{ context.{name} = newValue; context.events.append("write.{name}:\\(String(describing: newValue))") }} }}\n'
    fixture += "}\n"
    # Native backend is not linked. PID/gate/manager/report/notice are recording fixtures.
    cores = ["lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift", ui.CORE, feedback.CORE,
             completion.CORE, *recovery.CORES, failure.CORE]
    with tempfile.TemporaryDirectory(prefix="eagle-aura-operation-integration-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode,
                            *[str(repo / p) for p in cores], str(source), "-o", str(binary)],
                           check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)
    print("PASS: six owned Aura operation components connected through exact production bridges; native guards/calls reverse unchanged")

if __name__ == "__main__": main()

