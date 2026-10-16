#!/usr/bin/env python3
"""Connect all eight Aura editor/state extractions against the public screen.

Real extracted code and exact bindings; no SwiftUI, system queries or executor.
"""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration
import verify_eagle_aura_mode_policy as policy
import verify_eagle_aura_draft_modes as drafts
import verify_eagle_aura_colors as colors
import verify_eagle_aura_profile_state as profiles
import verify_eagle_aura_profile_status as status
import verify_eagle_aura_reconciliation as reconciliation
import verify_eagle_aura_entry_flow as entry


def main():
    repo = Path(__file__).resolve().parents[1]
    view = (repo / entry.VIEW).read_text()
    modules = [policy, drafts, colors, profiles, status, reconciliation, entry]
    for module in modules:
        module.verify_texts(view, (repo / module.CORE).read_text())
    public = entry.public_file()
    shared = [declaration(public, marker) for marker in [
        "private var selectedTarget:", "private func flag(for target:",
        "private var islandProfileAvailable:", "private var deviceSupportedFlags:",
    ]]
    public_members = policy.originals() + drafts.originals() + colors.originals() + profiles.originals()
    public_members += [status.original(), reconciliation.original()]
    owned_members = policy.BRIDGES + drafts.BRIDGES + [drafts.CONTROLLER] + colors.BRIDGES
    owned_members += profiles.BRIDGES + [profiles.CONTROLLER, status.BRIDGE, reconciliation.BRIDGE, entry.CONTROLLER]
    hosts = []
    actions = '''
    func act(_ op: Int) -> String {
        switch op {
        case 0: appear(); return "entry"
        case 1: return String(selectedMode.rawValue) + ":" + availableModes.map { String($0.rawValue) }.joined(separator: ",")
        case 2: selectedMode = .rainbow; return String(selectedMode.rawValue)
        case 3: setSelectedRGB(red: 0.2, green: 0.7, blue: 0.9); return "rgb"
        case 4: return profileStatusText(for: .island) + "|" + profileStatusText(for: .dock)
        case 5: selectedTarget = .dock; selectedMode = .pulse; return String(selectedMode.rawValue)
        case 6: setSelectedRGB(red: 0.9, green: 0.3, blue: 0.1); return "dock-rgb"
        case 7: channel(); return "channel"
        case 8: reconcilePersistedActiveState(currentPID: 101); return "session"
        case 9: return presets.map { $0.name + ":" + String(presetIsSelected($0)) }.joined(separator: "|")
        default: selectedTarget = .island; selectedMode = .glow; return String(selectedMode.rawValue)
        }
    }
'''
    for name, members, observers in [("PublicHost", public_members, entry.originals()),
                                      ("OwnedHost", owned_members, entry.BRIDGES)]:
        appear = observers[0][observers[0].index("{") + 1:observers[0].rindex("}")]
        change = observers[1][observers[1].index("_ in") + 4:observers[1].rindex("}")]
        hosts.append("@MainActor struct " + name + ": Host {\nlet context: Context\n" + actions
                     + "func appear() {" + appear + "}\nfunc channel() {" + change + "}\n"
                     + "\n".join(shared + members) + "\n}\n")
    properties = []
    fields = {
        "Int": ["legacySelectedModeRaw", "islandModeRaw", "dockModeRaw", "selectedTargetRaw",
                "activeFlagsRaw", "activeModeRaw", "activeIslandModeRaw", "activeDockModeRaw",
                "activeDockGalleryStyleRaw", "activeSpringBoardPID", "activeIslandRed", "activeIslandGreen",
                "activeIslandBlue", "activeDockRed", "activeDockGreen", "activeDockBlue"],
        "Double": ["islandRed", "islandGreen", "islandBlue", "dockRed", "dockGreen", "dockBlue"],
        "Bool": ["independentProfilesMigrated", "applySafetyBlocked", "isApplying"],
    }
    for kind, names in fields.items():
        for name in names:
            properties.append(f'var {name}: {kind} {{ get {{ context.read{kind}("{name}") }} nonmutating set {{ context.write{kind}("{name}", newValue) }} }}')
    fixture = (repo / "scripts/verify_eagle_aura_integration.swift").read_text()
    fixture += "\nextension Host {\n" + "\n".join(properties) + "\n}\n" + "\n".join(hosts)
    with tempfile.TemporaryDirectory(prefix="eagle-aura-integrated-") as temporary:
        source = Path(temporary) / "Fixture.swift"; source.write_text(fixture)
        for flags in (["-Onone", "-D", "DEBUG"], ["-O"]):
            binary = Path(temporary) / ("debug" if "-D" in flags else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", *flags,
                            *[str(repo / module.CORE) for module in modules],
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioMode.swift"),
                            str(repo / "lara/classes/EagleStoredThemeValues.swift"), str(source), "-o", str(binary)],
                           check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: all eight owned Aura components connected through exact production bindings; public screen reverses unchanged")


if __name__ == "__main__":
    main()
