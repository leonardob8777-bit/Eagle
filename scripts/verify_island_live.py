#!/usr/bin/env python3
"""Validate Island-only routing, media integrity and unchanged Vortex geometry."""
import argparse
import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("assets", type=Path)
parser.add_argument("--baseline", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
native = (repo / "lara/kexploit/pe/rc.m").read_text()
media = (repo / "lara/views/new/IslandLiveMedia.swift").read_text()
catalog_model = (repo / "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift").read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


manifest = json.loads((args.assets / "island-live-v1.json").read_text())
with Image.open(repo / "lara/other/media.xcassets/PhotoAuraVortex.imageset/PhotoAuraVortex.png") as vortex:
    alpha = vortex.getchannel("A").tobytes()
hashes = []
for i in range(1, 18):
    path = args.assets / "frames" / f"frame{i:02d}.png"
    data = path.read_bytes()
    hashes.append(hashlib.sha256(data).hexdigest())
    assert 0 < len(data) <= 448 * 1024
    with Image.open(path) as image:
        assert image.size == (1200, 500) and image.mode == "RGBA"
        assert image.getchannel("A").tobytes() == alpha
assert hashes == manifest["frameSHA256"] and len(set(hashes)) > 1
package = args.assets / "singularity-live-v1.zip"
assert hashlib.sha256(package.read_bytes()).hexdigest() == manifest["sha256"]
assert package.stat().st_size == manifest["byteCount"]
with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None and len(archive.namelist()) == 17
    assert [hashlib.sha256(archive.read(f"frame{i:02d}.png")).hexdigest() for i in range(1, 18)] == hashes
with Image.open(args.assets / "previews/singularity-live.gif") as gif:
    assert gif.size == (600, 250) and gif.n_frames == 17
    duration = 0
    for i in range(17):
        gif.seek(i)
        duration += gif.info["duration"]
    assert abs(duration - 17 / 6 * 1000) < 25

if args.baseline:
    old = (args.baseline / "rc.m").read_text()
    for marker in ["static bool eagle_install_dock_gallery_texture(",
                   "static uint64_t eagle_remove_island_fallback(",
                   "static bool eagle_rollback_island_fallback_candidate("]:
        assert block(old, marker) == block(native, marker), marker
    geometry = "    if (eagle_island_uses_photo_texture(mode)) {\n        // The 1200x500"
    assert block(old, geometry) == block(native, geometry)
    assert (args.baseline / "DockGalleryView.swift").read_bytes() == (repo / "lara/views/new/DockGalleryView.swift").read_bytes()

enum_start = native.rfind("enum {", 0, native.index("EagleIslandAuraGlacier = 5"))
enums = block(native[enum_start:], "enum {") + ";"
functions = "\n".join(block(native, name) for name in [
    "static bool eagle_island_uses_photo_texture(",
    "static bool eagle_island_uses_compact_custom_style(",
    "static bool eagle_is_dock_gallery_mode(",
])
c_test = "#include <stdbool.h>\n#include <assert.h>\n" + enums + functions + r'''
int main(void) {
    assert(eagle_island_uses_photo_texture(12));
    assert(eagle_island_uses_photo_texture(36));
    assert(eagle_island_uses_compact_custom_style(12));
    assert(eagle_island_uses_compact_custom_style(36));
    assert(!eagle_is_dock_gallery_mode(36));
    assert(eagle_is_dock_gallery_mode(35));
    assert(!eagle_island_uses_photo_texture(35));
    assert(!eagle_island_uses_photo_texture(0));
    assert(!eagle_island_uses_photo_texture(37));
    return 0;
}
'''
swift_test = "import Foundation\n" + block(catalog_model, "nonisolated struct EagleIslandGalleryManifest:") + "\ntypealias IslandLiveManifest = EagleIslandGalleryManifest\n" + r'''
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
private let valid = try JSONDecoder().decode(IslandLiveManifest.self, from: data)
assert(valid.isSupported)
let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for (key, badValue) in [("width", 1146), ("height", 318), ("frameCount", 0),
                       ("fps", 60), ("byteCount", 40000000), ("version", 2)] {
    var bad = object
    bad[key] = badValue
    let changed = try JSONSerialization.data(withJSONObject: bad)
    let decoded = try JSONDecoder().decode(IslandLiveManifest.self, from: changed)
    assert(!decoded.isSupported)
}
for key in ["packageURL", "sha256", "id"] {
    var bad = object
    bad[key] = "https://invalid.example/untrusted"
    let changed = try JSONSerialization.data(withJSONObject: bad)
    let decoded = try JSONDecoder().decode(IslandLiveManifest.self, from: changed)
    assert(!decoded.isSupported)
}
'''
with tempfile.TemporaryDirectory(prefix="eagle-island-tests-") as temporary:
    directory = Path(temporary)
    (directory / "routing.c").write_text(c_test)
    (directory / "manifest.swift").write_text(swift_test)
    subprocess.run(["cc", str(directory / "routing.c"), "-o", str(directory / "routing")], check=True)
    subprocess.run([str(directory / "routing")], check=True)
    subprocess.run(["swift", str(directory / "manifest.swift"), str(args.assets / "island-live-v1.json")], check=True)
print("PASS: 17 moving frames, 6 FPS preview, pixel-identical Vortex alpha, size/hash validation, invalid manifests rejected, isolated routing; Dock and Island geometry/rollback/removal unchanged")
