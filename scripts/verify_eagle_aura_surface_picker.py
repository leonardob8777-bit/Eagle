#!/usr/bin/env python3
"""Compare the complete public Aura surface picker and callback wiring."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

SOURCE = "lara/EagleAdapters/AuraStudio/EagleAuraStudioSurfacePicker.swift"
MARKERS = ["private var surfaceProfilesCard: some View", "private func profileButton(for target:", "private var homeIconCompactLink: some View"]
BRIDGE = """private var surfaceProfilesCard: some View {
        EagleAuraStudioSurfacePicker(
            readEditingIcons: { editingIcons },
            writeEditingIcons: { editingIcons = $0 },
            readTarget: { selectedTarget },
            writeTarget: { selectedTarget = $0 },
            islandAvailable: { islandProfileAvailable },
            operationInProgress: { isApplying },
            modeTitle: { mode(for: $0).title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).surfaceProfilesCard
    }"""
PREFIX = """import SwiftUI

/// Existing Island/Dock/Icons navigation UI; state, storage and hardware checks stay with the screen.
@MainActor
struct EagleAuraStudioSurfacePicker {
    let readEditingIcons: () -> Bool
    let writeEditingIcons: (Bool) -> Void
    let readTarget: () -> EagleAuraStudioTarget
    let writeTarget: (EagleAuraStudioTarget) -> Void
    let islandAvailable: () -> Bool
    let operationInProgress: () -> Bool
    let modeTitle: (EagleAuraStudioTarget) -> String
    let localizedText: (String, String) -> String

    """


def originals():
    return [declaration(public_file(), marker) for marker in MARKERS]


def inline_surface_picker(view):
    from verify_eagle_aura_access_note import inline_access_note
    view = inline_access_note(view)
    return replace_once(view, BRIDGE, "\n\n    ".join(originals()))


def expected_source():
    body = "\n\n    ".join(originals())
    for before, after, count in [
        ("private var ", "var ", 2), ("private func ", "func ", 1),
        ("AuraStudioTarget", "EagleAuraStudioTarget", 2),
        ("editingIcons = false", "writeEditingIcons(false)", 1),
        ("editingIcons = true", "writeEditingIcons(true)", 1),
        ("selectedTarget = target", "writeTarget(target)", 1),
        ("editingIcons", "readEditingIcons()", 3),
        ("selectedTarget", "readTarget()", 1),
        ("islandProfileAvailable", "islandAvailable()", 1),
        ("isApplying", "operationInProgress()", 2),
        ("mode(for: target).title", "modeTitle(target)", 1),
        ("LaraL10n.text(", "localizedText(", 3),
        ("en: ", "", 3), ("es: ", "", 3),
    ]:
        assert body.count(before) == count, (before, body.count(before))
        body = body.replace(before, after)
    return PREFIX + body + "\n}\n"


def project_visual_picker(source):
    # Only the reviewed tile renderer and two label expressions changed. Keep
    # actions, callback order, availability and accessibility byte-for-byte.
    tile = declaration(source, "private func tile(")
    assert hashlib.sha256(tile.encode()).hexdigest() == "d8f5f445a8c2a97f0584a3be9c8c81e1c7902bf55f45f0e420cac0f710e38837"
    comment = '''    /// One option. Solid colours, so it reads the same on the light top of the backdrop as on the dark:
    /// the chosen one in the action colours (white with black text in dark appearance, black with white
    /// text in light), the others on their own opaque surface with a hairline.
    '''
    source = replace_once(source, '\n\n' + comment + tile, '')
    expected = expected_source()
    labels = [
        ('func profileButton(for target:', '''} label: {
            tile(
                icon: target == .island ? "capsule.fill" : "dock.rectangle",
                title: target == .island ? "Island" : target.title,
                selected: isSelected
            )
        }'''),
        ('var homeIconCompactLink:', '''} label: {
            tile(icon: "app.fill", title: localizedText("Icons", "Iconos"), selected: readEditingIcons())
        }'''),
    ]
    for marker, current_label in labels:
        old_member = declaration(expected, marker)
        old_label = declaration(old_member, '} label:')
        source = replace_once(source, current_label, old_label)
    assert source.count('.buttonStyle(EaglePressableStyle(kind: .card))') == 2
    return source.replace('.buttonStyle(EaglePressableStyle(kind: .card))', '.buttonStyle(.plain)')


def verify_texts(view, source):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Unrelated screen/native behavior changed"
    assert project_visual_picker(source) == expected_source(), "Picker construction, ordering or availability changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, source = [(repo / p).read_text() for p in (VIEW, SOURCE)]
    verify_texts(view, source)
    mutations = [
        (0, "readEditingIcons: { editingIcons }", "readEditingIcons: { false }"),
        (0, "writeEditingIcons: { editingIcons = $0 }", "writeEditingIcons: { _ in }"),
        (0, "writeTarget: { selectedTarget = $0 }", "writeTarget: { _ in selectedTarget = .dock }"),
        (0, "islandAvailable: { islandProfileAvailable }", "islandAvailable: { true }"),
        (0, "operationInProgress: { isApplying }", "operationInProgress: { false }"),
        (0, "modeTitle: { mode(for: $0).title }", "modeTitle: { _ in mode(for: .dock).title }"),
        (1, "writeEditingIcons(false)\n            writeTarget(target)", "writeTarget(target)\n            writeEditingIcons(false)"),
        (1, "target != .island || islandAvailable()", "target == .island || islandAvailable()"),
        (1, "!readEditingIcons() && readTarget() == target", "readTarget() == target && !readEditingIcons()"),
        (1, "writeEditingIcons(true)", "writeEditingIcons(false)"),
        (1, "? 1 : 0.64", "? 1 : 0.5"),
        (1, ".frame(height: 52)", ".frame(height: 48)"),
        (1, "HStack(spacing: 8)", "HStack(spacing: 10)"),
        (1, '"capsule.fill"', '"app.fill"'),
        (1, "operationInProgress() || !isHardwareAvailable", "operationInProgress()"),
        (1, '"Icons", "Iconos"', '"Iconos", "Icons"'),
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
    print(f"PASS: three complete public picker members, full-screen reversal; {len(mutations)} rejected mutations", flush=True)
    fixture = (repo / "scripts/verify_eagle_aura_surface_picker.swift").read_text()
    for name, body in [("PublicHost", "\n".join(originals())), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host {\nlet context: Context\n" + body.replace("private var", "var").replace("private func", "func") + "\n}\n"
    fixture += "\n" + replace_once(project_visual_picker(source), "import SwiftUI\n", "")
    with tempfile.TemporaryDirectory(prefix="eagle-aura-surface-picker-") as temporary:
        swift = Path(temporary) / "Fixture.swift"
        swift.write_text(fixture)
        for optimization in ("-Onone", "-O"):
            binary = Path(temporary) / optimization
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", optimization,
                            str(repo / "lara/EagleCore/AuraStudio/EagleAuraStudioTarget.swift"),
                            str(swift), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == "__main__":
    main()
