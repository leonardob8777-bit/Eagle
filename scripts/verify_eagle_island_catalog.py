#!/usr/bin/env python3
"""Check the actual Island catalog model against public Eagle, without I/O/native execution."""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
MEDIA = "lara/views/new/IslandLiveMedia.swift"
MODEL = "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift"
ALIASES = "typealias IslandLiveManifest = EagleIslandGalleryManifest\ntypealias IslandLiveTheme = EagleIslandGalleryTheme\nprivate typealias IslandLiveCatalog = EagleIslandGalleryCatalog"
NAMES = (("IslandLiveManifest", "EagleIslandGalleryManifest"),
         ("IslandLiveTheme", "EagleIslandGalleryTheme"),
         ("IslandLiveCatalog", "EagleIslandGalleryCatalog"))


def original_models(public):
    return public[public.index("nonisolated struct IslandLiveManifest:"):public.index("/// An isolated,")].rstrip()


def expected_model(public):
    result = original_models(public)
    for old, new in NAMES:
        result = result.replace(old, new)
    return "import Foundation\n\n" + result.replace("private nonisolated struct", "nonisolated struct") + "\n"


def verify_texts(public, media, model):
    assert model == expected_model(public), "Island decoding/validation/classification/RGB changed"
    from verify_eagle_island_catalog_loader import inline_catalog_loader
    media = inline_catalog_loader(media)
    restored = replace_once(media, ALIASES, original_models(public))
    assert restored == public, "Island media changed beyond the exact model/alias extraction"


def verify_sources(repo):
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{MEDIA}"], cwd=repo, text=True)
    media, model = [(repo / path).read_text() for path in (MEDIA, MODEL)]
    verify_texts(public, media, model)
    from verify_eagle_island_filter import inline_filter
    for path, sha in (
        ("lara/views/new/IslandGalleryPresentation.swift", "7f4a22f14536451cecd56327bb204a1334279facac49cdce87154883b4c27225"),
        ("lara/views/new/IslandGalleryView.swift", "0659ee8112772cbcd0d418f7da0840b638be60e0e60b5798116050a91d1196ec"),
    ):
        data = (repo / path).read_bytes()
        if path.endswith("IslandGalleryPresentation.swift"):
            data = inline_filter(data.decode()).encode()
        assert hashlib.sha256(data).hexdigest() == sha, "Island screen or executor changed beyond counted filter move"
    cases = (
        ("model", "frameCount == 17", "frameCount > 1"),
        ("model", "fps == 6", "fps == 60"),
        ("model", "width == 1200", "width == 1146"),
        ("model", "34 * 1024 * 1024", "40 * 1024 * 1024"),
        ("model", 'id == "singularity-live"', 'id == "other"'),
        ("model", "frameSHA256.count == 17", "frameSHA256.count > 0"),
        ("model", "{ $0 != first }", "{ $0 == first }"),
        ("model", "guard let first = manifest.frameSHA256.first else { return false }", "guard let first = manifest.frameSHA256.first else { return true }"),
        ("model", "themes.count <= 500", "themes.count <= 501"),
        ("model", "Set(themes.map(\\.id)).count == themes.count", "true"),
        ("model", "?? 0xD9D9D9", "?? 0x000000"),
        ("model", "import Foundation", "import Foundation\nimport UIKit"),
        ("media", "typealias IslandLiveTheme = EagleIslandGalleryTheme", "typealias IslandLiveTheme = OtherTheme"),
        ("media", "import UIKit", "import UIKit\n// unrelated edit"),
    )
    for target, old, new in cases:
        changed = replace_once(model if target == "model" else media, old, new)
        try:
            verify_texts(public, changed if target == "media" else media, changed if target == "model" else model)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {old}")
    print(f"PASS: exact public model extraction, unchanged media/UI/executor and {len(cases)} rejected mutations", flush=True)
    return public


def theme(identifier="singularity-live", animated=True):
    release = "island-v1" if identifier == "singularity-live" else "island-gifs-v1"
    return dict(schemaVersion=1, id=identifier, version=1,
                packageURL=f"https://github.com/leonardob8777-bit/Eagle-Gallery/releases/download/{release}/{identifier}-v1.zip",
                sha256="a" * 64, byteCount=1024, frameCount=17, fps=6, width=1200, height=500,
                frameSHA256=["a" * 64] * 16 + [("b" if animated else "a") * 64],
                title="Island", titleES="Isla", accent="#20C0F0",
                previewURL=f"https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/previews/island/{identifier}.gif",
                posterURL=f"https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/previews/island/{identifier}.png")


