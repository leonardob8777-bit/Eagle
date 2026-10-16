#!/usr/bin/env python3
"""Compare captured Aura RGB/position values and ordered reads with the public screen."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once
from verify_eagle_aura_result_feedback import public_file, VIEW

CORE = "lara/EagleCore/AuraStudio/EagleAuraStudioRequestPreparation.swift"
BRIDGE = """        let parameters = EagleAuraStudioRequestPreparation.prepare(
            target: operationTarget,
            isRemoving: operation.isRemoving,
            readIslandRed: { islandRed },
            readIslandGreen: { islandGreen },
            readIslandBlue: { islandBlue },
            readDockRed: { dockRed },
            readDockGreen: { dockGreen },
            readDockBlue: { dockBlue },
            sanitize: { sanitizedChannel($0) },
            makeZeroPosition: { GalleryPosition(x: 0, y: 0) },
            savedPosition: { GalleryPosition.saved($0) },
            channel255: { channel255($0) }
        )
        let requestedPosition = parameters.position
        let positionSurface = parameters.positionSurface
        let redValue = parameters.red
        let greenValue = parameters.green
        let blueValue = parameters.blue"""
PREFIX = """import Foundation

/// Immutable values captured before an Aura operation. This contains no access/session objects.
nonisolated struct EagleAuraStudioRequestParameters<Position: Sendable>: Sendable {
    let position: Position
    let positionSurface: Int32
    let red: Int32
    let green: Int32
    let blue: Int32
}

@MainActor
enum EagleAuraStudioRequestPreparation {
    static func prepare<Position: Sendable>(
        target: EagleAuraStudioTarget,
        isRemoving: Bool,
        readIslandRed: () -> Double,
        readIslandGreen: () -> Double,
        readIslandBlue: () -> Double,
        readDockRed: () -> Double,
        readDockGreen: () -> Double,
        readDockBlue: () -> Double,
        sanitize: (Double) -> Double,
        makeZeroPosition: () -> Position,
        savedPosition: (String) -> Position,
        channel255: (Double) -> Int
    ) -> EagleAuraStudioRequestParameters<Position> {
"""
RETURN = """        return EagleAuraStudioRequestParameters(
            position: requestedPosition,
            positionSurface: positionSurface,
            red: redValue,
            green: greenValue,
            blue: blueValue
        )"""


def original():
    source = public_file()
    start = source.index("        let selectedRGB: (red: Double, green: Double, blue: Double) =")
    end = source.index("\n        AuraStudioDiagnostics.log(", start)
    return source[start:end]


def inline_request_preparation(view):
    from verify_eagle_aura_session_admission import inline_session_admission
    view = inline_session_admission(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    source = original()
    for before, after, count in [
        ("operationTarget", "target", 3),
        ("operation.isRemoving", "isRemoving", 1),
        ("GalleryPosition(x: 0, y: 0)", "makeZeroPosition()", 1),
        ("GalleryPosition.saved(", "savedPosition(", 1),
        *[(f"sanitizedChannel({surface}{channel})", f"sanitize(read{surface.title()}{channel}())", 1)
          for surface in ("island", "dock") for channel in ("Red", "Green", "Blue")],
    ]:
        assert source.count(before) == count, (before, source.count(before), count)
        source = source.replace(before, after)
    return PREFIX + source + "\n" + RETURN + "\n    }\n}\n"


def verify_texts(view, core):
    from verify_eagle_aura_mode_policy import inline_policy
    from verify_eagle_aura_mode import BRIDGE as MODE_BRIDGE, MARKER
    restored = replace_once(inline_policy(view), MODE_BRIDGE, declaration(public_file(), MARKER))
    assert restored == public_file(), "Request/native continuation, stores or other Aura code changed"
    assert core == expected_core(), "Request color, saved position or read/conversion order changed"


def main():
    repo = Path(__file__).resolve().parents[1]
    view, core = [(repo / path).read_text() for path in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "target: operationTarget", "target: .island"),
        (0, "readDockRed: { dockRed }", "readDockRed: { islandRed }"),
        (0, "makeZeroPosition: { GalleryPosition(x: 0, y: 0) }", "makeZeroPosition: { GalleryPosition.saved(\"island\") }"),
        (0, "let redValue = parameters.red", "let redValue = parameters.blue"),
        (1, "sanitize(readIslandRed())", "sanitize(readDockRed())"),
        (1, 'savedPosition(target == .island ? "island" : "dock")', 'savedPosition("island")'),
        (1, "let requestedPosition = isRemoving", "let requestedPosition = !isRemoving"),
        (1, "target == .island ? 1 : 0", "target == .island ? 0 : 1"),
        (1, "Int32(channel255(selectedRGB.blue))", "Int32(channel255(selectedRGB.red))"),
    ]
    for index, before, after in mutations:
        values = [view, core]
        if index == 0:
            values[0] = replace_once(view, BRIDGE, replace_once(BRIDGE, before, after))
        else:
            values[1] = replace_once(core, before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError("Accepted mutation: " + before)
    fixture = (repo / "scripts/verify_eagle_aura_request_preparation.swift").read_text()
    for name, body in [("PublicHost", original()), ("OwnedHost", BRIDGE)]:
        fixture += "\n@MainActor struct " + name + ": Host { let context: Context\n"
        fixture += "func prepare(_ operationTarget: AuraStudioTarget, _ operation: AuraStudioOperation) -> EagleAuraStudioRequestParameters<GalleryPosition> {\n" + body + "\n" + RETURN + "\n}\n}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-aura-preparation-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture)
        for profile, flags in [("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])]:
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / CORE),
                *[str(repo / "lara/EagleCore/AuraStudio" / filename) for filename in (
                    "EagleAuraStudioMode.swift", "EagleAuraStudioTarget.swift", "EagleAuraStudioOperationPlan.swift", "EagleAuraStudioColors.swift")],
                str(repo / "lara/EagleCore/Gallery/EagleGalleryPosition.swift"),
                str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: public RGB/position preparation and unchanged native continuation; nine rejected mutations", flush=True)


if __name__ == "__main__":
    main()
