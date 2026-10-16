#!/usr/bin/env python3
"""Check preview-only dimensions without changing native placement geometry."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioPreview.swift"
MARKER = "private var compactIslandPreviewSize: CGSize"
BRIDGE = """private var compactIslandPreviewSize: CGSize {
        EagleAuraStudioPreview.compactIslandSize(
            readLogicalWidth: { displayGeometry.logicalSize.width },
            readCompactWidth: { displayGeometry.compactIslandFrame.width },
            readCompactHeight: { displayGeometry.compactIslandFrame.height }
        )
    }"""
SIGNATURE = """static func compactIslandSize(
        readLogicalWidth: () -> CGFloat,
        readCompactWidth: () -> CGFloat,
        readCompactHeight: () -> CGFloat
    ) -> CGSize {"""


def original():
    return declaration(public_file(), MARKER)


def inline_preview_size(view):
    from verify_eagle_aura_color_binding import inline_color_binding
    view = inline_color_binding(view)
    return replace_once(view, BRIDGE, original())


def expected_method():
    body = replace_once(original(), MARKER + " {", SIGNATURE)
    body = replace_once(body, "displayGeometry.logicalSize.width", "readLogicalWidth()")
    assert body.count("displayGeometry.compactIslandFrame.width") == 2
    body = body.replace("displayGeometry.compactIslandFrame.width", "readCompactWidth()")
    return replace_once(body, "displayGeometry.compactIslandFrame.height", "readCompactHeight()")


def verify_texts(view, core):
    from verify_eagle_aura_preview import expected_core
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Preview/native geometry or other screen logic changed"
    assert declaration(core, "static func compactIslandSize(") == expected_method()
    assert compact(core) == compact(expected_core()), "Other preview calculations changed"
    # Explicitly protect the shared geometry type, not only the preview's numerical output.
    assert declaration(restored, "struct AuraStudioDisplayGeometry") == declaration(public_file(), "struct AuraStudioDisplayGeometry")


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "readLogicalWidth: { displayGeometry.logicalSize.width }", "readLogicalWidth: { displayGeometry.logicalSize.height }"),
        (0, "readCompactWidth: { displayGeometry.compactIslandFrame.width }", "readCompactWidth: { displayGeometry.dockAuraFrame.width }"),
        (0, "readCompactHeight: { displayGeometry.compactIslandFrame.height }", "readCompactHeight: { displayGeometry.compactIslandFrame.width }"),
        (0, "compactIslandFrame(readModel: { devicemachine() })", "compactIslandFrame(readModel: { \"iPhone15,2\" })"),
        (1, "max(readLogicalWidth(), 1)", "max(readLogicalWidth(), 2)"),
        (1, "CGFloat = 318", "CGFloat = 319"),
        (1, "max(96, min(122, scaledWidth))", "max(95, min(122, scaledWidth))"),
        (1, "max(96, min(122, scaledWidth))", "max(96, min(123, scaledWidth))"),
        (1, "max(31, width * aspect)", "max(32, width * aspect)"),
        (1, "max(readCompactWidth(), 1)", "max(readCompactHeight(), 1)"),
        (1, "let aspect = readCompactHeight()", "let aspect = readCompactWidth()"),
        (1, "let logicalWidth = max(readLogicalWidth(), 1)", "let width = readCompactWidth()\n        let logicalWidth = max(readLogicalWidth(), 1)"),
        (1, "logicalWidth * canvasWidth", "canvasWidth / logicalWidth"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        values[index] = replace_once(values[index], before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print(f"PASS: complete public preview-size helper, exact native geometry/full-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_preview_size.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body.replace("private var", "var") + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-preview-size-") as temporary:
        swift = Path(temporary) / "Fixture.swift"
        swift.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / optimization
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / CORE), str(swift), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
