#!/usr/bin/env python3
"""Applied Aura state: exact public decisions, bindings and read traces."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/AuraStudioView.swift"
CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioProfileState.swift"
MARKERS = ["private func isTargetActive(", "private func activeMode(for", "private func draftMatchesActive("]
BRIDGES = ['''private func isTargetActive(_ target: AuraStudioTarget) -> Bool {
        profileState.isTargetActive(target)
    }''', '''private func activeMode(for target: AuraStudioTarget) -> AuraStudioMode? {
        profileState.activeMode(for: target)
    }''', '''private func draftMatchesActive(_ target: AuraStudioTarget) -> Bool {
        profileState.draftMatchesActive(target)
    }''']
CONTROLLER = '''private var profileState: EagleAuraStudioProfileState<AuraStudioTarget> {
        EagleAuraStudioProfileState(
            readActiveFlags: { EagleStoredThemeValues.flags(activeFlagsRaw) },
            flag: { flag(for: $0) },
            readActiveMode: { $0 == .island ? activeIslandModeRaw : activeDockModeRaw },
            mode: { mode(for: $0) },
            readDraftRGB: { target in
                if target == .island {
                    return (
                        Int((islandRed * 255).rounded()),
                        Int((islandGreen * 255).rounded()),
                        Int((islandBlue * 255).rounded())
                    )
                } else {
                    return (
                        Int((dockRed * 255).rounded()),
                        Int((dockGreen * 255).rounded()),
                        Int((dockBlue * 255).rounded())
                    )
                }
            },
            readActiveRGB: { $0 == .island
                ? (activeIslandRed, activeIslandGreen, activeIslandBlue)
                : (activeDockRed, activeDockGreen, activeDockBlue)
            }
        )
    }'''
PREFIX = '''import Foundation
@MainActor
struct EagleAuraStudioProfileState<Target> {
    let readActiveFlags: () -> UInt32
    let flag: (Target) -> UInt32
    let readActiveMode: (Target) -> Int
    let mode: (Target) -> EagleAuraStudioMode
    let readDraftRGB: (Target) -> (Int, Int, Int)
    let readActiveRGB: (Target) -> (Int, Int, Int)
'''


def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=Path(__file__).resolve().parents[1], text=True)


def originals():
    source = public_file()
    return [declaration(source, m) for m in MARKERS]


def inline_profiles(view):
    from verify_eagle_aura_profile_status import inline_status
    view = inline_status(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return replace_once(view, "\n\n    " + CONTROLLER, "")


def expected_core():
    source = "\n".join(originals())
    start = source.index("        let draftRGB: (Int, Int, Int)")
    end = source.index("        return draftRGB == activeRGB", start)
    source = source[:start] + "        let draftRGB = readDraftRGB(target)\n        let activeRGB = readActiveRGB(target)\n" + source[end:]
    for before, after, count in [
        ("private func", "func", 3), ("AuraStudioTarget", "Target", 3),
        ("AuraStudioMode", "EagleAuraStudioMode", 2),
        ("EagleStoredThemeValues.flags(activeFlagsRaw)", "readActiveFlags()", 1),
        ("flag(for: target)", "flag(target)", 1),
        ("target == .island ? activeIslandModeRaw : activeDockModeRaw", "readActiveMode(target)", 1),
        ("mode(for: target)", "mode(target)", 2),
    ]:
        assert source.count(before) == count, (before, source.count(before))
        source = source.replace(before, after)
    return PREFIX + source + "\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE, MARKER
    restored = replace_once(inline_policy(view), BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Unrelated screen or binding change"
    assert compact(core) == compact(expected_core()), "Profile decisions changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    cases = [
        (0, "readActiveFlags: { EagleStoredThemeValues.flags(activeFlagsRaw) }", "readActiveFlags: { 0 }"),
        (0, "readActiveMode: { $0 == .island ? activeIslandModeRaw : activeDockModeRaw }", "readActiveMode: { _ in activeIslandModeRaw }"),
        (0, "mode: { mode(for: $0) }", "mode: { _ in .glow }"),
        (0, "Int((islandRed * 255).rounded())", "Int((islandRed * 255).rounded(.down))"),
        (0, "readActiveRGB: { $0 == .island", "readActiveRGB: { $0 == .dock"),
        (0, '"eagle.auraStudio.independentProfilesMigrated"', '"changed.migration"'),
        (1, "readActiveFlags() & flag(target) != 0", "readActiveFlags() != 0"),
        (1, "guard isTargetActive(target),", "guard true,"),
        (1, "activeMode(for: target) == mode(target)", "activeMode(for: target) != mode(target)"),
        (1, "if mode(target).usesFixedPalette { return true }", "if false { return true }"),
        (1, "let draftRGB = readDraftRGB(target)\n        let activeRGB = readActiveRGB(target)", "let activeRGB = readActiveRGB(target)\n        let draftRGB = readDraftRGB(target)"),
        (1, "return draftRGB == activeRGB", "return draftRGB.0 == activeRGB.0"),
    ]
    for index, before, after in cases:
        texts = [view, core]
        if index == 0 and before in CONTROLLER:
            # Other presenters can read the same state; mutate this binding only.
            texts[0] = replace_once(view, CONTROLLER, replace_once(CONTROLLER, before, after))
        else:
            texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    print(f"PASS: public decisions, exact RGB bindings and whole-screen reversal; {len(cases)} rejected mutations", flush=True)
    hosts = []
    for name, members in (("PublicHost", originals()), ("OwnedHost", BRIDGES + [CONTROLLER])):
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n"
                     "func act(_ op: Int, _ t: AuraStudioTarget) -> Int {\n"
                     "switch op { case 0: return isTargetActive(t) ? 1 : 0\n"
                     "case 1: return activeMode(for: t)?.rawValue ?? -1\n"
                     "default: return draftMatchesActive(t) ? 1 : 0 }\n}\n"
                     + "\n".join(members) + "\n}\n")
    # Generate recording getters, not alternate decision implementations.
    properties = []
    for name in ["activeFlagsRaw", "activeIslandModeRaw", "activeDockModeRaw"]:
        properties.append(f'var {name}: Int {{ context.readInt("{name}") }}')
    for prefix in ["island", "dock", "activeIsland", "activeDock"]:
        for color in ["Red", "Green", "Blue"]:
            name = prefix + color
            kind = "Int" if prefix.startswith("active") else "Double"
            properties.append(f'var {name}: {kind} {{ context.read{kind}("{name}") }}')
    fixture = (repo / "scripts/verify_eagle_aura_profile_state.swift").read_text()
    fixture += "\nextension Host {\n" + "\n".join(properties) + "\n}\n" + "\n".join(hosts)
    with tempfile.TemporaryDirectory(prefix="eagle-aura-profile-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / "lara/classes/EagleStoredThemeValues.swift"), str(source), "-o", str(binary)],
                           check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
