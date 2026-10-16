#!/usr/bin/env python3
"""Aura operation presentation lifecycle: public sequencing and queued completion parity."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioOperationUI.swift"
BRIDGES = ["        operationUI.begin(\n            operationID: operationID,\n            isRemoving: operation.isRemoving,\n            stepCount: steps.count\n        )","func resetOperationUI() {\n            operationUI.reset()\n        }","private func finish(message: String) {\n        operationUI.finish(message: message)\n    }"]
CONTROLLER = "private var operationUI: EagleAuraStudioOperationUI {\n        EagleAuraStudioOperationUI(\n            writeApplying: { isApplying = $0 },\n            writeRemoval: { operationIsRemoval = $0 },\n            writeStepIndex: { operationStepIndex = $0 },\n            writeStepCount: { operationStepCount = $0 },\n            writeOperationID: { activeOperationID = $0 },\n            writeStage: { applyStage = $0 },\n            localizedText: { LaraL10n.text(en: $0, es: $1) },\n            log: { AuraStudioDiagnostics.log($0, $1) },\n            scheduleOnMain: { DispatchQueue.main.async(execute: $0) },\n            endGate: { AuraStudioApplyGate.end() },\n            showNotice: { notice = AuraStudioNotice(message: $0) }\n        )\n    }"
PREFIX = "import Foundation\n\n/// Presentation lifecycle only. Native execution, operation gate and scheduling remain injected.\n@MainActor\nstruct EagleAuraStudioOperationUI {\n    let writeApplying: (Bool) -> Void\n    let writeRemoval: (Bool) -> Void\n    let writeStepIndex: (Int) -> Void\n    let writeStepCount: (Int) -> Void\n    let writeOperationID: (String?) -> Void\n    let writeStage: (String) -> Void\n    let localizedText: (String, String) -> String\n    let log: (String, String) -> Void\n    let scheduleOnMain: (@escaping @MainActor @Sendable () -> Void) -> Void\n    let endGate: () -> Void\n    let showNotice: (String) -> Void\n\n"
SUBSTITUTIONS = [["self.","",7],["operation.isRemoving","isRemoving",1],["steps.count","stepCount",1],["isApplying = true","writeApplying(true)",1],["isApplying = false","writeApplying(false)",2],["operationIsRemoval = isRemoving","writeRemoval(isRemoving)",1],["operationIsRemoval = false","writeRemoval(false)",2],["operationStepIndex = 0","writeStepIndex(0)",3],["operationStepCount = stepCount","writeStepCount(stepCount)",1],["operationStepCount = 0","writeStepCount(0)",2],["activeOperationID = operationID","writeOperationID(operationID)",1],["activeOperationID = nil","writeOperationID(nil)",2],["applyStage = \"\"","writeStage(\"\")",2],["applyStage = LaraL10n.text(\n            en: \"Preparing a fresh SpringBoard session…\",\n            es: \"Preparando una sesión nueva de SpringBoard…\"\n        )","writeStage(localizedText(\n            \"Preparing a fresh SpringBoard session…\",\n            \"Preparando una sesión nueva de SpringBoard…\"\n        ))",1],["AuraStudioDiagnostics.log","log",1],["DispatchQueue.main.async","scheduleOnMain",1],["AuraStudioApplyGate.end()","endGate()",1],["notice = AuraStudioNotice(message: message)","showNotice(message)",1]]


def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=Path(__file__).resolve().parents[1], text=True)


def originals():
    source = public_file()
    start = source.index("        isApplying = true\n        operationIsRemoval = operation.isRemoving")
    end = source.index("\n\n        func resetOperationUI()", start)
    return [source[start:end], declaration(source, "func resetOperationUI()"),
            declaration(source, "private func finish(message:")]


def inline_operation_ui(view):
    from verify_eagle_aura_result_feedback import inline_feedback
    view = inline_feedback(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_core():
    begin, reset, finish = originals()
    reset = "\n".join(line[4:] if index else line.replace("resetOperationUI", "reset")
                      for index, line in enumerate(reset.split("\n")))
    source = PREFIX + "    func begin(operationID: String, isRemoving: Bool, stepCount: Int) {\n" + begin + "\n    }\n\n    " + reset + "\n\n    " + finish.replace("private func", "func") + "\n}\n"
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return source


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated UI/native/gate logic or callback changed"
    assert compact(core) == compact(expected_core()), "Operation lifecycle order changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "writeApplying: { isApplying = $0 }", "writeApplying: { isApplying = false }"),
        (0, "writeStepCount: { operationStepCount = $0 }", "writeStepCount: { operationStepIndex = $0 }"),
        (0, "writeOperationID: { activeOperationID = $0 }", "writeOperationID: { activeOperationID = nil }"),
        (0, "scheduleOnMain: { DispatchQueue.main.async(execute: $0) }", "scheduleOnMain: { $0() }"),
        (0, "endGate: { AuraStudioApplyGate.end() }", "endGate: { }"),
        (0, "showNotice: { notice = AuraStudioNotice(message: $0) }", "showNotice: { _ in }"),
        (0, "beginGate: { AuraStudioApplyGate.begin() }", "beginGate: { true }"),
        (1, "writeApplying(true)", "writeApplying(false)"),
        (1, "writeRemoval(isRemoving)", "writeRemoval(false)"),
        (1, "writeStepCount(stepCount)", "writeStepCount(0)"),
        (1, "log(\"finish\", \"error=true\")", "log(\"finish\", \"error=false\")"),
        (1, "endGate()\n            writeOperationID(nil)", "writeOperationID(nil)\n            endGate()"),
        (1, "showNotice(message)", "showNotice(\"\")"),
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
    print(f"PASS: public begin/reset/queued-finish and exact callbacks; whole-screen/native reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, members in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        begin, reset, finish = members
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     "func begin(_ operation: Operation, _ steps: [Int], _ operationID: String) {\n" + begin + "\n}\n"
                     "func reset() { resetOperationUI() }\nfunc end(_ message: String) { finish(message: message) }\n"
                     + reset + "\n" + finish + "\n" + (CONTROLLER if name == "OwnedHost" else "") + "\n}\n")
    fields = [("Bool", "isApplying"), ("Bool", "operationIsRemoval"), ("Int", "operationStepIndex"),
              ("Int", "operationStepCount"), ("String?", "activeOperationID"), ("String", "applyStage"),
              ("AuraStudioNotice?", "notice")]
    getters = []
    for kind, name in fields:
        getters.append(f'var {name}: {kind} {{ get {{ context.{name} }} nonmutating set {{ context.{name} = newValue; context.record("{name}") }} }}')
    fixture = (repo / "scripts/verify_eagle_aura_operation_ui.swift").read_text()
    fixture += "\nextension Host {\n" + "\n".join(getters) + "\n}\n" + "\n".join(hosts)
    with tempfile.TemporaryDirectory(prefix="eagle-aura-operation-ui-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
