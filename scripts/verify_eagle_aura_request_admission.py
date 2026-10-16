#!/usr/bin/env python3
"""Compare request admission with the public guards using recording dependencies.

No native access, session construction, system mutation or network is linked.
"""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioRequestAdmission.swift"
BRIDGE = """        guard let operationTarget = requestAdmission.admit(
            operation: operation,
            operationID: operationID,
            mode: mode,
            requestedProfileMode: requestedProfileMode,
            requestedFlags: requestedFlags,
            requestedTarget: requestedTarget,
            majorVersion: version.majorVersion,
            displayIsZoomed: display.isDisplayZoomed
        ) else { return }"""
CONTROLLER = """private var requestAdmission: EagleAuraStudioRequestAdmission {
        EagleAuraStudioRequestAdmission(
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            operationInProgress: { isApplying },
            beginGate: { AuraStudioApplyGate.begin() },
            islandCanAttempt: { islandCompatibility.canAttemptLiveIslandAura },
            islandUnavailableMessage: { islandHardwareUnavailableMessage },
            debuggerAttached: { isdebugged() },
            accessReady: { mgr.dsready },
            readSelectedTarget: { selectedTarget },
            flagForTarget: { flag(for: $0) },
            allowsMode: { policyAllows($0, for: $1) },
            modeTitle: { $0.title },
            channelTitle: { releaseChannel.title },
            errorMessage: { message(for: $0) },
            localizedText: { LaraL10n.text(en: $0, es: $1) },
            log: { AuraStudioDiagnostics.log($0, $1) },
            showNotice: { notice = AuraStudioNotice(message: $0) },
            finish: { finish(message: $0) }
        )
    }"""
PREFIX = """import Foundation

/// Existing request checks, in their original order. Access reads and effects are supplied by the app.
@MainActor
struct EagleAuraStudioRequestAdmission {
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let operationInProgress: () -> Bool
    let beginGate: () -> Bool
    let islandCanAttempt: () -> Bool
    let islandUnavailableMessage: () -> String
    let debuggerAttached: () -> Bool
    let accessReady: () -> Bool
    let readSelectedTarget: () -> EagleAuraStudioTarget
    let flagForTarget: (EagleAuraStudioTarget) -> UInt32
    let allowsMode: (EagleAuraStudioMode, EagleAuraStudioTarget) -> Bool
    let modeTitle: (EagleAuraStudioMode) -> String
    let channelTitle: () -> String
    let errorMessage: (Int32) -> String
    let localizedText: (String, String) -> String
    let log: (String, String) -> Void
    let showNotice: (String) -> Void
    let finish: (String) -> Void

    """
SIGNATURE = """func admit(
        operation: EagleAuraStudioOperation,
        operationID: String,
        mode: Int,
        requestedProfileMode: EagleAuraStudioMode,
        requestedFlags: UInt32,
        requestedTarget: EagleAuraStudioTarget?,
        majorVersion: Int,
        displayIsZoomed: Bool
    ) -> EagleAuraStudioTarget? {"""


def original():
    source = public_file()
    begin = source.index("        // The camera aperture is fixed hardware")
    end = source.index("\n\n        var steps: [AuraStudioOperationStep]", begin)
    return source[begin:end]


def inline_request_admission(view):
    from verify_eagle_aura_request_preparation import inline_request_preparation
    view = inline_request_preparation(view)
    view = replace_once(view, BRIDGE, original())
    return replace_once(view, "    " + CONTROLLER + "\n\n", "")


