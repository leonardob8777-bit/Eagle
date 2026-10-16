#!/usr/bin/env python3
"""Public-result consumption and ordered profile effects; no native engine is linked."""
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap

from verify_eagle_dock_apply_flow import replace_once, declaration
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioResultConsumption.swift"
FIELDS = {
    "activeFlagsRaw": "flags", "activeModeRaw": "legacyMode",
    "activeIslandModeRaw": "islandMode", "activeDockModeRaw": "dockMode",
    "activeDockGalleryStyleRaw": "dockGalleryStyle", "activeSpringBoardPID": "springBoardPID",
    "activeIslandRed": "islandRed", "activeIslandGreen": "islandGreen", "activeIslandBlue": "islandBlue",
    "activeDockRed": "dockRed", "activeDockGreen": "dockGreen", "activeDockBlue": "dockBlue",
}
PREFIX = '''import Foundation

/// Result interpretation and ordered profile updates. Storage and final effects are supplied by the app.
@MainActor
struct EagleAuraStudioResultConsumption {
    enum StoredField: CaseIterable {
        case flags, legacyMode, islandMode, dockMode, dockGalleryStyle, springBoardPID
        case islandRed, islandGreen, islandBlue, dockRed, dockGreen, dockBlue
    }

    let islandFlag: UInt32
    let dockFlag: UInt32
    let supportedFlags: UInt32
    let motionDegradedFlag: UInt32
    let readRetained: () -> UInt32
    let writeRetained: (UInt32) -> Void
    let readNewlyApplied: () -> UInt32
    let writeNewlyApplied: (UInt32) -> Void
    let readRemoved: () -> UInt32
    let writeRemoved: (UInt32) -> Void
    let readUnavailable: () -> Int32?
    let writeUnavailable: (Int32) -> Void
    let writeFallback: (Int32) -> Void
    let readMotionDegraded: () -> Bool
    let writeMotionDegraded: (Bool) -> Void
    let readDeadlineExceeded: () -> Bool
    let readStored: (StoredField) -> Int
    let writeStored: (StoredField, Int) -> Void
    let log: (String, String) -> Void
    let localizedText: (String, String) -> String
    let errorMessage: (Int32) -> String
    let failAfter: (String, Int32, String?) -> Void
    let finishRollback: (Int32, EagleAuraStudioOperationStep, String) -> Void

    func consume(
        result: Int32,
        operation: EagleAuraStudioOperation,
        operationID: String,
        target: EagleAuraStudioTarget,
        requestedMode: EagleAuraStudioMode,
        step: EagleAuraStudioOperationStep,
        index: Int,
        previouslyVerified: UInt32,
        springBoardPID: Int32,
        mode: Int,
        redValue: Int32,
        greenValue: Int32,
        blueValue: Int32,
        complete: (Bool) -> Void,
        runNext: (Int) -> Void
    ) {
'''
BRIDGE_PREFIX = '''                        EagleAuraStudioResultConsumption(
                            islandFlag: Flag.island,
                            dockFlag: Flag.dock,
                            supportedFlags: Flag.supported,
                            motionDegradedFlag: Flag.motionDegraded,
                            readRetained: { retainedVerified },
                            writeRetained: { retainedVerified = $0 },
                            readNewlyApplied: { newlyApplied },
                            writeNewlyApplied: { newlyApplied = $0 },
                            readRemoved: { removedFlags },
                            writeRemoved: { removedFlags = $0 },
                            readUnavailable: { firstUnavailableResult },
                            writeUnavailable: { firstUnavailableResult = $0 },
                            writeFallback: { verifiedFallbackResult = $0 },
                            readMotionDegraded: { motionDegraded },
                            writeMotionDegraded: { motionDegraded = $0 },
                            readDeadlineExceeded: { hardDeadlineExceeded },
'''
BRIDGE_SUFFIX = '''                            log: { AuraStudioDiagnostics.log($0, $1) },
                            localizedText: { LaraL10n.text(en: $0, es: $1) },
                            errorMessage: { message(for: $0) },
                            failAfter: { failAfterNativeCall($0, result: $1, userDetail: $2) },
                            finishRollback: { finishVerifiedRollback($0, step: $1, reason: $2) }
                        ).consume(
                            result: result,
                            operation: operation,
                            operationID: operationID,
                            target: operationTarget,
                            requestedMode: requestedProfileMode,
                            step: step,
                            index: index,
                            previouslyVerified: previouslyVerified,
                            springBoardPID: springBoardPID,
                            mode: mode,
                            redValue: redValue,
                            greenValue: greenValue,
                            blueValue: blueValue,
                            complete: { completeSuccess(deadlineWarning: $0) },
                            runNext: { runStep($0) }
                        )'''


