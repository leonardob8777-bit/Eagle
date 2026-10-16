#!/usr/bin/env python3
"""Verify shared position extraction, unchanged controls and isolated preference reads."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once, PUBLIC_COMMIT

VIEW = "lara/views/new/GalleryPositionControl.swift"
CORE = "lara/EagleCore/Gallery/EagleGalleryPosition.swift"
ADAPTER = "lara/EagleAdapters/Gallery/EagleGalleryPositionStorage.swift"
MARKER = "nonisolated struct GalleryPosition: Equatable, Sendable"
BRIDGE = "typealias GalleryPosition = EagleGalleryPosition"
PREFIX = "import Foundation\n\n/// Shared quarter-point position value. Persistence and controls live outside Core.\n"


def public_file():
    return subprocess.check_output(["git", "show", f"{PUBLIC_COMMIT}:{VIEW}"],
                                   cwd=Path(__file__).resolve().parents[1], text=True)


def original():
    return declaration(public_file(), MARKER)


def expected_sources():
    value = original()
    saved = declaration(value, "static func saved(")
    core = replace_once(value, "\n\n    " + saved, "")
    core = replace_once(core, "struct GalleryPosition:", "struct EagleGalleryPosition:")
    adapter = "import Foundation\n\nextension EagleGalleryPosition {\n    nonisolated " + saved + "\n}\n"
    return PREFIX + core + "\n", adapter


def verify_texts(view, core, adapter):
    # Exact visual-only changes; coordinate writes, bounds and enablement stay frozen.
    assert view.count('.buttonStyle(EaglePressableStyle())') == 2
    view = view.replace('.buttonStyle(EaglePressableStyle())', '.buttonStyle(.plain)')
    for before, after in [
        ('''        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
        // Opaque, so the filters read the same over the light top of the backdrop as over the dark.
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        // The highlight moves to the chosen filter with a quick crossfade instead of jumping.
        .animation(.easeInOut(duration: 0.22), value: selectedID)''', '''        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 17))'''),
        ('    @State private var resetTurns = 0.0\n', ''),
        ('                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { resetTurns += 1 }\n', ''),
        ('                    // Winds back a full turn as the position resets.\n', ''),
        ('                        .rotationEffect(.degrees(-360 * resetTurns))\n', ''),
        ('''            // The coordinates roll to each new value.
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.2), value: x)
            .animation(.easeOut(duration: 0.2), value: y)
''', ''),
        ('''        // Opaque like the other cards, so it does not take the backdrop's fade through it.
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }''', '''        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 18)
        )'''),
    ]:
        view = replace_once(view, before, after)
    assert replace_once(view, BRIDGE, original()) == public_file(), "Gallery position controls or filter UI changed"
    assert (core, adapter) == expected_sources(), "Position rounding, bounds, defaults or keys changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    values = [(repo / path).read_text() for path in (VIEW, CORE, ADAPTER)]
    verify_texts(*values)
    mutations = [
        (0, BRIDGE, "typealias GalleryPosition = OtherPosition"),
        (1, "value.isFinite", "!value.isFinite"),
        (1, "min(12, max(-12, value))", "min(16, max(-16, value))"),
        (1, ".rounded() / 4", ".rounded(.towardZero) / 4"),
        (1, "self.y = Self.component(y)", "self.y = Self.component(x)"),
        (2, 'Gallery.positionX"', 'Gallery.positionY"'),
        (2, 'eagle.\\(surface)Gallery', 'eagle.\\(surface)Aura'),
    ]
    for index, before, after in mutations:
        changed = values.copy()
        changed[index] = changed[index].replace(before, after)
        assert changed[index] != values[index]
        try:
            verify_texts(*changed)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_gallery_position.swift").read_text()
    reference = original().replace("struct GalleryPosition:", "struct PublicPosition:")
    reference = reference.replace("UserDefaults.standard", "Fixture.defaults")
    adapter = values[2].replace("import Foundation\n", "").replace("UserDefaults.standard", "Fixture.defaults")
    fixture += "\n" + reference + "\n" + adapter
    with tempfile.TemporaryDirectory(prefix="eagle-gallery-position-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in [("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])]:
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / CORE), str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: unchanged public position/control source, exact saved keys and seven rejected mutations", flush=True)


if __name__ == "__main__":
    main()
