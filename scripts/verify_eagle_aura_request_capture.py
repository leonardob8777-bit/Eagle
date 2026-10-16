#!/usr/bin/env python3
"""Compare request capture/reconciliation order with the frozen public screen."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioRequestCapture.swift"
BRIDGE = """        let context = EagleAuraStudioRequestCapture(
            supportedFlags: Flag.supported,
            islandFlag: Flag.island,
            dockFlag: Flag.dock,
            currentPID: { "SpringBoard".withCString { find_process_pid($0) } },
            reconcile: { reconcilePersistedActiveState(currentPID: $0) },
            readVersion: { ProcessInfo.processInfo.operatingSystemVersion },
            makeUUID: { UUID() },
            targetTitle: { $0.title },
            readDisplay: { displayGeometry },
            islandFrame: { $0.compactIslandFrame },
            dockFrame: { $0.dockAuraFrame },
            engineBuild: { auraEngineBuild },
            deviceModel: { devicemachine() },
            hardwareToken: { islandCompatibility.diagnosticsToken },
            log: { AuraStudioDiagnostics.log($0, $1) }
        ).capture(operation: operation, flags: flags)
        let operationSpringBoardPID = context.springBoardPID
        let version = context.version
        let operationID = context.operationID
        let mode = context.mode
        let requestedProfileMode = context.requestedProfileMode
        let requestedFlags = context.requestedFlags
        let requestedTarget = context.requestedTarget
        let display = context.display"""
PREFIX = """import Foundation
import CoreGraphics

/// One request's captured identity and environment; no access or session objects.
nonisolated struct EagleAuraStudioRequestContext: Sendable {
    let springBoardPID: Int32
    let version: OperatingSystemVersion
    let operationID: String
    let mode: Int
    let requestedProfileMode: EagleAuraStudioMode
    let requestedFlags: UInt32
    let requestedTarget: EagleAuraStudioTarget?
    let display: EagleAuraStudioDisplayGeometry
}

/// Preserves reconciliation, capture and diagnostic ordering before request admission.
@MainActor
struct EagleAuraStudioRequestCapture {
    let supportedFlags: UInt32
    let islandFlag: UInt32
    let dockFlag: UInt32
    let currentPID: () -> Int32
    let reconcile: (Int32) -> Void
    let readVersion: () -> OperatingSystemVersion
    let makeUUID: () -> UUID
    let targetTitle: (EagleAuraStudioTarget) -> String
    let readDisplay: () -> EagleAuraStudioDisplayGeometry
    let islandFrame: (EagleAuraStudioDisplayGeometry) -> CGRect
    let dockFrame: (EagleAuraStudioDisplayGeometry) -> CGRect
    let engineBuild: () -> String
    let deviceModel: () -> String
    let hardwareToken: () -> String
    let log: (String, String) -> Void

