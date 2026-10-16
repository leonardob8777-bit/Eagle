#!/usr/bin/env python3
"""Public Aura editor eligibility/fallback parity with the actual feature policy."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioModePolicy.swift"
MODE = "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"
FEATURES = "lara/config/EagleFeaturePolicy.swift"
MARKERS = ["private func policyAllows(", "private func normalizedMode("]
BRIDGES = ['''private func policyAllows(
        _ mode: AuraStudioMode,
        for target: AuraStudioTarget
    ) -> Bool {
        EagleAuraStudioModePolicy.allows(
            mode,
            isIsland: target == .island,
            pulseAllowed: { EagleFeaturePolicy.allows(.auraPulse, channel: releaseChannel) },
            rainbowAllowed: { EagleFeaturePolicy.allows(.auraRainbow, channel: releaseChannel) }
        )
    }''', '''private func normalizedMode(
        rawValue: Int,
        for target: AuraStudioTarget
    ) -> AuraStudioMode {
        EagleAuraStudioModePolicy.normalizedMode(
            rawValue: rawValue,
            allows: { policyAllows($0, for: target) }
        )
    }''']
HEADERS = ['''static func allows(
        _ mode: EagleAuraStudioMode,
        isIsland: @autoclosure () -> Bool,
        pulseAllowed: () -> Bool,
        rainbowAllowed: () -> Bool
    ) -> Bool''', '''static func normalizedMode(
        rawValue: Int,
        allows: (EagleAuraStudioMode) -> Bool
    ) -> EagleAuraStudioMode''']


def public_file(path):
    repo = Path(__file__).resolve().parents[1]
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{path}"], cwd=repo, text=True)


def originals():
    public = public_file(VIEW)
    return [declaration(public, marker) for marker in MARKERS]


def inline_policy(view):
    from verify_eagle_visual_base import inline_aura_animation_visuals
    view = inline_aura_animation_visuals(view)
    from verify_eagle_aura_draft_modes import inline_drafts
    view = inline_drafts(view)
    for bridge, old in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, old)
    return view


def expected_core():
    methods = []
    for index, method in enumerate(originals()):
        method = HEADERS[index] + method[method.index(" {"):]
        if index == 0:
            for before, after in (
                ("EagleFeaturePolicy.allows(.auraPulse, channel: releaseChannel)", "pulseAllowed()"),
                ("target == .island", "isIsland()"),
                ("EagleFeaturePolicy.allows(.auraRainbow, channel: releaseChannel)", "rainbowAllowed()"),
            ):
                method = replace_once(method, before, after)
        else:
            method = replace_once(method, "AuraStudioMode(rawValue:", "EagleAuraStudioMode(rawValue:")
            method = replace_once(method, "policyAllows(stored, for: target)", "allows(stored)")
        methods.append(method)
    return "import Foundation\n@MainActor\nenum EagleAuraStudioModePolicy {\n" + "\n".join(methods) + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(VIEW), MARKER))
    assert restored == public_file(VIEW), "Unrelated Aura change"
    assert compact(core) == compact(expected_core()), "Policy differs from public decisions/signatures"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    assert (repo / FEATURES).read_text() == public_file(FEATURES), "Feature policy changed"
    cases = [
        (0, "isIsland: target == .island", "isIsland: true"),
        (0, "pulseAllowed: { EagleFeaturePolicy.allows(.auraPulse, channel: releaseChannel) }", "pulseAllowed: { true }"),
        (0, "rainbowAllowed: { EagleFeaturePolicy.allows(.auraRainbow, channel: releaseChannel) }", "rainbowAllowed: { true }"),
        (0, "allows: { policyAllows($0, for: target) }", "allows: { _ in true }"),
        (0, '"eagle.auraStudio.island.mode"', '"eagle.auraStudio.island.modeV2"'),
        (1, "return isIsland() && rainbowAllowed()", "return rainbowAllowed() && isIsland()"),
        (1, "return pulseAllowed()", "return true"),
        (1, "?? .glow", "?? .rainbow"),
        (1, "return allows(stored) ? stored : .glow", "return stored"),
        (1, "case .glow:\n            return true", "case .glow:\n            return pulseAllowed()"),
        (1, "import Foundation", "import Foundation\nimport UIKit"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation: {before}")
    print(f"PASS: two complete public decisions, unchanged feature policy, full screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, methods in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        hosts.append("@MainActor final class " + name + ": Host {\n"
                     "override func test(_ raw: Int, _ target: AuraStudioTarget) -> Int { normalizedMode(rawValue: raw, for: target).rawValue }\n"
                     "override func eligible(_ mode: AuraStudioMode, _ target: AuraStudioTarget) -> Bool { policyAllows(mode, for: target) }\n"
                     + "\n".join(methods) + "\n}\n")
    fixture = (repo / "scripts/verify_eagle_aura_mode_policy.swift").read_text()
    # Target is the actual current public definition, not a remapping of its IDs.
    target = declaration(public_file(VIEW), "private enum AuraStudioTarget:").replace("private enum", "enum", 1)
    with tempfile.TemporaryDirectory(prefix="eagle-aura-policy-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture + "\n" + target + "\n" + "\n".join(hosts))
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / MODE),
                            str(repo / CORE), str(repo / FEATURES), str(source), "-o", str(binary)],
                           check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