def bridge():
    result = BRIDGE_PREFIX + "                            readStored: { field in\n                                switch field {\n"
    for old, field in FIELDS.items():
        result += f"                                case .{field}: return {old}\n"
    result += "                                }\n                            },\n                            writeStored: { field, value in\n                                switch field {\n"
    for old, field in FIELDS.items():
        result += f"                                case .{field}: {old} = value\n"
    return result + "                                }\n                            },\n" + BRIDGE_SUFFIX


def original():
    source = public_file()
    start = source.index("                        if operation.isRemoving {")
    end = source.index("\n                    }\n                }\n            }\n        }\n\n        runStep(0)", start)
    return source[start:end]


def intermediate():
    from verify_eagle_aura_step_lifecycle import OLD_ADVANCE, ADVANCE, replace_exact_lines
    source = original()
    for indent, count in ((28, 3), (24, 1)):
        source = replace_exact_lines(source, textwrap.indent(OLD_ADVANCE, " " * indent),
                                     textwrap.indent(ADVANCE, " " * indent), count)
    return source


def inline_result_consumption(view):
    from verify_eagle_aura_request_capture import inline_request_capture
    view = inline_request_capture(view)
    return replace_once(view, bridge(), intermediate())


def expected_core():
    source = textwrap.indent(textwrap.dedent(intermediate()), "        ")
    # Turn compound updates into one ordered read/write; do not snapshot state early.
    for name, read, write in (("retainedVerified", "readRetained", "writeRetained"),
                              ("newlyApplied", "readNewlyApplied", "writeNewlyApplied"),
                              ("removedFlags", "readRemoved", "writeRemoved")):
        source, count = re.subn(r"(?m)^(\s*)" + name + r" ([&|])= ([^\n]+)$",
                               lambda m: m[1] + write + "(" + read + "() " + m[2] + " " + m[3] + ")", source)
        assert count > 0, name
        source = re.sub(r"\b" + name + r"\b", read + "()", source)
    source = replace_once(source, "motionDegraded = motionDegraded ||\n            rawResult & Flag.motionDegraded != 0",
                          "writeMotionDegraded(readMotionDegraded() ||\n            rawResult & Flag.motionDegraded != 0)")
    source = replace_once(source, "firstUnavailableResult = result", "writeUnavailable(result)")
    source = replace_once(source, "firstUnavailableResult == nil", "readUnavailable() == nil")
    source = replace_once(source, "verifiedFallbackResult = result", "writeFallback(result)")
    source = replace_once(source, "activeSpringBoardPID = activeFlagsRaw == 0\n                ? 0\n                : Int(springBoardPID)",
                          "writeStored(.springBoardPID, readStored(.flags) == 0\n                ? 0\n                : Int(springBoardPID))")
    for old, field in FIELDS.items():
        source = re.sub(r"(?m)^(\s*)" + old + r" = ([^\n]+)$",
                        lambda m: m[1] + f"writeStored(.{field}, " + m[2] + ")", source)
        source = re.sub(r"\b" + old + r"\b", f"readStored(.{field})", source)
    for before, after, count in [
        ("AuraStudioNativeContract.", "EagleAuraStudioNativeContract.", 4),
        ("operationTarget", "target", 3), ("requestedProfileMode", "requestedMode", 2),
        ("Flag.island", "islandFlag", 5), ("Flag.dock", "dockFlag", 2),
        ("Flag.supported", "supportedFlags", 1), ("Flag.motionDegraded", "motionDegradedFlag", 1),
        ("hardDeadlineExceeded", "readDeadlineExceeded()", 5),
        ("complete: { completeSuccess(deadlineWarning: $0) }", "complete: complete", 4),
        ("runNext: { runStep($0) }", "runNext: runNext", 4),
        ("AuraStudioDiagnostics.log(", "log(", 4),
        ("message(for: result)", "errorMessage(result)", 2),
        ("failAfterNativeCall(", "failAfter(", 6),
        ("result: result,\n                userDetail: ", "result,\n                ", 4),
        ("result: result,\n                    userDetail: ", "result,\n                    ", 1),
        ("result: result\n            )", "result, nil\n            )", 1),
        ("LaraL10n.text(", "localizedText(", 3),
        ("en: ", "", 3), ("es: ", "", 3),
        ("finishVerifiedRollback(", "finishRollback(", 1),
        ("step: step,\n                reason: ", "step,\n                ", 1),
    ]:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n    }\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_request_preparation import verify_texts as verify_preparation, CORE as PREPARATION
    repo = Path(__file__).resolve().parents[1]
    verify_preparation(view, (repo / PREPARATION).read_text())
    assert core == expected_core(), "Result handling, profile effects or continuation changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    for index, before, after in [
        (0, "case .dockMode: activeDockModeRaw = value", "case .dockMode: activeIslandModeRaw = value"),
        (0, "writeFallback: { verifiedFallbackResult = $0 }", "writeFallback: { firstUnavailableResult = $0 }"),
        (0, "target: operationTarget", "target: .dock"),
        (0, "readDeadlineExceeded: { hardDeadlineExceeded }", "readDeadlineExceeded: { false }"),
        (1, "guard result == 0", "guard result >= 0"),
        (1, "readRetained() & ~step.flag", "readRetained() & step.flag"),
        (1, "readRemoved() | step.flag", "readRemoved() | islandFlag"),
        (1, "readUnavailable() == nil", "readUnavailable() != nil"),
        (1, "readNewlyApplied() | islandFlag", "readNewlyApplied() | dockFlag"),
        (1, "&& !readDeadlineExceeded()", "&& readDeadlineExceeded()"),
        (1, "writeStored(.dockRed, Int(redValue))", "writeStored(.islandRed, Int(redValue))"),
        (1, "writeStored(.dockGalleryStyle, 0)", "writeStored(.dockGalleryStyle, 1)"),
        (1, "requestedFlag: step.flag", "requestedFlag: supportedFlags"),
        (1, "rawResult & motionDegradedFlag != 0", "rawResult & motionDegradedFlag == 0"),
    ]:
        values = [view, core]
        if index == 0:
            assert before in bridge()
            values[0] = replace_once(view, bridge(), bridge().replace(before, after, 1))
        else:
            assert before in core, before
            values[1] = core.replace(before, after, 1)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_result_consumption.swift").read_text()
    # Public result contract comes directly from the frozen public screen.
    fixture += "\n" + declaration(public_file(), "private enum AuraStudioNativeContract") + "\n"
    for name, block in (("PublicHost", original()), ("OwnedHost", bridge())):
        fixture += "\n@MainActor struct " + name + ": Host { let context: Context\n"
        fixture += "func consume(result: Int32, operation: EagleAuraStudioOperation, operationID: String, operationTarget: EagleAuraStudioTarget, requestedProfileMode: EagleAuraStudioMode, step: EagleAuraStudioOperationStep, index: Int, previouslyVerified: UInt32, springBoardPID: Int32, mode: Int, redValue: Int32, greenValue: Int32, blueValue: Int32) {\n"
        fixture += block + "\n}\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-consumption-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in (("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])):
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                *[str(repo / path) for path in (CORE,
                  "lara/EagleCore/AuraStudio/EagleAuraStudioNativeContract.swift",
                  "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift",
                  "lara/EagleCore/AuraStudio/EagleAuraStudioStepFlow.swift",
                  "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift",
                  "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift")],
                str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: public result consumption, all profile bindings, unchanged screen continuation; 14 rejected mutations")


if __name__ == "__main__":
    main()
