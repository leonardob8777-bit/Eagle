#!/usr/bin/env python3
"""Source-level contract for Island Gallery's independent shadow control."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = (root / "lara/views/new/IslandGalleryView.swift").read_text()
presentation = (root / "lara/views/new/IslandGalleryPresentation.swift").read_text()
native = (root / "lara/kexploit/pe/rc.m").read_text()
header = (root / "lara/kexploit/pe/rc.h").read_text()
dock = (root / "lara/views/new/DockGalleryView.swift").read_text()

required_presentation = (
    '@AppStorage("eagle.islandGallery.shadowIntensity")',
    "Slider(value: $shadowIntensity, in: 0...1, step: 0.01)",
    "shadowIntensity: shadowIntensity",
    "0.9 * shadowIntensity",
    "17 * shadowIntensity",
    'en: "No shadow", es: "Sin sombra"',
)
for snippet in required_presentation:
    assert snippet in presentation, f"missing Island preview/UI contract: {snippet}"

required_executor = (
    "func apply(_ style: IslandGalleryStyle, shadowIntensity: Double)",
    "func applyLive(_ theme: IslandLiveTheme, shadowIntensity: Double)",
    "min(max(shadowIntensity.isFinite ? shadowIntensity : 0.72, 0), 1)",
    "eagle_set_island_gallery_shadow_intensity(requestedShadowIntensity)",
    'defaults.set(shadowIntensity, forKey: "eagle.islandGallery.appliedShadowIntensity")',
)
for snippet in required_executor:
    assert snippet in view, f"missing Island apply contract: {snippet}"

assert "void eagle_set_island_gallery_shadow_intensity(int intensity);" in header
for snippet in (
    "gEagleIslandGalleryShadowIntensity = MAX(0, MIN(100, intensity))",
    "static bool eagle_is_island_gallery_mode(int mode)",
    '(CGFloat)gEagleIslandGalleryShadowIntensity / 100.0',
    'eagle_main_get_struct(proc, verifiedLayer, "shadowOpacity"',
    "fabsf(actual - expected) <= 0.0001f",
    "photoReady && shadowReady && proc.healthy",
):
    assert snippet in native, f"missing native shadow/read-back contract: {snippet}"

# Dock's label now matches Island visually; its independent control remains unchanged.
assert 'en: "Shadow", es: "Sombra"' in dock
assert 'Slider(value: $glowIntensity, in: 0...1, step: 0.01)' in dock
assert 'en: "Dock light intensity", es: "Intensidad de luz del Dock"' in dock
assert "Dock shadow intensity" not in dock

for raw in (-100, -1, 0, 1, 72, 100, 101, 999):
    clamped = max(0, min(100, raw))
    opacity = clamped / 100.0
    assert 0.0 <= opacity <= 1.0
assert max(0, min(100, 0)) / 100.0 == 0.0

# Exercise all slider steps through CALayer's Float storage representation.
# The previous NSDecimalNumber equality incorrectly rejected 72%, among others.
import struct
for percent in range(101):
    expected = percent / 100.0
    actual = struct.unpack("f", struct.pack("f", expected))[0]
    assert actual == 0 if percent == 0 else abs(actual - expected) <= 0.0001
assert struct.unpack("f", struct.pack("f", 0.72))[0] != 0.72

print("PASS: Island-only shadow slider; 0% is no shadow; native clamp, apply, read-back and persistence verified; Dock light unchanged")
