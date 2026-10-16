#!/usr/bin/env python3
"""Compare display/frame math and platform read order to the unchanged public implementation."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioDisplayGeometry.swift"
ADAPTER = "lara/EagleAdapters/AuraStudio/EagleAuraStudioDisplayMetrics.swift"
MARKER = "struct AuraStudioDisplayGeometry"
BRIDGE = """typealias AuraStudioDisplayGeometry = EagleAuraStudioDisplayGeometry

@MainActor
extension EagleAuraStudioDisplayGeometry {
    var compactIslandFrame: CGRect {
        compactIslandFrame(readModel: { devicemachine() })
    }

    var dockAuraFrame: CGRect {
        dockAuraFrame(readModel: { devicemachine() })
    }

    static var current: AuraStudioDisplayGeometry {
        EagleAuraStudioDisplayMetrics.current
    }
}"""
SIGNATURE = """static func resolve(
        readBounds: () -> CGRect,
        readNativeBounds: () -> CGRect,
        readScale: () -> CGFloat,
        readNativeScale: () -> CGFloat
    ) -> EagleAuraStudioDisplayGeometry {"""
ADAPTER_SOURCE = """import UIKit

/// Reads the same screen measurements as the existing app; all numerical decisions live in Core.
@MainActor
enum EagleAuraStudioDisplayMetrics {
    static var current: EagleAuraStudioDisplayGeometry {
        let screen = UIScreen.main
        return EagleAuraStudioDisplayGeometry.resolve(
            readBounds: { screen.bounds },
            readNativeBounds: { screen.nativeBounds },
            readScale: { screen.scale },
            readNativeScale: { screen.nativeScale }
        )
    }
}
"""


def original():
    return declaration(public_file(), MARKER)


def inline_display_geometry(view):
    from verify_eagle_aura_request_admission import inline_request_admission
    view = inline_request_admission(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    source = original()
    source = replace_once(source, MARKER, "nonisolated struct EagleAuraStudioDisplayGeometry: Sendable")
    source = replace_once(source, "var compactIslandFrame: CGRect {", "func compactIslandFrame(readModel: () -> String) -> CGRect {")
    source = replace_once(source, "var dockAuraFrame: CGRect {", "func dockAuraFrame(readModel: () -> String) -> CGRect {")
    source = replace_once(source, "static var current: AuraStudioDisplayGeometry {\n        let screen = UIScreen.main", SIGNATURE.rstrip() + "\n")
    # Remove only the extra line introduced by removing the platform acquisition.
    source = replace_once(source, SIGNATURE + "\n\n", SIGNATURE + "\n")
    for before, after, count in [
        ("devicemachine()", "readModel()", 3),
        ("screen.bounds", "readBounds()", 4),
        ("screen.nativeBounds", "readNativeBounds()", 4),
        ("screen.scale", "readScale()", 1),
        ("screen.nativeScale", "readNativeScale()", 1),
        ("return AuraStudioDisplayGeometry(", "return EagleAuraStudioDisplayGeometry(", 1),
    ]:
        assert source.count(before) == count, (before, source.count(before))
        source = source.replace(before, after)
    return "import Foundation\nimport CoreGraphics\n\n/// Display and frame calculations. Platform measurements and model reads are supplied by the caller.\n" + source + "\n"


def verify_texts(view, core, adapter):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER as MODE_MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MODE_MARKER))
    assert restored == public_file(), "Geometry connections, native calls or other Aura behavior changed"
    assert core == expected_core(), "Display Zoom thresholds, models, frames or evaluation order changed"
    assert adapter == ADAPTER_SOURCE, "UIScreen source or measurement callbacks changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    sources = [(repo / p).read_text() for p in (VIEW, CORE, ADAPTER)]
    verify_texts(*sources)
    mutations = [
        (0, "compactIslandFrame(readModel: { devicemachine() })", "compactIslandFrame(readModel: { \"iPhone15,2\" })"),
        (0, "dockAuraFrame(readModel: { devicemachine() })", "dockAuraFrame(readModel: { \"\" })"),
        (1, "width: 134,", "width: 135,"),
        (1, "height: 39", "height: 40"),
        (1, "? 18 : 15", "? 15 : 18"),
        (1, "? 90 : 94", "? 94 : 90"),
        (1, "0.985", "0.984"),
        (1, "0.75...1.015", "0.75...1.05"),
        (1, "readModel() == \"iPhone15,3\"", "readModel() == \"iPhone15,2\""),
        (2, "readBounds: { screen.bounds }", "readBounds: { screen.nativeBounds }"),
        (2, "readScale: { screen.scale }", "readScale: { screen.nativeScale }"),
    ]
    for index, before, after in mutations:
        values = sources.copy()
        values[index] = values[index].replace(before, after)
        assert values[index] != sources[index]
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_display_geometry.swift").read_text()
    reference = original().replace("AuraStudioDisplayGeometry", "PublicGeometry")
    fixture += "\n@MainActor\n" + reference
    fixture += "\n" + ADAPTER_SOURCE.replace("import UIKit\n", "") + "\n" + BRIDGE
    with tempfile.TemporaryDirectory(prefix="eagle-aura-display-geometry-") as temporary:
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
    print("PASS: exact public geometry, full-screen reversal and eleven rejected mutations", flush=True)


if __name__ == "__main__":
    main()
