#!/usr/bin/env python3
"""Compare owned Aura colors with complete public members and observable state traces."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioColors.swift"
MARKERS = ["private var presets:", "private func presetIsSelected(",
           "private func setSelectedRGB(", "private func sanitizedChannel(", "private func channel255("]
BRIDGES = ['''private var presets: [(name: String, red: Double, green: Double, blue: Double)] {
        EagleAuraStudioColors.presets(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }''', '''private func presetIsSelected(
        _ preset: (name: String, red: Double, green: Double, blue: Double)
    ) -> Bool {
        EagleAuraStudioColors.presetIsSelected(preset, selectedRGB: {
            selectedTarget == .island
                ? (sanitizedChannel(islandRed), sanitizedChannel(islandGreen), sanitizedChannel(islandBlue))
                : (sanitizedChannel(dockRed), sanitizedChannel(dockGreen), sanitizedChannel(dockBlue))
        })
    }''', '''private func setSelectedRGB(red: Double, green: Double, blue: Double) {
        EagleAuraStudioColors.setSelectedRGB(
            red: red, green: green, blue: blue,
            isIsland: selectedTarget == .island,
            writeIsland: { islandRed = $0; islandGreen = $1; islandBlue = $2 },
            writeDock: { dockRed = $0; dockGreen = $1; dockBlue = $2 }
        )
    }''', '''private func sanitizedChannel(_ value: Double, fallback: Double = 0) -> Double {
        EagleAuraStudioColors.sanitizedChannel(value, fallback: fallback)
    }''', '''private func channel255(_ value: Double) -> Int {
        EagleAuraStudioColors.channel255(value)
    }''']


def originals():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    return [declaration(public, m) for m in MARKERS]


def inline_colors(view):
    from verify_eagle_aura_profile_state import inline_profiles
    view = inline_profiles(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return view


def expected_core():
    source = "\n".join(originals())
    substitutions = [
        ("private var presets:", "static func presets(localizedText: (String, String) -> String) ->", 1),
        ("private func", "static func", 4),
        ("LaraL10n.text(en: ", "localizedText(", 4), (", es: ", ", ", 4),
        ("blue: Double)\n    ) -> Bool", "blue: Double),\n        selectedRGB: () -> (Double, Double, Double)\n    ) -> Bool", 1),
        ("let selectedRGB = selectedTarget == .island\n            ? (sanitizedChannel(islandRed), sanitizedChannel(islandGreen), sanitizedChannel(islandBlue))\n            : (sanitizedChannel(dockRed), sanitizedChannel(dockGreen), sanitizedChannel(dockBlue))", "let selectedRGB = selectedRGB()", 1),
        ("setSelectedRGB(red: Double, green: Double, blue: Double)", "setSelectedRGB(\n        red: Double, green: Double, blue: Double,\n        isIsland: @autoclosure () -> Bool,\n        writeIsland: (Double, Double, Double) -> Void,\n        writeDock: (Double, Double, Double) -> Void\n    )", 1),
        ("selectedTarget == .island", "isIsland()", 1),
        ("islandRed = nextRed\n            islandGreen = nextGreen\n            islandBlue = nextBlue", "writeIsland(nextRed, nextGreen, nextBlue)", 1),
        ("dockRed = nextRed\n            dockGreen = nextGreen\n            dockBlue = nextBlue", "writeDock(nextRed, nextGreen, nextBlue)", 1),
    ]
    for before, after, count in substitutions:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return "import Foundation\n@MainActor\nenum EagleAuraStudioColors {\n" + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy, public_file
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(VIEW), MARKER))
    assert restored == public_file(VIEW), "Unrelated Aura screen change"
    assert compact(core) == compact(expected_core()), "Color data/rules diverge"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "writeIsland: { islandRed = $0; islandGreen = $1; islandBlue = $2 }", "writeIsland: { dockRed = $0; dockGreen = $1; dockBlue = $2 }"),
        (0, "isIsland: selectedTarget == .island", "isIsland: true"),
        (0, "EagleAuraStudioColors.presets(localizedText: { LaraL10n.text(en: $0, es: $1) })", "EagleAuraStudioColors.presets(localizedText: { LaraL10n.text(en: $1, es: $0) })"),
        (0, '"eagle.auraStudio.independentProfilesMigrated"', '"changed.migration"'),
        (1, "0.10, 0.78, 1.00", "0.10, 0.79, 1.00"),
        (1, '"Verde ácido"', '"Verde"'),
        (1, "let tolerance = 0.002", "let tolerance = 0.003"),
        (1, "abs(selectedRGB.0 - preset.red) < tolerance", "abs(selectedRGB.0 - preset.red) <= tolerance"),
        (1, "writeIsland(nextRed, nextGreen, nextBlue)", "writeDock(nextRed, nextGreen, nextBlue)"),
        (1, "writeDock(nextRed, nextGreen, nextBlue)", "writeDock(nextBlue, nextGreen, nextRed)"),
        (1, "guard value.isFinite else { return fallback }", "guard value.isFinite else { return 0 }"),
        (1, "max(0, min(1, value))", "min(1, value)"),
        (1, "* 255).rounded()", "* 255).rounded(.down)"),
    ]
    for index, before, after in cases:
        texts = [view, core]; texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: five complete public members, whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, members in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     "func palette() -> [Preset] { presets }\n"
                     "func matches(_ p: Preset) -> Bool { presetIsSelected(p) }\n"
                     "func set(_ r: Double, _ g: Double, _ b: Double) { setSelectedRGB(red: r, green: g, blue: b) }\n"
                     "func sanitize(_ v: Double, _ f: Double) -> Double { sanitizedChannel(v, fallback: f) }\n"
                     "func byte(_ v: Double) -> Int { channel255(v) }\n"
                     + "\n".join(members) + "\n}\n")
    fixture = (repo / "scripts/verify_eagle_aura_colors.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="eagle-aura-colors-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture + "\n" + "\n".join(hosts))
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