def expected_core():
    source = original()
    substitutions = [
        ("display.isDisplayZoomed", "displayIsZoomed", 1),
        ("AuraStudioDiagnostics.log(", "log(", 2),
        ("notice = AuraStudioNotice(message: LaraL10n.text(", "showNotice(localizedText(", 3),
        ("finish(message: ", "finish(", 8),
        ("LaraL10n.text(", "localizedText(", 6),
        ("en: ", "", 9), ("es: ", "", 9),
        ("!applySafetyBlocked", "!localSafetyBlocked()", 1),
        ("!mgr.rcSafetyLocked", "!remoteSafetyLocked()", 1),
        ("!isApplying", "!operationInProgress()", 1),
        ("AuraStudioApplyGate.begin()", "beginGate()", 1),
        ("!islandCompatibility.canAttemptLiveIslandAura", "!islandCanAttempt()", 1),
        ("islandHardwareUnavailableMessage", "islandUnavailableMessage()", 1),
        ("!isdebugged()", "!debuggerAttached()", 1),
        ("version.majorVersion", "majorVersion", 3),
        ("AuraStudioMode.tint", "EagleAuraStudioMode.tint", 1),
        ("message(for: -17)", "errorMessage(-17)", 1),
        ("mgr.dsready", "accessReady()", 1),
        ("flag(for: selectedTarget)", "flagForTarget(readSelectedTarget())", 1),
        ("operationTarget == selectedTarget", "operationTarget == readSelectedTarget()", 1),
        ("selectedTarget.title", "readSelectedTarget().title", 1),
        ("policyAllows(requestedProfileMode, for: operationTarget)", "allowsMode(requestedProfileMode, operationTarget)", 1),
        ("requestedProfileMode.title", "modeTitle(requestedProfileMode)", 2),
        ("releaseChannel.title", "channelTitle()", 2),
        ("            return\n", "            return nil\n", 11),
    ]
    for before, after, count in substitutions:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + SIGNATURE + "\n" + source + "\n        return operationTarget\n    }\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Request reads, native continuation, UI or guard connections changed"
    assert core == expected_core(), "Admission decisions, notices, effect order or short-circuiting changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "localSafetyBlocked: { applySafetyBlocked }", "localSafetyBlocked: { false }"),
        (0, "remoteSafetyLocked: { mgr.rcSafetyLocked }", "remoteSafetyLocked: { false }"),
        (0, "beginGate: { AuraStudioApplyGate.begin() }", "beginGate: { true }"),
        (0, "debuggerAttached: { isdebugged() }", "debuggerAttached: { false }"),
        (0, "accessReady: { mgr.dsready }", "accessReady: { true }"),
        (0, "readSelectedTarget: { selectedTarget }", "readSelectedTarget: { .island }"),
        (0, "majorVersion: version.majorVersion", "majorVersion: 18"),
        (0, "displayIsZoomed: display.isDisplayZoomed", "displayIsZoomed: false"),
        (1, "!localSafetyBlocked(), !remoteSafetyLocked()", "!remoteSafetyLocked(), !localSafetyBlocked()"),
        (1, "!operationInProgress(), beginGate()", "beginGate(), !operationInProgress()"),
        (1, "majorVersion == 17 || majorVersion == 18", "majorVersion >= 17"),
        (1, "requestedFlags.nonzeroBitCount == 1", "requestedFlags.nonzeroBitCount > 0"),
        (1, "operationTarget == readSelectedTarget()", "operationTarget == .island"),
        (1, "return operationTarget", "return .island"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0 and before in CONTROLLER:
            values[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            values[index] = replace_once(values[index], before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    signature = """func evaluate(_ operation: AuraStudioOperation, _ operationID: String,
        _ mode: Int, _ requestedProfileMode: AuraStudioMode, _ requestedFlags: UInt32,
        _ requestedTarget: AuraStudioTarget?, _ version: OperatingSystemVersion,
        _ display: Display) -> AuraStudioTarget? {"""
    reference = original().replace("            return\n", "            return nil\n")
    fixture = (repo / "scripts/verify_eagle_aura_request_admission.swift").read_text()
    import verify_eagle_aura_request_preparation as preparation
    request_signature = signature.replace("func evaluate(", "func request(").replace(
        "-> AuraStudioTarget?", "-> EagleAuraStudioRequestParameters<GalleryPosition>?")
    fixture += "\n@MainActor struct PublicHost: Host { let context: Context\n" + signature + "\n" + reference + "\n        return operationTarget\n    }\n"
    fixture += request_signature + "\n" + reference + "\n" + preparation.original() + "\n" + preparation.RETURN + "\n}\n}\n"
    fixture += "\n@MainActor struct OwnedHost: Host { let context: Context\n" + CONTROLLER.replace("private var ", "var ") + "\n" + signature + "\n"
    fixture += "return requestAdmission.admit(operation: operation, operationID: operationID, mode: mode, requestedProfileMode: requestedProfileMode, requestedFlags: requestedFlags, requestedTarget: requestedTarget, majorVersion: version.majorVersion, displayIsZoomed: display.isDisplayZoomed)\n}\n"
    fixture += request_signature + "\n" + BRIDGE.replace("else { return }", "else { return nil }") + "\n" + preparation.BRIDGE + "\n" + preparation.RETURN + "\n}\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-admission-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in [("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])]:
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / CORE), str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift"),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioOperationPlan.swift"),
                str(repo / preparation.CORE),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioColors.swift"),
                str(repo / "lara/EagleCore/Gallery/EagleGalleryPosition.swift"),
                str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: public request admission/full-screen reversal; fourteen rejected mutations; no native execution", flush=True)


if __name__ == "__main__":
    main()
