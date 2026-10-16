#!/usr/bin/env python3
"""Verify the complete public color binding and its lazy screen connections."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

SOURCE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioColorBinding.swift"
MARKER = "private var auraColorBinding: Binding<Color>"
BRIDGE = """private var auraColorBinding: Binding<Color> {
        EagleAuraStudioColorBinding(
            readColor: { auraColor },
            readMode: { selectedMode },
            writeMode: { selectedMode = $0 },
            writeRGB: { setSelectedRGB(red: $0, green: $1, blue: $2) }
        ).binding
    }"""
PREFIX = """import SwiftUI
import UIKit

/// Existing color-picker binding; UIKit conversion stays outside Core.
@MainActor
struct EagleAuraStudioColorBinding {
    let readColor: () -> Color
    let readMode: () -> EagleAuraStudioMode
    let writeMode: (EagleAuraStudioMode) -> Void
    let writeRGB: (Double, Double, Double) -> Void

    """


def original():
    return declaration(public_file(), MARKER)


def inline_color_binding(view):
    from verify_eagle_aura_restore_button import inline_restore_button
    view = inline_restore_button(view)
    return replace_once(view, BRIDGE, original())


def expected_source():
    body = original()
    for before, after in [
        (MARKER, "var binding: Binding<Color>"),
        ("get: { auraColor }", "get: { readColor() }"),
        ("selectedMode.usesFixedPalette", "readMode().usesFixedPalette"),
        ("selectedMode = .glow", "writeMode(.glow)"),
        ("setSelectedRGB(", "writeRGB("),
        ("red: Double(nextRed)", "Double(nextRed)"),
        ("green: Double(nextGreen)", "Double(nextGreen)"),
        ("blue: Double(nextBlue)", "Double(nextBlue)"),
    ]:
        body = replace_once(body, before, after)
    return PREFIX + body + "\n}\n"


def verify_texts(view, source):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated screen, native execution or color consumers changed"
    assert source == expected_source(), "Color binding conversion, ordering or branches changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, source = [(repo / p).read_text() for p in (VIEW, SOURCE)]
    verify_texts(view, source)
    mutations = [
        (0, "readColor: { auraColor }", "readColor: { Color.black }"),
        (0, "readMode: { selectedMode }", "readMode: { .glow }"),
        (0, "writeMode: { selectedMode = $0 }", "writeMode: { _ in }"),
        (0, "setSelectedRGB(red: $0, green: $1, blue: $2)", "setSelectedRGB(red: $2, green: $1, blue: $0)"),
        (1, "if readMode().usesFixedPalette", "if !readMode().usesFixedPalette"),
        (1, "writeMode(.glow)", "writeMode(.rainbow)"),
        (1, "var nextRed: CGFloat = 0", "var nextRed: CGFloat = 1"),
        (1, "var alpha: CGFloat = 0", "var alpha: CGFloat = 1"),
        (1, "else { return }", "else { writeRGB(0, 0, 0); return }"),
        (1, "Double(nextBlue)", "Double(alpha)"),
        (1, "let resolved = UIColor(color)", "let _ = readColor()\n                let resolved = UIColor(color)"),
        (1, "get: { readColor() }", "get: { let _ = readMode(); return readColor() }"),
    ]
    for index, before, after in mutations:
        values = [view, source]
        if index == 0:
            values[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            values[1] = replace_once(source, before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print(f"PASS: complete public picker binding, exact callbacks and whole-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_color_binding.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body.replace("private var", "var") + "\n}\n"
    fixture += "\n" + replace_once(source, "import SwiftUI\nimport UIKit\n", "")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-color-binding-") as temporary:
        swift = Path(temporary) / "Fixture.swift"
        swift.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / optimization
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(swift), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
