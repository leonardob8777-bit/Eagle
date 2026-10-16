#!/usr/bin/env python3
"""Public/owned Aura color decisions, exact production bindings, no SwiftUI or native execution."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioColorPresentation.swift"
MARKERS = ["private func color(for target:", "private func previewLightColor(for target:", "private func activeColor(for flag:"]
BRIDGES = ['''private func color(for target: AuraStudioTarget) -> Color {
        colorPresentation.color(for: target)
    }''', '''private func previewLightColor(for target: AuraStudioTarget) -> Color {
        colorPresentation.previewLightColor(for: target)
    }''', '''private func activeColor(for flag: UInt32) -> Color {
        colorPresentation.activeColor(for: flag)
    }''']
CONTROLLER = '''private var colorPresentation: EagleAuraStudioColorPresentation<Color> {
        EagleAuraStudioColorPresentation(
            readDraftRed: { $0 == .island ? islandRed : dockRed },
            readDraftGreen: { $0 == .island ? islandGreen : dockGreen },
            readDraftBlue: { $0 == .island ? islandBlue : dockBlue },
            readActiveRGB: { $0 == .island
                ? (activeIslandRed, activeIslandGreen, activeIslandBlue)
                : (activeDockRed, activeDockGreen, activeDockBlue)
            },
            islandFlag: Flag.island,
            mode: { mode(for: $0) },
            spectrumHue: { previewSpectrumHue(for: $0) },
            sanitize: { sanitizedChannel($0) },
            makeRGB: { Color(red: $0, green: $1, blue: $2) },
            makeHSB: { Color(hue: $0, saturation: $1, brightness: $2) }
        )
    }'''
PREFIX = '''import Foundation

/// Color selection and conversion decisions; storage and platform color construction stay injected.
@MainActor
struct EagleAuraStudioColorPresentation<ColorValue> {
    let readDraftRed: (EagleAuraStudioTarget) -> Double
    let readDraftGreen: (EagleAuraStudioTarget) -> Double
    let readDraftBlue: (EagleAuraStudioTarget) -> Double
    let readActiveRGB: (EagleAuraStudioTarget) -> (Int, Int, Int)
    let islandFlag: UInt32
    let mode: (EagleAuraStudioTarget) -> EagleAuraStudioMode
    let spectrumHue: (EagleAuraStudioMode) -> Double
    let sanitize: (Double) -> Double
    let makeRGB: (Double, Double, Double) -> ColorValue
    let makeHSB: (Double, Double, Double) -> ColorValue

    '''


def originals():
    source = public_file()
    return [declaration(source, marker) for marker in MARKERS]


def inline_color_presentation(view):
    from verify_eagle_aura_preview_styles import inline_preview_styles
    view = inline_preview_styles(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_core():
    draft, light, active = originals()
    for target in ("island", "dock"):
        for channel in ("Red", "Green", "Blue"):
            draft = replace_once(draft, f"{channel.lower()}: sanitizedChannel({target}{channel})",
                                 f"sanitize(readDraft{channel}(.{target}))")
    assert draft.count("return Color(") == 2
    draft = draft.replace("return Color(", "return makeRGB(")
    light = replace_once(light, "mode(for: target)", "mode(target)")
    light = replace_once(light, "? Color(", "? makeHSB(")
    light = replace_once(light, "hue: previewSpectrumHue(for: mode)", "spectrumHue(mode)")
    light = replace_once(light, "saturation: 0.96", "0.96")
    light = replace_once(light, "brightness: 1.0", "1.0")
    active = replace_once(active, "Flag.island", "islandFlag")
    active = replace_once(active, "(activeIslandRed, activeIslandGreen, activeIslandBlue)", "readActiveRGB(.island)")
    active = replace_once(active, "(activeDockRed, activeDockGreen, activeDockBlue)", "readActiveRGB(.dock)")
    active = replace_once(active, "return Color(", "return makeRGB(")
    for channel in ("red", "green", "blue"):
        active = replace_once(active, channel + ": Double(", "Double(")
    source = "\n\n    ".join([draft, light, active])
    for before, after, count in [("private func ", "func ", 3),
                                 ("AuraStudioTarget", "EagleAuraStudioTarget", 2),
                                 ("-> Color {", "-> ColorValue {", 3)]:
        assert source.count(before) == count
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Color factory/binding, renderer, geometry or unrelated screen changed"
    assert compact(core) == compact(expected_core()), "Color decision, read order or conversion changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "readDraftRed: { $0 == .island ? islandRed : dockRed }", "readDraftRed: { _ in dockRed }"),
        (0, "readDraftGreen: { $0 == .island ? islandGreen : dockGreen }", "readDraftGreen: { _ in islandGreen }"),
        (0, "(activeIslandRed, activeIslandGreen, activeIslandBlue)", "(activeIslandBlue, activeIslandGreen, activeIslandRed)"),
        (0, "islandFlag: Flag.island", "islandFlag: Flag.dock"),
        (0, "mode: { mode(for: $0) }", "mode: { _ in .rainbow }"),
        (0, "spectrumHue: { previewSpectrumHue(for: $0) }", "spectrumHue: { _ in 0 }"),
        (0, "sanitize: { sanitizedChannel($0) }", "sanitize: { $0 }"),
        (0, "Color(red: $0, green: $1, blue: $2)", "Color(red: $2, green: $1, blue: $0)"),
        (0, "Color(hue: $0, saturation: $1, brightness: $2)", "Color(hue: $0, saturation: $2, brightness: $1)"),
        (1, "sanitize(readDraftRed(.island))", "readDraftRed(.island)"),
        (1, "sanitize(readDraftBlue(.dock))", "sanitize(readDraftBlue(.island))"),
        (1, "return mode.usesFixedPalette", "return !mode.usesFixedPalette"),
        (1, "0.96,", "0.95,"),
        (1, "flag == islandFlag", "flag != islandFlag"),
        (1, "Double(rgb.0) / 255.0", "Double(rgb.0) / 256.0"),
        (1, "let mode = mode(target)", "let _ = spectrumHue(.rainbow)\n        let mode = mode(target)"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            values[1] = replace_once(core, before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation: {before}")
    print(f"PASS: three complete public color helpers, exact platform callbacks and whole-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_color_presentation.swift").read_text()
    fixture += "\n" + replace_once(declaration(public_file(), "private enum Flag {"),
                                    "private enum Flag", "enum Flag") + "\n"
    fields = []
    for prefix in ("island", "dock", "activeIsland", "activeDock"):
        for channel in ("Red", "Green", "Blue"):
            field = prefix + channel
            kind = "Int" if prefix.startswith("active") else "Double"
            fields.append(f'var {field}: {kind} {{ context.read{kind}("{field}") }}')
    fixture += "\nextension Host {\n" + "\n".join(fields) + "\n}\n"
    for name, members in [("PublicHost", originals()), ("OwnedHost", BRIDGES + [CONTROLLER])]:
        body = "\n".join(members).replace("private func ", "func ").replace("private var ", "var ")
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body + "\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-color-presentation-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if optimization == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            *[str(repo / ("lara/EagleCore/AuraStudio/EagleAuraStudio" + name + ".swift"))
                              for name in ("Mode", "Target", "Colors", "ColorPresentation")],
                            str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
