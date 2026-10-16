#!/usr/bin/env python3
"""Compare actual public Aura preview calculations and production bridges, without rendering or native calls."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioPreview.swift"
MARKERS = ["private var previewTintFillColor:", "private func previewSpectrumHue(",
           "private func auraSpectrumPhase(", "private func auraPulseLevel("]
BRIDGES = ['''private var previewTintFillColor: Color {
        EagleAuraStudioPreview.tintFill(
            readRed: { sanitizedChannel(islandRed) },
            readGreen: { sanitizedChannel(islandGreen) },
            readBlue: { sanitizedChannel(islandBlue) },
            makeColor: { Color(red: $0, green: $1, blue: $2) }
        )
    }''', '''private func previewSpectrumHue(for mode: AuraStudioMode) -> Double {
        EagleAuraStudioPreview.spectrumHue(for: mode, now: { Date() })
    }''', '''private func auraSpectrumPhase(at date: Date) -> Double {
        EagleAuraStudioPreview.spectrumPhase(at: date)
    }''', '''private func auraPulseLevel(at date: Date) -> Double {
        EagleAuraStudioPreview.pulseLevel(at: date)
    }''']
PREFIX = "import Foundation\n\n/// Preview-only color and motion calculations; rendering, clock and color reads are supplied by the view.\nnonisolated enum EagleAuraStudioPreview {\n"
TINT_SIGNATURE = '''static func tintFill<Color>(
        readRed: () -> Double,
        readGreen: () -> Double,
        readBlue: () -> Double,
        makeColor: (Double, Double, Double) -> Color
    ) -> Color {'''

def originals():
    source = public_file()
    return [declaration(source, marker) for marker in MARKERS]

def inline_preview(view):
    from verify_eagle_aura_capability import inline_capability
    view = inline_capability(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return view

def expected_core():
    from verify_eagle_aura_preview_size import expected_method
    tint, hue, phase, pulse = originals()
    tint = replace_once(tint, "private var previewTintFillColor: Color {", TINT_SIGNATURE)
    for channel in ("Red", "Green", "Blue"):
        tint = replace_once(tint, f"sanitizedChannel(island{channel})", f"read{channel}()")
    tint = replace_once(tint, "return Color(", "return makeColor(")
    for channel in ("red", "green", "blue"):
        tint = replace_once(tint, f"{channel}: {channel} * scale", f"{channel} * scale")
    hue = replace_once(hue, "private func previewSpectrumHue(for mode: AuraStudioMode)",
                       "static func spectrumHue(for mode: EagleAuraStudioMode, now: () -> Date)")
    hue = replace_once(hue, "auraSpectrumPhase(at: Date())", "spectrumPhase(at: now())")
    phase = replace_once(phase, "private func auraSpectrumPhase", "static func spectrumPhase")
    pulse = replace_once(pulse, "private func auraPulseLevel", "static func pulseLevel")
    return PREFIX + "    " + expected_method() + "\n\n" + "\n\n".join([tint, hue, phase, pulse]) + "\n}\n"

def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Preview renderer, native geometry or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Preview calculation or lazy reads changed"

def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "readRed: { sanitizedChannel(islandRed) }", "readRed: { sanitizedChannel(dockRed) }"),
        (0, "makeColor: { Color(red: $0, green: $1, blue: $2) }", "makeColor: { Color(red: $2, green: $1, blue: $0) }"),
        (0, "EagleAuraStudioPreview.spectrumHue(for: mode, now: { Date() })", "EagleAuraStudioPreview.spectrumHue(for: .rainbow, now: { Date() })"),
        # The accepted visual projection now pins 60 fps; reject reverting it.
        (0, "minimumInterval: 1.0 / 60.0", "minimumInterval: 1.0 / 30.0"),
        # Native width constants moved to DisplayGeometry and have their own gate.
        # Keep this whole-screen mutation aimed at the actual preview renderer.
        (0, ".frame(width: 190, height: 55)", ".frame(width: 191, height: 55)"),
        (1, "let red = readRed()\n        let green = readGreen()", "let green = readGreen()\n        let red = readRed()"),
        (1, "112.0 / 255.0", "120.0 / 255.0"),
        (1, "return 0.73", "return 0.74"),
        (1, "return 0\n", "return spectrumPhase(at: now())\n"),
        (1, "/ 5.2", "/ 5.0"),
        (1, "/ 2.3", "/ 2.2"),
        (1, "floor(cycles)", "ceil(cycles)"),
        (1, "0.58 + (0.42 * wave)", "0.60 + (0.40 * wave)"),
        (1, "cos(phase * 2 * Double.pi)", "sin(phase * 2 * Double.pi)"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        assert before in values[index]
        values[index] = values[index].replace(before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation: {before}")
    print(f"PASS: four public preview implementations, exact bridges/whole-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_preview.swift").read_text()
    for name, methods in [("PublicHost", originals()), ("OwnedHost", BRIDGES)]:
        body = "\n".join(methods).replace("private ", "").replace("Date()", "fixtureNow()")
        fixture += f"\n@MainActor struct {name}: PreviewHost {{\nlet context: Context\n{body}\n}}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-preview-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioColors.swift"),
                            str(repo / CORE), str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=90)

if __name__ == "__main__":
    main()