def fixtures():
    result = []
    def add(kind, value):
        result.append({"kind": kind, "json": json.dumps(value, ensure_ascii=False)})
    mutations = {
        "schemaVersion": [0, 2, "1", None], "version": [0, 2, "1", None],
        "id": ["", "UPPER", "a/b", "á", "-bad", "a" * 80, "a" * 81, None],
        "byteCount": [-1, 0, 1, 34 * 1024 * 1024, 34 * 1024 * 1024 + 1, "1024", None],
        "frameCount": [0, 1, 16, 17, 18, None], "fps": [0, 5.9, 6, 6.1, "6", None],
        "width": [0, 1146, 1200, 1201, None], "height": [0, 318, 500, 501, None],
        "sha256": ["", "a" * 63, "a" * 65, "A" * 64, "g" * 64, None],
        "frameSHA256": [[], ["a" * 64], ["a" * 64] * 16, ["a" * 64] * 17,
                         ["a" * 64] * 18, ["a" * 64] * 16 + ["b" * 64], ["a" * 64] * 16 + [""], None],
        "title": ["", "x" * 80, "x" * 81, "🌈" * 80, None],
        "titleES": ["", "x" * 80, "x" * 81, None],
        "accent": ["", "#000000", "#FFFFFF", "#ff00aB", "112233", "#12345", "#GGGGGG", None],
    }
    for key in ("packageURL", "previewURL", "posterURL"):
        mutations[key] = ["https://example.invalid/file", "http://example.invalid/file", "file:///tmp/test", "", None]
    for identifier in ("singularity-live", "blue-flame"):
        base = theme(identifier)
        for animated in (False, True):
            add("theme", theme(identifier, animated))
        for key in base:
            missing = copy.deepcopy(base)
            del missing[key]
            add("theme", missing)
        for key, values in mutations.items():
            for value in values:
                changed = copy.deepcopy(base)
                changed[key] = value
                add("theme", changed)
        for key in ("packageURL", "previewURL", "posterURL"):
            for suffix in ("?download=1", "#fragment", "/"):
                changed = copy.deepcopy(base)
                changed[key] += suffix
                add("theme", changed)
        unknown = copy.deepcopy(base)
        unknown["unrelated"] = {"extra": [1, 2]}
        add("theme", unknown)
    for identifier in ("a", "a" * 80, "a" * 81, "-bad", "UPPER", "a-b_2"):
        add("theme", theme(identifier))
    for count in (0, 1, 2, 499, 500, 501):
        add("catalog", {"schemaVersion": 1, "themes": [theme(f"theme-{i}", i % 2 == 0) for i in range(count)]})
    for payload in (
        {"schemaVersion": 1, "themes": [theme(), theme()]},
        {"schemaVersion": 2, "themes": [theme()]},
        {"schemaVersion": 1, "themes": [dict(theme(), accent="bad")]},
        {"schemaVersion": 1}, {"themes": [theme()]}, {"schemaVersion": 1, "themes": None},
    ):
        add("catalog", payload)
    for malformed in ("null", "[]", "{}", "{", '{"id":true}'):
        for kind in ("theme", "catalog"):
            result.append({"kind": kind, "json": malformed})
    return result


def main():
    repo = Path(__file__).resolve().parents[1]
    public = verify_sources(repo)
    reference = original_models(public).replace("private nonisolated struct", "nonisolated struct")
    for old, new in NAMES:
        reference = reference.replace(old, "Public" + old)
    fixture = "import Foundation\n" + reference
    for prefix, theme_name, catalog_name in (
        ("public", "PublicIslandLiveTheme", "PublicIslandLiveCatalog"),
        ("owned", "EagleIslandGalleryTheme", "EagleIslandGalleryCatalog"),
    ):
        fixture += f'''
nonisolated func {prefix}Snapshot(_ input: Input) -> [String] {{
    let data = Data(input.json.utf8)
    do {{
        func describe(_ theme: {theme_name}) -> [String] {{
            let m = theme.manifest
            let rgb = theme.rgb
            let encoded = try! JSONEncoder().encode(m)
            let object = try! JSONSerialization.jsonObject(with: encoded)
            let normalized = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return [String(m.isSupported), String(theme.isSupported), String(theme.isAnimated), theme.id,
                    theme.title, theme.titleES, theme.accent, theme.previewURL.absoluteString, theme.posterURL.absoluteString,
                    String(rgb.red), String(rgb.green), String(rgb.blue), String(decoding: normalized, as: UTF8.self)]
        }}
        if input.kind == "theme" {{ return ["decoded"] + describe(try JSONDecoder().decode({theme_name}.self, from: data)) }}
        let catalog = try JSONDecoder().decode({catalog_name}.self, from: data)
        return ["decoded", String(catalog.schemaVersion), String(catalog.isSupported), String(catalog.themes.count)] + catalog.themes.flatMap(describe)
    }} catch {{ return ["decode-error"] }}
}}
'''
    fixture += '''
nonisolated struct Input: Decodable, Sendable { let kind: String; let json: String }
@main struct Checks {
    static func main() async throws {
        let inputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        for (index, input) in inputs.enumerated() {
            precondition(publicSnapshot(input) == ownedSnapshot(input), "Public parity failed at \\(index)")
            let detached = await Task.detached { ownedSnapshot(input) }.value
            precondition(detached == publicSnapshot(input), "Detached parity failed at \\(index)")
        }
        let decoder = JSONDecoder()
        let live = try decoder.decode(EagleIslandGalleryTheme.self, from: Data(inputs[1].json.utf8))
        let still = try decoder.decode(EagleIslandGalleryTheme.self, from: Data(inputs[0].json.utf8))
        precondition(live.manifest.frameCount == 17 && still.manifest.frameCount == 17)
        precondition(live.isSupported && still.isSupported && live.isAnimated && !still.isAnimated)
        precondition(live.rgb.red == 32 && live.rgb.green == 192 && live.rgb.blue == 240)
        print("PASS: \\(inputs.count) public/owned decoding, validation, classification, RGB and manifest encoding cases, also detached")
        print("PASS: 17-frame Static/Live classification preserved; actual owned Foundation-only types")
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="eagle-island-model-") as directory:
        work = Path(directory)
        source = work / "ModelChecks.swift"
        source.write_text(fixture)
        cases = work / "cases.json"
        cases.write_text(json.dumps(fixtures(), ensure_ascii=False))
        binary = work / "verify"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        str(repo / MODEL), str(source), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary), str(cases)], check=True, timeout=55)


if __name__ == "__main__":
    main()
