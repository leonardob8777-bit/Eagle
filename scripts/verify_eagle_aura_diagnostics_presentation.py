#!/usr/bin/env python3
"""Compare Aura diagnostic messages/formatting against public members; native detection is not executed."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticsPresentation.swift"
MARKERS = ["private var islandHardwareUnavailableMessage:","private func rgb255String(","private var activeModuleCount:","private var verifiedSurfaceSummary:"]
BRIDGES = ["private var islandHardwareUnavailableMessage: String {\n        diagnosticsPresentation.islandHardwareUnavailableMessage\n    }","private func rgb255String(_ red: Double, _ green: Double, _ blue: Double) -> String {\n        diagnosticsPresentation.rgb255String(red, green, blue)\n    }","private var activeModuleCount: Int {\n        diagnosticsPresentation.activeModuleCount\n    }","private var verifiedSurfaceSummary: String {\n        diagnosticsPresentation.verifiedSurfaceSummary\n    }"]
CONTROLLER = "private var diagnosticsPresentation: EagleAuraStudioDiagnosticsPresentation<EagleDynamicIslandCompatibility.Availability> {\n        EagleAuraStudioDiagnosticsPresentation(\n            supportedAvailability: .supported,\n            unsupportedAvailability: .unsupported,\n            isSimulator: { islandCompatibility.isSimulator },\n            availability: { islandCompatibility.availability },\n            readActiveFlags: { EagleStoredThemeValues.flags(activeFlagsRaw) },\n            readSupportedFlags: { deviceSupportedFlags },\n            channel255: { channel255($0) },\n            localizedText: { LaraL10n.text(en: $0, es: $1) }\n        )\n    }"
PREFIX = "import Foundation\n\n/// Read-only diagnostic wording/formatting; hardware classification, flag decoding and storage stay injected.\n@MainActor\nstruct EagleAuraStudioDiagnosticsPresentation<Availability: Equatable> {\n    let supportedAvailability: Availability\n    let unsupportedAvailability: Availability\n    let isSimulator: () -> Bool\n    let availability: () -> Availability\n    let readActiveFlags: () -> UInt32\n    let readSupportedFlags: () -> UInt32\n    let channel255: (Double) -> Int\n    let localizedText: (String, String) -> String\n\n    "
SUBSTITUTIONS = [["private var","var",3],["private func","func",1],["islandCompatibility.isSimulator","isSimulator()",1],["islandCompatibility.availability","availability()",1],["case .supported:","case supportedAvailability:",1],["case .unsupported:","case unsupportedAvailability:",1],["case .unknown:","default:",1],["EagleStoredThemeValues.flags(activeFlagsRaw)","readActiveFlags()",1],["deviceSupportedFlags","readSupportedFlags()",1],["LaraL10n.text(","localizedText(",6],["en: \"","\"",6],["es: \"","\"",6]]

def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]

def inline_diagnostics_presentation(view):
    from verify_eagle_aura_diagnostic_log import inline_diagnostic_log
    view = inline_diagnostic_log(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")

def expected_core():
    source = "\n\n    ".join(originals())
    for before, after, count in SUBSTITUTIONS:
        assert source.count(before) == count, (before, source.count(before))
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Hardware/support rule, runtime binding or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Message/format/count or read order changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "supportedAvailability: .supported", "supportedAvailability: .unknown"),
        (0, "unsupportedAvailability: .unsupported", "unsupportedAvailability: .supported"),
        (0, "isSimulator: { islandCompatibility.isSimulator }", "isSimulator: { false }"),
        (0, "availability: { islandCompatibility.availability }", "availability: { .supported }"),
        (0, "readActiveFlags: { EagleStoredThemeValues.flags(activeFlagsRaw) }", "readActiveFlags: { 0 }"),
        (0, "readSupportedFlags: { deviceSupportedFlags }", "readSupportedFlags: { 0 }"),
        (0, "channel255: { channel255($0) }", "channel255: { _ in 0 }"),
        (1, "if isSimulator()", "if !isSimulator()"),
        (1, "[red, green, blue]", "[blue, green, red]"),
        (1, '.joined(separator: ",")', '.joined(separator: ";")'),
        (1, "(readActiveFlags() & readSupportedFlags())", "(readSupportedFlags() & readActiveFlags())"),
        (1, "& readSupportedFlags()", "| readSupportedFlags()"),
        (1, "activeModuleCount == 1", "activeModuleCount == 0"),
        (1, "No se cambió nada.", "Se aplicó."),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else: values[index] = replace_once(values[index], before, after)
        try: verify_texts(*values)
        except AssertionError: continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: four public diagnostic members, exact bindings and whole-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_diagnostics_presentation.swift").read_text()
    for name, owned in [("PublicHost", False), ("OwnedHost", True)]:
        members = BRIDGES if owned else originals()
        body = "\n".join(members + ([CONTROLLER] if owned else []))
        body = body.replace("private var ", "var ").replace("private func ", "func ")
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-diagnostics-presentation-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioColors.swift"),
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__": main()
