#!/usr/bin/env python3
"""Compare extracted Apply colors with public helpers, including lazy read order."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

SOURCE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioButtonStyles.swift"
NAMES = ("applyButtonForeground", "applyButtonBackground")
BRIDGES = [f"private var {name}: Color {{\n        buttonStyles.{name}\n    }}" for name in NAMES]
CONTROLLER = """private var buttonStyles: EagleAuraStudioButtonStyles {
        EagleAuraStudioButtonStyles(
            isDisabled: { isApplyButtonDisabled },
            isDark: { colorScheme == .dark },
            accessReady: { mgr.dsready },
            actionText: { EagleVisualTheme.actionText },
            actionFill: { EagleVisualTheme.actionFill }
        )
    }"""
PREFIX = """import SwiftUI

/// Existing Apply colors only. Eligibility and execution remain at their existing boundaries.
@MainActor
struct EagleAuraStudioButtonStyles {
    let isDisabled: () -> Bool
    let isDark: () -> Bool
    let accessReady: () -> Bool
    let actionText: () -> Color
    let actionFill: () -> Color

    """


def originals():
    return [declaration(public_file(), "private var " + name + ": Color") for name in NAMES]


def inline_button_styles(view):
    from verify_eagle_aura_preview_size import inline_preview_size
    view = inline_preview_size(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_source():
    body = "\n\n    ".join(originals())
    for before, after, count in [
        ("private var", "var", 2),
        ("isApplyButtonDisabled", "isDisabled()", 2),
        ("colorScheme == .dark", "isDark()", 3),
        ("mgr.dsready", "accessReady()", 1),
        ("EagleVisualTheme.actionText", "actionText()", 1),
        ("EagleVisualTheme.actionFill", "actionFill()", 1),
    ]:
        assert body.count(before) == count, before
        body = body.replace(before, after)
    return PREFIX + body + "\n}\n"


def verify_texts(view, source):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Full public screen reversal failed"
    assert source == expected_source(), "Apply color values or evaluation sequence changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, source = [(repo / path).read_text() for path in (VIEW, SOURCE)]
    verify_texts(view, source)
    mutations = [
        (0, "isDisabled: { isApplyButtonDisabled }", "isDisabled: { false }"),
        (0, "isDark: { colorScheme == .dark }", "isDark: { true }"),
        (0, "accessReady: { mgr.dsready }", "accessReady: { true }"),
        (0, "actionText: { EagleVisualTheme.actionText }", "actionText: { EagleVisualTheme.actionFill }"),
        (0, "actionFill: { EagleVisualTheme.actionFill }", "actionFill: { Color.white }"),
        (1, "if !accessReady()", "if accessReady()"),
        (1, "if isDisabled()", "if !isDisabled()"),
        (1, "0.86", "0.85"), (1, "0.78", "0.77"),
        (1, "0.24", "0.23"), (1, "0.13", "0.12"),
        (1, "0.14", "0.13"), (1, "0.09", "0.08"),
        (1, "Color.red", "Color.primary"),
        (1, "return actionFill()", "let _ = isDark()\n        return actionFill()"),
    ]
    for index, before, after in mutations:
        values = [view, source]
        if index == 0:
            values[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            values[1] = replace_once(source, before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print(f"PASS: two complete Apply color helpers, full-screen reversal, {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_button_styles.swift").read_text()
    for name, members in [("PublicHost", originals()), ("OwnedHost", BRIDGES + [CONTROLLER])]:
        body = "\n".join(members).replace("private var ", "var ")
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body + "\n}\n"
    fixture += "\n" + replace_once(source, "import SwiftUI\n", "")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-button-styles-") as temporary:
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
