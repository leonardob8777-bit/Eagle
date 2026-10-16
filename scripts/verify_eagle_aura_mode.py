#!/usr/bin/env python3
"""Exact public Aura metadata extraction; no native execution, UI or preferences."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"
MARKER = "private enum AuraStudioMode: Int, CaseIterable, Identifiable"
BRIDGE = '''private typealias AuraStudioMode = EagleAuraStudioMode

private extension EagleAuraStudioMode {
    var title: String {
        title(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }

    var summary: String {
        summary(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
}'''


def public_view(repo):
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)


def expected_core(public):
    source = declaration(public, MARKER)
    for before, after in (
        (MARKER, "nonisolated enum EagleAuraStudioMode: Int, CaseIterable, Identifiable, Sendable"),
        ("var title: String {", "func title(localizedText: (String, String) -> String) -> String {"),
        ("var summary: String {", "func summary(localizedText: (String, String) -> String) -> String {"),
    ):
        source = replace_once(source, before, after)
    assert source.count("LaraL10n.text(") == 16
    assert source.count("en: ") == 16 and source.count("es: ") == 16
    source = source.replace("LaraL10n.text(", "localizedText(").replace("en: ", "").replace("es: ", "")
    return "import Foundation\n\n/// Shared Aura style metadata; policy, preferences, rendering and execution stay at the app boundary.\n" + source + "\n"


def verify_texts(public, view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    view = inline_policy(view)
    assert core == expected_core(public), "Mode definition or localization changed"
    assert replace_once(view, BRIDGE, declaration(public, MARKER)) == public, \
        "Aura screen/policy/native behavior changed beyond exact metadata extraction"


def verify_sources(repo):
    public = public_view(repo)
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(public, view, core)
    mutations = [
        (1, "case rainbow = 4", "case rainbow = 5"),
        (1, "case photo = 8", "case photo = 7"),
        (1, "var id: Int { rawValue }", "var id: Int { 0 }"),
        (1, 'localizedText("Glow", "Brillo")', 'localizedText("Glow", "Glow")'),
        (1, '"PhotoAuraGalaxy"', '"PhotoAuraOther"'),
        (1, "self == .rainbow || isPhotoTexture", "self == .rainbow"),
        (1, "self == .tint || self == .rainbow", "self == .glow || self == .rainbow"),
        (1, "default: return nil", 'default: return "PhotoAuraGalaxy"'),
        (1, "import Foundation", "import Foundation\nimport UIKit"),
        (0, '"eagle.auraStudio.island.mode"', '"eagle.auraStudio.island.modeV2"'),
        (0, "allows: { policyAllows($0, for: target) }", "allows: { _ in true }"),
        (0, "private var dockRed = 0.62", "private var dockRed = 0.10"),
    ]
    for index, before, after in mutations:
        changed = [view, core]
        changed[index] = replace_once(changed[index], before, after)
        try:
            verify_texts(public, *changed)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation: {before}")
    print(f"PASS: whole public enum and whole-screen reversal; {len(mutations)} negative mutations rejected", flush=True)
    return public


def main():
    repo = Path(__file__).resolve().parents[1]
    public = verify_sources(repo)
    reference = declaration(public, MARKER).replace(MARKER,
        "nonisolated enum PublicMode: Int, CaseIterable, Identifiable, Sendable")
    fixture = r'''
enum Language {
    @TaskLocal static var spanish = false
}
nonisolated enum LaraL10n {
    static func text(en: String, es: String) -> String { Language.spanish ? es : en }
}

func check() -> Int {
    let ids = [1, 2, 3, 4, 8, 9, 10, 11, 12, 13, 14]
    let assets = ["PhotoAuraGalaxy", "PhotoAuraRainbow", "PhotoAuraInferno", "PhotoAuraSky",
                  "PhotoAuraVortex", "PhotoAuraBubblegum", "PhotoAuraTraffic"]
    precondition(EagleAuraStudioMode.allCases.map(\.rawValue) == ids)
    precondition(PublicMode.allCases.map(\.rawValue) == ids)
    var count = 0
    for raw in [Int.min, Int.max] + Array(-100...1000) {
        let old = PublicMode(rawValue: raw)
        let new = EagleAuraStudioMode(rawValue: raw)
        precondition((old == nil) == (new == nil))
        if let old, let new {
            precondition(old.id == new.id)
            precondition(old.usesFixedPalette == new.usesFixedPalette)
            precondition(old.isPhotoTexture == new.isPhotoTexture)
            precondition(old.photoAssetName == new.photoAssetName)
            precondition(old.fillsIslandBackground == new.fillsIslandBackground)
            precondition(new.isPhotoTexture == (8...14).contains(raw))
            precondition(new.usesFixedPalette == (raw == 4 || raw >= 8))
            precondition(new.fillsIslandBackground == (raw == 3 || raw == 4))
            precondition(new.photoAssetName == ((8...14).contains(raw) ? assets[raw - 8] : nil))
            for spanish in [false, true, false] {
                Language.$spanish.withValue(spanish) {
                    precondition(old.title == new.title)
                    precondition(old.summary == new.summary)
                    var calls = 0
                    let title = new.title { en, es in calls += 1; return spanish ? es : en }
                    precondition(calls == 1 && title == old.title)
                    let summary = new.summary { en, es in calls += 1; return spanish ? es : en }
                    precondition(calls == 2 && summary == old.summary)
                }
            }
        }
        count += 1
    }
    return count
}
@main struct Main {
    static func main() async {
        let direct = check()
        let detached = await Task.detached { check() }.value
        print("PASS: \(direct) raw-value cases direct/\(detached) detached; all 11 styles, assets, palette/fill flags and 33 language transitions per run")
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="eagle-aura-metadata-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text("import Foundation\n" + reference + "\n" + BRIDGE + "\n" + fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
