#!/usr/bin/env python3
"""Verify unchanged Aura SwiftUI styles and callback order; recording types are not a pixel renderer."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioPreviewStyles.swift"
MARKERS = ["private func previewRingStyle(for target:","private func islandPreviewFillStyle(for mode:","private func islandRingStyle(for mode:","private func islandFillStyle(for mode:"]
BRIDGES = ["private func previewRingStyle(for target: AuraStudioTarget) -> AnyShapeStyle {\n        previewStyles.previewRingStyle(for: target)\n    }","private func islandPreviewFillStyle(for mode: AuraStudioMode) -> AnyShapeStyle {\n        previewStyles.islandPreviewFillStyle(for: mode)\n    }","private func islandRingStyle(for mode: AuraStudioMode, angle: Double) -> AnyShapeStyle {\n        previewStyles.islandRingStyle(for: mode, angle: angle)\n    }","private func islandFillStyle(for mode: AuraStudioMode, angle: Double) -> AnyShapeStyle {\n        previewStyles.islandFillStyle(for: mode, angle: angle)\n    }"]
CONTROLLER = "private var previewStyles: EagleAuraStudioPreviewStyles {\n        EagleAuraStudioPreviewStyles(\n            mode: { mode(for: $0) },\n            color: { color(for: $0) },\n            tintFillColor: { previewTintFillColor }\n        )\n    }"
PREFIX = "import SwiftUI\n\n/// Existing SwiftUI shape styles; draft mode/color reads remain supplied by the screen.\n@MainActor\nstruct EagleAuraStudioPreviewStyles {\n    let mode: (EagleAuraStudioTarget) -> EagleAuraStudioMode\n    let color: (EagleAuraStudioTarget) -> Color\n    let tintFillColor: () -> Color\n\n    "

def originals():
    source = public_file()
    return [declaration(source, marker) for marker in MARKERS]


def inline_preview_styles(view):
    from verify_eagle_aura_button_styles import inline_button_styles
    view = inline_button_styles(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_core():
    source = "\n\n    ".join(originals())
    for before, after, count in [
        ("private func ", "func ", 4),
        ("AuraStudioTarget", "EagleAuraStudioTarget", 1),
        ("AuraStudioMode", "EagleAuraStudioMode", 3),
        ("mode(for: target)", "mode(target)", 1),
        ("color(for: target)", "color(target)", 1),
        ("color(for: .island)", "color(.island)", 1),
        ("AnyShapeStyle(previewTintFillColor)", "AnyShapeStyle(tintFillColor())", 1),
    ]:
        assert source.count(before) == count, before
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Renderer, shape geometry, timeline, artwork or native execution changed"
    assert core == expected_core(), "Style construction, palette or callback sequence changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "mode: { mode(for: $0) }", "mode: { _ in .rainbow }"),
        (0, "color: { color(for: $0) }", "color: { color(for: .dock) }"),
        (0, "tintFillColor: { previewTintFillColor }", "tintFillColor: { Color.black }"),
        (1, "if mode == .rainbow", "if mode != .rainbow"),
        (1, "let mode = mode(target)", "let _ = color(target)\n        let mode = mode(target)"),
        (1, "AnyShapeStyle(color(target))", "AnyShapeStyle(color(.island))"),
        (1, "AnyShapeStyle(tintFillColor())", "AnyShapeStyle(Color.black)"),
        (1, "AnyShapeStyle(Color.purple)", "AnyShapeStyle(Color.black)"),
        (1, "AnyShapeStyle(color(.island))", "AnyShapeStyle(color(.dock))"),
        (1, "guard mode == .rainbow", "guard mode != .rainbow"),
        (1, ".pink, .orange, .yellow", ".red, .orange, .yellow"),
        (1, "Color.orange,", "Color.yellow,"),
        (1, "startPoint: .leading", "startPoint: .trailing"),
        (1, "angle: .degrees(angle)", "angle: .degrees(0)"),
        (1, ".purple, .red]", ".purple, .purple]"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            assert before in core
            values[1] = core.replace(before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print(f"PASS: four complete public style helpers, exact SwiftUI construction/bridges, full-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_preview_styles.swift").read_text()
    for name, members in [("PublicHost", originals()), ("OwnedHost", BRIDGES + [CONTROLLER])]:
        body = "\n".join(members).replace("private func ", "func ").replace("private var ", "var ")
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body + "\n}\n"
    # Only framework import is replaced. All owned/public style bodies compile
    # unchanged against recording Color/Gradient types for structural comparison.
    fixture += "\n" + replace_once(core, "import SwiftUI\n", "") + "\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-preview-styles-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            *[str(repo / ("lara/EagleCore/AuraStudio/EagleAuraStudio" + name + ".swift"))
                              for name in ("Mode", "Target")], str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
