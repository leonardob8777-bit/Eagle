#!/usr/bin/env python3
"""Aura status messages: complete public decision/text parity and lazy read order."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioProfileStatus.swift"
MARKER = "private func profileStatusText(for"
BRIDGE = "private func profileStatusText(for target: AuraStudioTarget) -> String {\n        EagleAuraStudioProfileStatus(\n            islandTarget: AuraStudioTarget.island,\n            dockTarget: AuraStudioTarget.dock,\n            islandProfileAvailable: { islandProfileAvailable },\n            islandModelUnknown: { islandCompatibility.availability == .unknown },\n            isTargetActive: { isTargetActive($0) },\n            readDockMode: { activeDockModeRaw },\n            readIslandMode: { activeIslandModeRaw },\n            activeMode: { activeMode(for: $0) },\n            draftMatchesActive: { draftMatchesActive($0) },\n            modeTitle: { $0.title },\n            localizedText: { LaraL10n.text(en: $0, es: $1) }\n        ).profileStatusText(for: target)\n    }"
PREFIX = "import Foundation\n\n/// Status decisions and messages; compatibility, state and localization stay injected.\n@MainActor\nstruct EagleAuraStudioProfileStatus<Target: Equatable> {\n    let islandTarget: Target\n    let dockTarget: Target\n    let islandProfileAvailable: () -> Bool\n    let islandModelUnknown: () -> Bool\n    let isTargetActive: (Target) -> Bool\n    let readDockMode: () -> Int\n    let readIslandMode: () -> Int\n    let activeMode: (Target) -> EagleAuraStudioMode?\n    let draftMatchesActive: (Target) -> Bool\n    let modeTitle: (EagleAuraStudioMode) -> String\n    let localizedText: (String, String) -> String\n\n    "


def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=Path(__file__).resolve().parents[1], text=True)


def original():
    return declaration(public_file(), MARKER)


def inline_status(view):
    from verify_eagle_aura_reconciliation import inline_reconciliation
    view = inline_reconciliation(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    source = original()
    for before, after, count in [
        ("private func", "func", 1), ("AuraStudioTarget", "Target", 1),
        (".island", "islandTarget", 2), (".dock", "dockTarget", 1),
        ("!islandProfileAvailable", "!islandProfileAvailable()", 1),
        ("islandCompatibility.availability == .unknown", "islandModelUnknown()", 1),
        ("activeDockModeRaw", "readDockMode()", 2),
        ("activeIslandModeRaw", "readIslandMode()", 2),
        ("activeMode(for: target)", "activeMode(target)", 1),
        ("appliedMode.title", "modeTitle(appliedMode)", 4),
        ("LaraL10n.text(", "localizedText(", 7), ("en: ", "", 7), ("es: ", "", 7),
    ]:
        assert source.count(before) == count, (before, source.count(before))
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated screen/status binding change"
    assert compact(core) == compact(expected_core()), "Status text or decision sequence changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "islandProfileAvailable: { islandProfileAvailable }", "islandProfileAvailable: { true }"),
        (0, "islandModelUnknown: { islandCompatibility.availability == .unknown }", "islandModelUnknown: { false }"),
        (0, "readDockMode: { activeDockModeRaw }", "readDockMode: { activeIslandModeRaw }"),
        (0, "modeTitle: { $0.title }", 'modeTitle: { _ in "Glow" }'),
        (0, '"eagle.auraStudio.independentProfilesMigrated"', '"changed.migration"'),
        (1, "(15...31)", "(15...32)"),
        (1, "readDockMode() == 35", "readDockMode() == 36"),
        (1, "(32...34)", "(31...34)"),
        (1, "readIslandMode() == 36", "readIslandMode() == 35"),
        (1, "!islandProfileAvailable()", "islandProfileAvailable()"),
        (1, "if draftMatchesActive(target)", "if true"),
        (1, 'localizedText("Not active", "No activo")', 'localizedText("Not active", "Activo")'),
        (1, "guard let appliedMode = activeMode(target), isTargetActive(target)", "guard isTargetActive(target), let appliedMode = activeMode(target)"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in BRIDGE:
            texts[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: complete public status body, exact callbacks and whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, member in (("PublicHost", original()), ("OwnedHost", BRIDGE)):
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     "func status(_ target: AuraStudioTarget) -> String { profileStatusText(for: target) }\n"
                     + member + "\n}\n")
    fixture = (repo / "scripts/verify_eagle_aura_profile_status.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="eagle-aura-status-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture + "\n" + "\n".join(hosts))
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
