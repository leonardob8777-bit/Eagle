#!/usr/bin/env python3
"""Compare complete public Apply control and preserve deferred screen action."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

SOURCE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioApplyButton.swift"
MARKER = "private var applyButton: some View"
BRIDGE = """private var applyButton: some View {
        EagleAuraStudioApplyButton(
            apply: { runAuraOperation(.apply(selectedMode), flags: selectedFlags) },
            accessReady: { mgr.dsready },
            modeTitle: { selectedMode.title },
            foreground: { applyButtonForeground },
            background: { applyButtonBackground },
            isDark: { colorScheme == .dark },
            surfaceBorder: { EagleVisualTheme.surfaceBorder(for: colorScheme) },
            isDisabled: { isApplyButtonDisabled },
            targetTitle: { selectedTarget.title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).button
    }"""
PREFIX = """import SwiftUI

/// Existing Apply control; the screen retains eligibility and native execution.
@MainActor
struct EagleAuraStudioApplyButton {
    let apply: () -> Void
    let accessReady: () -> Bool
    let modeTitle: () -> String
    let foreground: () -> Color
    let background: () -> Color
    let isDark: () -> Bool
    let surfaceBorder: () -> Color
    let isDisabled: () -> Bool
    let targetTitle: () -> String
    let localizedText: (String, String) -> String

    """


def original():
    return declaration(public_file(), MARKER)


def visual_original():
    # The user's accepted visual base changed only this style. Keep all public
    # actions, enablement, labels, reads and borders as the comparison oracle.
    return replace_once(original(), ".buttonStyle(.plain)", ".buttonStyle(EagleApplyButtonStyle(fill: nil))")


def inline_apply_button(view):
    from verify_eagle_aura_surface_picker import inline_surface_picker
    view = inline_surface_picker(view)
    return replace_once(view, BRIDGE, original())


def expected_source():
    body = visual_original()
    for before, after, count in [
        (MARKER, "var button: some View", 1),
        ("runAuraOperation(.apply(selectedMode), flags: selectedFlags)", "apply()", 1),
        ("mgr.dsready", "accessReady()", 3),
        ("selectedMode.title", "modeTitle()", 2),
        ("applyButtonForeground", "foreground()", 1),
        ("applyButtonBackground", "background()", 1),
        ("EagleVisualTheme.surfaceBorder(for: colorScheme)", "surfaceBorder()", 1),
        ("colorScheme == .dark", "isDark()", 1),
        ("isApplyButtonDisabled", "isDisabled()", 1),
        ("selectedTarget.title", "targetTitle()", 2),
        ("LaraL10n.text(", "localizedText(", 3),
        ("en: ", "", 3), ("es: ", "", 3),
    ]:
        assert body.count(before) == count, before
        body = body.replace(before, after)
    return PREFIX + body + "\n}\n"


def verify_texts(view, source):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Native action, guards or unrelated screen changed"
    assert source == expected_source(), "Apply rendering or evaluation order changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, source = [(repo / p).read_text() for p in (VIEW, SOURCE)]
    verify_texts(view, source)
    mutations = [
        (0, "apply: { runAuraOperation(.apply(selectedMode), flags: selectedFlags) }", "apply: { runAuraOperation(.apply(.glow), flags: selectedFlags) }"),
        (0, "accessReady: { mgr.dsready }", "accessReady: { true }"),
        (0, "foreground: { applyButtonForeground }", "foreground: { applyButtonBackground }"),
        (0, "background: { applyButtonBackground }", "background: { applyButtonForeground }"),
        (0, "isDisabled: { isApplyButtonDisabled }", "isDisabled: { false }"),
        (0, "isDark: { colorScheme == .dark }", "isDark: { false }"),
        (0, "targetTitle: { selectedTarget.title }", "targetTitle: { \"Dock\" }"),
        (1, "systemImage: accessReady()", "systemImage: !accessReady()"),
        (1, ".frame(height: 48)", ".frame(height: 36)"),
        (1, "cornerRadius: 15", "cornerRadius: 16"),
        (1, "? 0.42 : 0.30", "? 0.30 : 0.42"),
        (1, ".disabled(isDisabled())", ".disabled(false)"),
        (1, '"System Access Required"', '"Ready"'),
        (1, "apply()\n", "let _ = modeTitle()\n            apply()\n"),
        (1, "lineWidth: 1", "lineWidth: 2"),
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
    print(f"PASS: public Apply action/enablement/labels with accepted Eagle visual style; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_apply_button.swift").read_text()
    for name, body in [("PublicHost", visual_original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body.replace("private var", "var") + "\n}\n"
    fixture += "\n" + replace_once(source, "import SwiftUI\n", "")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-apply-button-") as temporary:
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
