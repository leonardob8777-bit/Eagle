#!/usr/bin/env python3
"""Verify full Restore control extraction, lazy state reads and deferred action."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

SOURCE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioRestoreButton.swift"
MARKER = "private var restoreButton: some View"
BRIDGE = """private var restoreButton: some View {
        EagleAuraStudioRestoreButton(
            restore: { runAuraOperation(.remove, flags: selectedFlags) },
            operationInProgress: { isApplying },
            accessReady: { mgr.dsready },
            selectedFlags: { selectedFlags },
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            targetTitle: { selectedTarget.title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).button
    }"""
PREFIX = """import SwiftUI

/// Existing Restore control; the screen retains the action and native executor.
@MainActor
struct EagleAuraStudioRestoreButton {
    let restore: () -> Void
    let operationInProgress: () -> Bool
    let accessReady: () -> Bool
    let selectedFlags: () -> UInt32
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let targetTitle: () -> String
    let localizedText: (String, String) -> String

    """


def original():
    return declaration(public_file(), MARKER)


def inline_restore_button(view):
    from verify_eagle_aura_apply_button import inline_apply_button
    view = inline_apply_button(view)
    return replace_once(view, BRIDGE, original())


def expected_source():
    body = original()
    for before, after, count in [
        (MARKER, "var button: some View", 1),
        ("runAuraOperation(.remove, flags: selectedFlags)", "restore()", 1),
        ("isApplying", "operationInProgress()", 1),
        ("mgr.dsready", "accessReady()", 2),
        ("selectedFlags", "selectedFlags()", 1),
        ("applySafetyBlocked", "localSafetyBlocked()", 2),
        ("mgr.rcSafetyLocked", "remoteSafetyLocked()", 2),
        ("selectedTarget.title", "targetTitle()", 2),
        ("LaraL10n.text(", "localizedText(", 2),
        ("en: ", "", 2), ("es: ", "", 2),
    ]:
        assert body.count(before) == count, before
        body = body.replace(before, after)
    return PREFIX + body + "\n}\n"


def verify_texts(view, source):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Native operation, safety guards or unrelated screen changed"
    assert source == expected_source(), "Restore control or callback order changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, source = [(repo / p).read_text() for p in (VIEW, SOURCE)]
    verify_texts(view, source)
    mutations = [
        (0, "restore: { runAuraOperation(.remove, flags: selectedFlags) }", "restore: { runAuraOperation(.remove, flags: 1) }"),
        (0, "operationInProgress: { isApplying }", "operationInProgress: { false }"),
        (0, "accessReady: { mgr.dsready }", "accessReady: { true }"),
        (0, "localSafetyBlocked: { applySafetyBlocked }", "localSafetyBlocked: { false }"),
        (0, "remoteSafetyLocked: { mgr.rcSafetyLocked }", "remoteSafetyLocked: { false }"),
        (0, "targetTitle: { selectedTarget.title }", "targetTitle: { \"Dock\" }"),
        (1, "selectedFlags() == 0", "selectedFlags() != 0"),
        (1, "operationInProgress() || !accessReady()", "!accessReady() || operationInProgress()"),
        (1, "localSafetyBlocked() || remoteSafetyLocked()", "remoteSafetyLocked() || localSafetyBlocked()"),
        (1, "? 0.52 : 1", "? 0.5 : 1"),
        (1, ".frame(height: 36)", ".frame(height: 48)"),
        (1, 'systemImage: "arrow.counterclockwise"', 'systemImage: "arrow.clockwise"'),
        (1, 'localizedText("Restore", "Restaurar")', 'localizedText("Apply", "Aplicar")'),
        (1, "restore()\n", "let _ = selectedFlags()\n            restore()\n"),
    ]
    for index, before, after in mutations:
        values = [view, source]
        if index == 0:
            values[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            assert before in source
            values[1] = source.replace(before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print(f"PASS: entire public Restore control, full-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_restore_button.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body.replace("private var", "var") + "\n}\n"
    fixture += "\n" + replace_once(source, "import SwiftUI\n", "")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-restore-button-") as temporary:
        swift = Path(temporary) / "Fixture.swift"
        swift.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / optimization
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(swift), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
