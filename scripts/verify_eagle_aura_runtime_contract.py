#!/usr/bin/env python3
"""Compare Aura result rules and process-wide admission against the public code.

The fixture never links or executes the native engine. Concurrency exercises only
the MainActor admission flag; native results are ordinary input integers.
"""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CONTRACT = "lara/EagleCore/AuraStudio/EagleAuraStudioNativeContract.swift"
GATE = "lara/EagleCore/AuraStudio/EagleAuraStudioApplyGate.swift"
CONTRACT_MARKER = "private enum AuraStudioNativeContract"
GATE_MARKER = "@MainActor\nprivate enum AuraStudioApplyGate"
CONTRACT_BRIDGE = "private typealias AuraStudioNativeContract = EagleAuraStudioNativeContract"
GATE_BRIDGE = "private typealias AuraStudioApplyGate = EagleAuraStudioApplyGate"
CONTRACT_PREFIX = "import Foundation\n\n/// Pure interpretation of one-surface Aura results. This never acquires access or calls the native engine.\n"
GATE_PREFIX = "import Foundation\n\n/// Process-wide Aura admission state. The caller retains session ownership and native execution.\n"


def originals():
    public = public_file()
    return declaration(public, CONTRACT_MARKER), declaration(public, GATE_MARKER)


def inline_runtime_contract(view):
    from verify_eagle_aura_display_geometry import inline_display_geometry
    view = inline_display_geometry(view)
    contract, gate = originals()
    view = replace_once(view, CONTRACT_BRIDGE, contract)
    return replace_once(view, GATE_BRIDGE, gate)


def expected_sources():
    contract, gate = originals()
    contract = replace_once(contract, CONTRACT_MARKER, "nonisolated enum EagleAuraStudioNativeContract")
    contract = contract.replace("AuraStudioTarget", "EagleAuraStudioTarget").replace("AuraStudioMode", "EagleAuraStudioMode")
    gate = replace_once(gate, "private enum AuraStudioApplyGate", "enum EagleAuraStudioApplyGate")
    return CONTRACT_PREFIX + contract + "\n", GATE_PREFIX + gate + "\n"


def verify_texts(view, contract, gate):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Aura calls, storage, UI or guard order changed"
    assert (contract, gate) == expected_sources(), "Result decisions or process-wide gate semantics changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, contract, gate = [(repo / p).read_text() for p in (VIEW, CONTRACT, GATE)]
    verify_texts(view, contract, gate)
    for index, before, after in [
        (0, CONTRACT_BRIDGE, CONTRACT_BRIDGE.replace("= EagleAuraStudioNativeContract", "= OtherContract")),
        (0, GATE_BRIDGE, GATE_BRIDGE.replace("= EagleAuraStudioApplyGate", "= OtherGate")),
        (1, "guard !isRemoval", "guard isRemoval"),
        (1, "result == -12", "result == -15"),
        (1, "guard result >= 0", "guard result > 0"),
        (1, "& supportedFlags == requestedFlag", "& supportedFlags != requestedFlag"),
        (2, "!operationInFlight, !safetyLocked", "!operationInFlight"),
        (2, "private static var safetyLocked", "private var safetyLocked"),
        (2, "safetyLocked = true", "safetyLocked = false"),
    ]:
        values = [view, contract, gate]
        values[index] = replace_once(values[index], before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_runtime_contract.swift").read_text()
    original_contract, original_gate = originals()
    fixture += "\n" + original_contract.replace(CONTRACT_MARKER, "nonisolated enum PublicContract")
    fixture += "\n" + original_gate.replace("private enum AuraStudioApplyGate", "enum PublicGate")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-runtime-contract-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in [("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])]:
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift"),
                str(repo / CONTRACT), str(repo / GATE), str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: exact public Aura contract/gate, full-screen reversal and nine rejected mutations", flush=True)


if __name__ == "__main__":
    main()
