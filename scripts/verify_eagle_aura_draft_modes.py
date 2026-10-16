#!/usr/bin/env python3
"""Public/owned Aura draft sequencing with recording state and injected policy."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioDraftModes.swift"
ROOT = "lara/EagleCore/AuraStudio/"
MARKERS = ["private func normalizeDraftModesForPolicy()", "private var selectedMode:",
           "private var availableModes:", "private func mode(for target:"]
BRIDGES = ['''private func normalizeDraftModesForPolicy() {
        draftModes.normalizeDraftModesForPolicy()
    }''', '''private var selectedMode: AuraStudioMode {
        get { draftModes.selectedMode }
        nonmutating set { draftModes.selectedMode = newValue }
    }''', '''private var availableModes: [AuraStudioMode] {
        draftModes.availableModes
    }''', '''private func mode(for target: AuraStudioTarget) -> AuraStudioMode {
        draftModes.mode(for: target)
    }''']
CONTROLLER = '''private var draftModes: EagleAuraStudioDraftModes<AuraStudioTarget> {
        EagleAuraStudioDraftModes(
            islandTarget: .island,
            dockTarget: .dock,
            readTarget: { selectedTarget },
            readIsland: { islandModeRaw },
            writeIsland: { islandModeRaw = $0 },
            readDock: { dockModeRaw },
            writeDock: { dockModeRaw = $0 },
            normalize: { normalizedMode(rawValue: $0, for: $1) },
            allows: { policyAllows($0, for: $1) }
        )
    }'''
PREFIX = '''import Foundation
@MainActor
struct EagleAuraStudioDraftModes<Target: Equatable> {
    let islandTarget: Target
    let dockTarget: Target
    let readTarget: () -> Target
    let readIsland: () -> Int
    let writeIsland: (Int) -> Void
    let readDock: () -> Int
    let writeDock: (Int) -> Void
    let normalize: (Int, Target) -> EagleAuraStudioMode
    let allows: (EagleAuraStudioMode, Target) -> Bool
'''


def originals():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    return [declaration(public, m) for m in MARKERS]


def inline_drafts(view):
    from verify_eagle_aura_colors import inline_colors
    view = inline_colors(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_core():
    source = "\n".join(originals())
    substitutions = [
        ("private ", "", 4),
        ("AuraStudioMode", "EagleAuraStudioMode", 4),
        ("AuraStudioTarget", "Target", 1),
        ("normalizedMode(rawValue: islandModeRaw, for: .island)", "normalize(readIsland(), islandTarget)", 1),
        ("normalizedMode(rawValue: dockModeRaw, for: .dock)", "normalize(readDock(), dockTarget)", 1),
        ("islandModeRaw != island.rawValue { islandModeRaw = island.rawValue }", "readIsland() != island.rawValue { writeIsland(island.rawValue) }", 1),
        ("dockModeRaw != dock.rawValue { dockModeRaw = dock.rawValue }", "readDock() != dock.rawValue { writeDock(dock.rawValue) }", 1),
        ("islandModeRaw = newValue.rawValue", "writeIsland(newValue.rawValue)", 1),
        ("dockModeRaw = newValue.rawValue", "writeDock(newValue.rawValue)", 1),
        ("islandModeRaw", "readIsland()", 2), ("dockModeRaw", "readDock()", 2),
        ("selectedTarget", "readTarget()", 5),
        (".island", "islandTarget", 3),
        ("normalizedMode(rawValue: rawValue, for: readTarget())", "normalize(rawValue, readTarget())", 1),
        ("normalizedMode(rawValue: rawValue, for: target)", "normalize(rawValue, target)", 1),
        ("policyAllows(newValue, for: readTarget())", "allows(newValue, readTarget())", 1),
        ("policyAllows($0, for: readTarget())", "allows($0, readTarget())", 1),
    ]
    for before, after, count in substitutions:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy, public_file
    from verify_eagle_aura_mode import BRIDGE, MARKER
    # inline_policy itself reverses this step before reverting its own bridges.
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(VIEW), MARKER))
    assert restored == public_file(VIEW), "Unrelated Aura screen change"
    assert compact(core) == compact(expected_core()), "Draft reads/writes/constraints diverge"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "readIsland: { islandModeRaw }", "readIsland: { dockModeRaw }"),
        (0, "writeDock: { dockModeRaw = $0 }", "writeDock: { islandModeRaw = $0 }"),
        (0, "readTarget: { selectedTarget }", "readTarget: { .island }"),
        (0, "normalize: { normalizedMode(rawValue: $0, for: $1) }", "normalize: { _, _ in .glow }"),
        (0, '"eagle.auraStudio.independentProfilesMigrated"', '"changed.migration"'),
        (1, "guard allows(newValue, readTarget()) else { return }", "// guard removed"),
        (1, "writeIsland(newValue.rawValue)", "writeDock(newValue.rawValue)"),
        (1, "return normalize(rawValue, readTarget())", "return normalize(rawValue, islandTarget)"),
        (1, "if readIsland() != island.rawValue", "if true"),
        (1, "if readDock() != dock.rawValue", "if true"),
        (1, "let dock = normalize(readDock(), dockTarget)", "let dock = normalize(readDock(), islandTarget)"),
        (1, "allCases.filter { allows($0, readTarget()) }", "allCases.filter { allows($0, islandTarget) }"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in CONTROLLER:
            # Other extracted controllers now also read selectedTarget. Mutate
            # this exact draft controller, not an ambiguous whole-screen match.
            texts[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: four complete public members, exact state bridge/screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, members in (("PublicHost", originals()), ("OwnedHost", BRIDGES + [CONTROLLER])):
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     "func act(_ operation: Int) -> [Int] {\n"
                     "switch operation {\ncase 0: return [selectedMode.rawValue]\n"
                     "case 1: return availableModes.map(\\.rawValue)\n"
                     "case 2: return [mode(for: .island).rawValue]\ncase 3: return [mode(for: .dock).rawValue]\n"
                     "case 4: normalizeDraftModesForPolicy(); return []\n"
                     "default: selectedMode = AuraStudioMode.allCases[operation - 5]; return []\n}\n}\n"
                     + "\n".join(members) + "\n}\n")
    fixture = (repo / "scripts/verify_eagle_aura_draft_modes.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="eagle-aura-drafts-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture + "\n" + "\n".join(hosts))
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(repo / ROOT / "EagleAuraStudioMode.swift"),
                            str(repo / ROOT / "EagleAuraStudioModePolicy.swift"), str(source), "-o", str(binary)],
                           check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
