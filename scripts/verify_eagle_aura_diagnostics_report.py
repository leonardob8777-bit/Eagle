#!/usr/bin/env python3
"""Aura report text/file coordination parity; source-level preservation of the runtime header."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticsReport.swift"
MARKER = "private func makeDiagnosticsReport("
BRIDGE = "private func makeDiagnosticsReport(summary: String) -> URL? {\n        EagleAuraStudioDiagnosticsReport(\n            now: { Date() },\n            readLogs: { globallogger.logs },\n            makeHeader: { timestamp, summary in\n                [\n                    \"Eagle Aura Studio diagnostics\",\n                    \"timestamp=\\(timestamp)\",\n                    \"engine=\\(auraEngineBuild)\",\n                    \"operation=\\(activeOperationID ?? \"none\")\",\n                    \"operationKind=\\(operationIsRemoval ? \"remove\" : \"apply\")\",\n                    \"operationStep=\\(operationStepIndex)/\\(operationStepCount)\",\n                    \"summary=\\(summary)\",\n                    \"device=\\(devicemachine())\",\n                    \"islandHardware=\\(islandCompatibility.diagnosticsToken)\",\n                    \"ios=\\(ProcessInfo.processInfo.operatingSystemVersionString)\",\n                    \"dsready=\\(mgr.dsready)\",\n                    \"rcrunning=\\(mgr.rcrunning)\",\n                    \"rcready=\\(mgr.rcready)\",\n                    \"rcSafetyLocked=\\(mgr.rcSafetyLocked)\",\n                    \"rcError=\\(mgr.rcLastError ?? \"none\")\",\n                    \"selectedTarget=\\(selectedTarget.title)\",\n                    \"islandDraft=mode:\\(islandModeRaw) rgb:\\(rgb255String(islandRed, islandGreen, islandBlue))\",\n                    \"dockDraft=mode:\\(dockModeRaw) rgb:\\(rgb255String(dockRed, dockGreen, dockBlue))\",\n                    \"selectedFlags=0x\\(String(selectedFlags, radix: 16))\",\n                    \"activeFlags=0x\\(String(EagleStoredThemeValues.flags(activeFlagsRaw) & deviceSupportedFlags, radix: 16))\",\n                    \"activeIsland=mode:\\(activeIslandModeRaw) rgb:\\(activeIslandRed),\\(activeIslandGreen),\\(activeIslandBlue)\",\n                    \"activeDock=mode:\\(activeDockModeRaw) rgb:\\(activeDockRed),\\(activeDockGreen),\\(activeDockBlue)\",\n                    \"activeSpringBoardPID=\\(activeSpringBoardPID)\",\n                    \"currentSpringBoardPID=\\(\"SpringBoard\".withCString { find_process_pid($0) })\",\n                    \"displayZoomed=\\(displayGeometry.isDisplayZoomed)\",\n                    \"displayFactor=\\(String(format: \"%.4f,%.4f\", displayGeometry.xFactor, displayGeometry.yFactor))\",\n                    \"--- filtered log ---\",\n                ]\n            },\n            temporaryDirectory: { FileManager.default.temporaryDirectory },\n            writeReport: { try $0.write(to: $1, atomically: true, encoding: .utf8) },\n            log: { AuraStudioDiagnostics.log($0, $1) }\n        ).makeDiagnosticsReport(summary: summary)\n    }"
HEADER = "        let header = [\n            \"Eagle Aura Studio diagnostics\",\n            \"timestamp=\\(timestamp)\",\n            \"engine=\\(auraEngineBuild)\",\n            \"operation=\\(activeOperationID ?? \"none\")\",\n            \"operationKind=\\(operationIsRemoval ? \"remove\" : \"apply\")\",\n            \"operationStep=\\(operationStepIndex)/\\(operationStepCount)\",\n            \"summary=\\(summary)\",\n            \"device=\\(devicemachine())\",\n            \"islandHardware=\\(islandCompatibility.diagnosticsToken)\",\n            \"ios=\\(ProcessInfo.processInfo.operatingSystemVersionString)\",\n            \"dsready=\\(mgr.dsready)\",\n            \"rcrunning=\\(mgr.rcrunning)\",\n            \"rcready=\\(mgr.rcready)\",\n            \"rcSafetyLocked=\\(mgr.rcSafetyLocked)\",\n            \"rcError=\\(mgr.rcLastError ?? \"none\")\",\n            \"selectedTarget=\\(selectedTarget.title)\",\n            \"islandDraft=mode:\\(islandModeRaw) rgb:\\(rgb255String(islandRed, islandGreen, islandBlue))\",\n            \"dockDraft=mode:\\(dockModeRaw) rgb:\\(rgb255String(dockRed, dockGreen, dockBlue))\",\n            \"selectedFlags=0x\\(String(selectedFlags, radix: 16))\",\n            \"activeFlags=0x\\(String(EagleStoredThemeValues.flags(activeFlagsRaw) & deviceSupportedFlags, radix: 16))\",\n            \"activeIsland=mode:\\(activeIslandModeRaw) rgb:\\(activeIslandRed),\\(activeIslandGreen),\\(activeIslandBlue)\",\n            \"activeDock=mode:\\(activeDockModeRaw) rgb:\\(activeDockRed),\\(activeDockGreen),\\(activeDockBlue)\",\n            \"activeSpringBoardPID=\\(activeSpringBoardPID)\",\n            \"currentSpringBoardPID=\\(\"SpringBoard\".withCString { find_process_pid($0) })\",\n            \"displayZoomed=\\(displayGeometry.isDisplayZoomed)\",\n            \"displayFactor=\\(String(format: \"%.4f,%.4f\", displayGeometry.xFactor, displayGeometry.yFactor))\",\n            \"--- filtered log ---\",\n        ]"
PREFIX = "import Foundation\n\n/// Diagnostic text/file coordination. Runtime header data, storage and logging remain injected.\n@MainActor\nstruct EagleAuraStudioDiagnosticsReport {\n    let now: () -> Date\n    let readLogs: () -> [String]\n    let makeHeader: (String, String) -> [String]\n    let temporaryDirectory: () -> URL\n    let writeReport: (String, URL) throws -> Void\n    let log: (String, String) -> Void\n\n    "
SUBSTITUTIONS = [["private func","func",1],["formatter.string(from: Date())","formatter.string(from: now())",1],["globallogger.logs","readLogs()",1],["        let header = [\n            \"Eagle Aura Studio diagnostics\",\n            \"timestamp=\\(timestamp)\",\n            \"engine=\\(auraEngineBuild)\",\n            \"operation=\\(activeOperationID ?? \"none\")\",\n            \"operationKind=\\(operationIsRemoval ? \"remove\" : \"apply\")\",\n            \"operationStep=\\(operationStepIndex)/\\(operationStepCount)\",\n            \"summary=\\(summary)\",\n            \"device=\\(devicemachine())\",\n            \"islandHardware=\\(islandCompatibility.diagnosticsToken)\",\n            \"ios=\\(ProcessInfo.processInfo.operatingSystemVersionString)\",\n            \"dsready=\\(mgr.dsready)\",\n            \"rcrunning=\\(mgr.rcrunning)\",\n            \"rcready=\\(mgr.rcready)\",\n            \"rcSafetyLocked=\\(mgr.rcSafetyLocked)\",\n            \"rcError=\\(mgr.rcLastError ?? \"none\")\",\n            \"selectedTarget=\\(selectedTarget.title)\",\n            \"islandDraft=mode:\\(islandModeRaw) rgb:\\(rgb255String(islandRed, islandGreen, islandBlue))\",\n            \"dockDraft=mode:\\(dockModeRaw) rgb:\\(rgb255String(dockRed, dockGreen, dockBlue))\",\n            \"selectedFlags=0x\\(String(selectedFlags, radix: 16))\",\n            \"activeFlags=0x\\(String(EagleStoredThemeValues.flags(activeFlagsRaw) & deviceSupportedFlags, radix: 16))\",\n            \"activeIsland=mode:\\(activeIslandModeRaw) rgb:\\(activeIslandRed),\\(activeIslandGreen),\\(activeIslandBlue)\",\n            \"activeDock=mode:\\(activeDockModeRaw) rgb:\\(activeDockRed),\\(activeDockGreen),\\(activeDockBlue)\",\n            \"activeSpringBoardPID=\\(activeSpringBoardPID)\",\n            \"currentSpringBoardPID=\\(\"SpringBoard\".withCString { find_process_pid($0) })\",\n            \"displayZoomed=\\(displayGeometry.isDisplayZoomed)\",\n            \"displayFactor=\\(String(format: \"%.4f,%.4f\", displayGeometry.xFactor, displayGeometry.yFactor))\",\n            \"--- filtered log ---\",\n        ]","        let header = makeHeader(timestamp, summary)",1],["FileManager.default.temporaryDirectory","temporaryDirectory()",1],["try report.write(to: url, atomically: true, encoding: .utf8)","try writeReport(report, url)",1],["AuraStudioDiagnostics.log(","log(",2]]

def original(): return declaration(public_file(), MARKER)
def inline_diagnostics_report(view):
    from verify_eagle_aura_operation_plan import inline_operation_plan
    view = inline_operation_plan(view)
    return replace_once(view, BRIDGE, original())

def expected_core():
    source = original()
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Header, runtime reads, file adapter or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Report rules or sequencing changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, 'readLogs: { globallogger.logs }', 'readLogs: { [] }'),
        (0, 'atomically: true', 'atomically: false'),
        (0, 'encoding: .utf8', 'encoding: .utf16'),
        (0, '"dsready=\\(mgr.dsready)"', '"dsready=true"'),
        (0, 'displayGeometry.xFactor, displayGeometry.yFactor', 'displayGeometry.yFactor, displayGeometry.xFactor'),
        (1, '.suffix(600)', '.prefix(600)'),
        (1, '.suffix(600)', '.suffix(599)'),
        (1, '.localizedCaseInsensitiveContains(fragment)', '.contains(fragment)'),
        (1, '"eagle.dock",', '"unrelated",'),
        (1, ' + "\\n"', ' + ""'),
        (1, 'timestamp.replacingOccurrences(of: ":", with: "-")', 'timestamp'),
        (1, 'return nil', 'return url'),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0:
            texts[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else: texts[index] = replace_once(core, before, after)
        try: verify_texts(*texts)
        except AssertionError: continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: entire public report flow/header, exact bridges and whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_diagnostics_report.swift").read_text()
    # Runtime header expressions remain byte-identical in the source test. Use a
    # recording header provider in both hosts so no device/native getter runs.
    old = replace_once(original(), HEADER, "        let header = fixtureHeader(timestamp, summary)")
    array = HEADER[len("        let header = "):]
    bridge_array = "\n".join("                " + (line[8:] if n else line) for n, line in enumerate(array.split("\n")))
    owned = replace_once(BRIDGE, bridge_array, "                fixtureHeader(timestamp, summary)")
    old = replace_once(old, "try report.write(to: url, atomically: true, encoding: .utf8)",
                       "try fixtureWrite(report, url, atomically: true, encoding: .utf8)")
    owned = replace_once(owned, "try $0.write(to: $1, atomically: true, encoding: .utf8)",
                         "try fixtureWrite($0, $1, atomically: true, encoding: .utf8)")
    for name, method in [("PublicHost", old), ("OwnedHost", owned)]:
        method = replace_once(method, "Date()", "fixtureNow()").replace("private func", "func")
        fixture += "\n@MainActor struct " + name + " {\n" + method + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-report-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)
if __name__ == "__main__": main()

