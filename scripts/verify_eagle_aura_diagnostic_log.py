#!/usr/bin/env python3
"""Compare Aura event formatting/delivery with the public implementation, without native execution."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioDiagnosticLog.swift"
MARKER = "private enum AuraStudioDiagnostics {"
BRIDGE = '''private enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String = "") {
        EagleAuraStudioDiagnosticLog.log(
            stage, detail,
            now: { Date() },
            makeDelivery: { globallogger.log }
        )
    }
}'''
SIGNATURE = '''static func log(
        _ stage: String,
        _ detail: String = "",
        now: () -> Date,
        makeDelivery: () -> (String) -> Void
    )'''
PREFIX = '''import Foundation

/// Formats one existing Aura diagnostic event; the caller owns the clock and delivery.
'''


def original():
    return declaration(public_file(), MARKER)


def injected_original(name):
    source = replace_once(original(), "private enum AuraStudioDiagnostics", "enum " + name)
    source = replace_once(source, 'static func log(_ stage: String, _ detail: String = "")', SIGNATURE)
    source = replace_once(source, "Date()", "now()")
    return replace_once(source, "globallogger.log(", "makeDelivery()(")


def reference_host():
    # Preserve the public receiver-call expression to independently test its
    # evaluation order. Only its clock is redirected; the sink is a property.
    source = replace_once(original(), "private enum AuraStudioDiagnostics {", """struct PublicDiagnosticLog {
    let context: LogContext
    var globallogger: LogSink { context.sink() }""")
    source = replace_once(source, "static func log(", "func log(")
    return replace_once(source, "Date()", "context.now()")


def inline_diagnostic_log(view):
    from verify_eagle_aura_color_presentation import inline_color_presentation
    view = inline_color_presentation(view)
    return replace_once(view, BRIDGE, original())


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Existing log calls, delivery binding or unrelated screen changed"
    # Whitespace inside log strings is observable; do not normalize it away.
    assert core == PREFIX + injected_original("EagleAuraStudioDiagnosticLog") + "\n", "Diagnostic formatting or sequencing changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "stage, detail,", "detail, stage,"),
        (0, "now: { Date() }", "now: { Date(timeIntervalSince1970: 0) }"),
        (0, "makeDelivery: { globallogger.log }", "makeDelivery: { { _ in } }"),
        (0, "makeDelivery: { globallogger.log }", "makeDelivery: { { globallogger.log($0) } }"),
        (1, '.withInternetDateTime, .withFractionalSeconds', '.withInternetDateTime'),
        (1, 'detail.isEmpty ? ""', 'detail.isEmpty ? " "'),
        (1, '" \\(detail)"', '"\\(detail)"'),
        (1, '(eagle.aura.apply)', '(eagle.aura)'),
        (1, 'stage=\\(stage)', 'stage=\\(detail)'),
        (1, 'from: now()', 'from: Date(timeIntervalSince1970: 0)'),
        (1, 'let formatter =', 'let _ = now()\n        let formatter ='),
        (1, '_ detail: String = ""', '_ detail: String = "unknown"'),
        (1, 'makeDelivery()("[', 'makeDelivery()("duplicate"); makeDelivery()("['),
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
        raise AssertionError(f"Accepted mutation: {before}")
    print(f"PASS: full public diagnostic implementation, exact clock/sink bridge and whole-screen reversal; {len(mutations)} mutations rejected", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_diagnostic_log.swift").read_text()
    fixture += "\n" + reference_host() + "\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-diagnostic-log-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