    func capture(
        operation: EagleAuraStudioOperation,
        flags: UInt32
    ) -> EagleAuraStudioRequestContext {
        // Reconcile before reading request metadata or consulting admission.
"""
RETURN = """        return EagleAuraStudioRequestContext(
            springBoardPID: operationSpringBoardPID,
            version: version,
            operationID: operationID,
            mode: mode,
            requestedProfileMode: requestedProfileMode,
            requestedFlags: requestedFlags,
            requestedTarget: requestedTarget,
            display: display
        )"""


def original():
    source = public_file()
    start = source.index('        let operationSpringBoardPID = "SpringBoard".withCString {')
    end = source.index("\n\n        // The camera aperture is fixed hardware", start)
    return source[start:end]


def intermediate():
    from verify_eagle_aura_operation_plan import originals, BRIDGES
    return replace_once(original(), originals()[2], BRIDGES[2])


def inline_request_capture(view):
    from verify_eagle_aura_progress_scheduling import inline_progress_scheduling
    view = inline_progress_scheduling(view)
    return replace_once(view, BRIDGE, intermediate())


def expected_core():
    source = intermediate()
    for before, after in [
        ('"SpringBoard".withCString {\n            find_process_pid($0)\n        }', "currentPID()"),
        ("reconcilePersistedActiveState(currentPID: operationSpringBoardPID)", "reconcile(operationSpringBoardPID)"),
        ("ProcessInfo.processInfo.operatingSystemVersion", "readVersion()"),
        ("UUID()", "makeUUID()"), ("Flag.supported", "supportedFlags"),
        ("AuraStudioNativeContract.target", "EagleAuraStudioNativeContract.target"),
        ("Flag.island", "islandFlag"), ("Flag.dock", "dockFlag"),
        ("requestedTarget?.title", "requestedTarget.map(targetTitle)"),
        ("let display = displayGeometry", "let display = readDisplay()"),
        ("display.compactIslandFrame", "islandFrame(display)"),
        ("display.dockAuraFrame", "dockFrame(display)"),
        ("AuraStudioDiagnostics.log", "log"),
        ("auraEngineBuild", "engineBuild()"), ("devicemachine()", "deviceModel()"),
        ("islandCompatibility.diagnosticsToken", "hardwareToken()"),
    ]:
        source = replace_once(source, before, after)
    return PREFIX + source + "\n" + RETURN + "\n    }\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_result_consumption import verify_texts as verify_consumption, CORE as CONSUMPTION
    repo = Path(__file__).resolve().parents[1]
    verify_consumption(view, (repo / CONSUMPTION).read_text())
    assert core == expected_core(), "Request reconciliation/capture/diagnostics or context changed"


def fixture_block(block):
    # Only nondeterministic platform reads are replaced in both original and bridge.
    block = replace_once(block, "ProcessInfo.processInfo.operatingSystemVersion", "readVersion()")
    return replace_once(block, "UUID()", "makeUUID()")


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "reconcilePersistedActiveState(currentPID: $0)", "reconcilePersistedActiveState(currentPID: 0)"),
        (0, "flags: flags", "flags: Flag.supported"),
        (0, "context.springBoardPID", "Int32(0)"),
        (0, "context.requestedTarget", "AuraStudioTarget.dock"),
        (0, "islandFrame: { $0.compactIslandFrame }", "islandFrame: { $0.dockAuraFrame }"),
        (1, "reconcile(operationSpringBoardPID)", "reconcile(0)"),
        (1, "let version = readVersion()\n        let operationID", "let version = readVersion()\n        reconcile(operationSpringBoardPID)\n        let operationID"),
        (1, "flags & supportedFlags", "flags | supportedFlags"),
        (1, ".prefix(8)", ".prefix(7)"),
        (1, "islandFlag: islandFlag", "islandFlag: dockFlag"),
        (1, "requestedTarget.map(targetTitle)", "requestedTarget.map { _ in targetTitle(.dock) }"),
        (1, "let dockFrame = dockFrame(display)", "let dockFrame = islandFrame(display)"),
        (1, "springBoardPID: operationSpringBoardPID", "springBoardPID: currentPID()"),
        (1, "display: display", "display: readDisplay()"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            values[1] = replace_once(core, before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_request_capture.swift").read_text()
    fixture += "\n" + declaration(public_file(), "private enum AuraStudioNativeContract") + "\n"
    for name, block in (("PublicHost", original()), ("OwnedHost", BRIDGE)):
        fixture += "\n@MainActor struct " + name + ": Host { let state: State\n"
        fixture += "func capture(operation: EagleAuraStudioOperation, flags: UInt32) -> EagleAuraStudioRequestContext {\n"
        fixture += fixture_block(block) + "\n" + RETURN + "\n}\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-capture-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in (("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])):
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                *[str(repo / "lara/EagleCore/AuraStudio" / name) for name in (
                    "EagleAuraStudioRequestCapture.swift", "EagleAuraStudioNativeContract.swift",
                    "EagleAuraStudioOperationPlan.swift", "EagleAuraStudioMode.swift",
                    "EagleAuraStudioTarget.swift", "EagleAuraStudioDisplayGeometry.swift",
                    "EagleAuraStudioReconciliation.swift")],
                str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: whole public screen reconstruction, request context and exact bridge; 14 rejected mutations")


if __name__ == "__main__":
    main()
