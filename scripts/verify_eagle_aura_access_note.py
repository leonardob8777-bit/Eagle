#!/usr/bin/env python3
"""Verify unchanged read-only access/status card, no native calls."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

SOURCE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioAccessNote.swift"
MARKER = "private var adaptiveNote: some View"
BRIDGE = """private var adaptiveNote: some View {
        EagleAuraStudioAccessNote(
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            accessReady: { mgr.dsready },
            lightColor: { previewLightColor },
            capabilityTitle: { selectedCapabilityTitle },
            capabilityDescription: { selectedCapabilityDescription },
            engineBuild: { auraEngineBuild },
            channelTitle: { releaseChannel.title },
            displayZoomed: { displayGeometry.isDisplayZoomed }
        ).note
    }"""
PREFIX = """import SwiftUI

/// Existing read-only access note; decisions and native access remain outside this view adapter.
@MainActor
struct EagleAuraStudioAccessNote {
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let accessReady: () -> Bool
    let lightColor: () -> Color
    let capabilityTitle: () -> String
    let capabilityDescription: () -> String
    let engineBuild: () -> String
    let channelTitle: () -> String
    let displayZoomed: () -> Bool

    """


def original():
    return declaration(public_file(), MARKER)


def inline_access_note(view):
    from verify_eagle_aura_runtime_contract import inline_runtime_contract
    view = inline_runtime_contract(view)
    return replace_once(view, BRIDGE, original())


def expected_source():
    body = original()
    for before, after, count in [
        (MARKER, "var note: some View", 1),
        ("applySafetyBlocked", "localSafetyBlocked()", 2),
        ("mgr.rcSafetyLocked", "remoteSafetyLocked()", 2),
        ("mgr.dsready", "accessReady()", 1),
        ("previewLightColor", "lightColor()", 1),
        ("selectedCapabilityTitle", "capabilityTitle()", 1),
        ("selectedCapabilityDescription", "capabilityDescription()", 1),
        ("auraEngineBuild", "engineBuild()", 1),
        ("releaseChannel.title", "channelTitle()", 1),
        ("displayGeometry.isDisplayZoomed", "displayZoomed()", 1),
    ]:
        assert body.count(before) == count, before
        body = body.replace(before, after)
    return PREFIX + body + "\n}\n"


def verify_texts(view, source):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Access decisions, native geometry or other screen behavior changed"
    assert source == expected_source(), "Note construction, text or read order changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, source = [(repo / p).read_text() for p in (VIEW, SOURCE)]
    verify_texts(view, source)
    mutations = [
        (0, "localSafetyBlocked: { applySafetyBlocked }", "localSafetyBlocked: { false }"),
        (0, "remoteSafetyLocked: { mgr.rcSafetyLocked }", "remoteSafetyLocked: { false }"),
        (0, "accessReady: { mgr.dsready }", "accessReady: { true }"),
        (0, "lightColor: { previewLightColor }", "lightColor: { Color.orange }"),
        (0, "capabilityTitle: { selectedCapabilityTitle }", "capabilityTitle: { selectedCapabilityDescription }"),
        (0, "displayZoomed: { displayGeometry.isDisplayZoomed }", "displayZoomed: { false }"),
        (1, "localSafetyBlocked() || remoteSafetyLocked()", "remoteSafetyLocked() || localSafetyBlocked()"),
        (1, '"checkmark.shield.fill"', '"lock.shield.fill"'),
        (1, "? Color.orange", "? Color.red"),
        (1, '"Display Zoom" : "Standard"', '"Standard" : "Display Zoom"'),
        (1, ".padding(18)", ".padding(16)"),
        (1, "opacity(0.06)", "opacity(0.08)"),
        (1, "cornerRadius: 18", "cornerRadius: 20"),
        (1, "· ", "- "),
    ]
    for index, before, after in mutations:
        values = [view, source]
        if index == 0:
            values[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            assert before in source
            values[1] = source.replace(before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    print(f"PASS: full public access note and screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_access_note.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body.replace("private var", "var") + "\n}\n"
    fixture += "\n" + replace_once(source, "import SwiftUI\n", "")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-access-note-") as temporary:
        swift = Path(temporary) / "Fixture.swift"
        swift.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / optimization
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(swift), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
