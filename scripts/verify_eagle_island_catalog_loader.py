#!/usr/bin/env python3
"""Verify Island transport/cache extraction with temporary files and injected transport."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
MEDIA = "lara/views/new/IslandLiveMedia.swift"
LOADER = "lara/EagleAdapters/IslandGallery/EagleIslandGalleryCatalogLoader.swift"
MODEL = "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift"
MARKER = "static func loadCatalog("
BRIDGE = '''static func loadCatalog(force: Bool = false) async throws -> [IslandLiveTheme] {
        try await EagleIslandGalleryCatalogLoader.loadCatalog(force: force)
    }'''
HEADER = '''static func loadCatalog(
        force: Bool = false,
        fileManager: FileManager = .default,
        fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async throws -> [EagleIslandGalleryTheme]'''
PREFIX = '''import Foundation

/// Owns Island catalog transport, validation and disk fallback outside the media facade.
/// Default ports retain the public cache location and shared network session.
nonisolated enum EagleIslandGalleryCatalogLoader {
    '''


def original():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{MEDIA}"], cwd=repo, text=True)
    return declaration(public, MARKER)


def inline_catalog_loader(media):
    from verify_eagle_island_package import inline_package
    media = inline_package(media)
    return replace_once(media, BRIDGE, original())


def injected_reference():
    method = original()
    for old, new in (
        ("static func loadCatalog(force: Bool = false) async throws -> [IslandLiveTheme]", HEADER),
        ("let fm = FileManager.default", "let fm = fileManager"),
        ("try await URLSession.shared.data(for: request)", "try await fetch(request)"),
    ):
        method = replace_once(method, old, new)
    assert method.count("IslandLiveCatalog.self") == 2
    return method.replace("IslandLiveCatalog.self", "EagleIslandGalleryCatalog.self")


def verify_texts(media, loader):
    assert hashlib.sha256(inline_catalog_loader(media).encode()).hexdigest() == "7687fe79e838d8a5515dfc041594fc704517d00cab6b38cc76eef36637e1d9ee", "Unrelated media/package change"
    assert loader == PREFIX + injected_reference() + "\n}\n", "Loader differs from full public body/default ports"


def verify_sources(repo):
    media, loader = [(repo / p).read_text() for p in (MEDIA, LOADER)]
    verify_texts(media, loader)
    from verify_eagle_island_load_flow import inline_load_flow
    screen = inline_load_flow((repo / "lara/views/new/IslandGalleryPresentation.swift").read_text())
    assert hashlib.sha256(screen.encode()).hexdigest() == "de94ea7f78da18d4de3937196592fc6ef158b6b91f45ef7e67cee6fc6d637d38", "Screen changed beyond verified load flow"
    cases = [
        (0, "loadCatalog(force: force)", "loadCatalog(force: false)"),
        (0, "import UIKit", "import UIKit\n// unrelated"),
        (1, "fileManager: FileManager = .default", "fileManager: FileManager = FileManager()"),
        (1, "URLSession.shared.data", "URLSession.shared.download"),
        (1, "create: true", "create: false"),
        (1, '"EagleGallery/Island"', '"EagleGallery/Dock"'),
        (1, 'root.appendingPathComponent("island-gallery-v1.json")', 'root.appendingPathComponent("new.json")'),
        (1, "request.timeoutInterval = 25", "request.timeoutInterval = 90"),
        (1, ".useProtocolCachePolicy", ".returnCacheDataElseLoad"),
        (1, "force ? .reloadIgnoringLocalCacheData", "!force ? .reloadIgnoringLocalCacheData"),
        (1, "response.statusCode == 200", "response.statusCode < 400"),
        (1, "data.count <= 2 * 1024 * 1024 else { throw URLError(.badServerResponse)", "data.count < 2 * 1024 * 1024 else { throw URLError(.badServerResponse)"),
        (1, "try data.write(to: saved, options: .atomic)", "// skipped cache write"),
        (1, "let data = try Data(contentsOf: saved)", "throw error\n            let data = try Data(contentsOf: saved)"),
        (1, "guard data.count <= 2 * 1024 * 1024", "guard data.count <= 3 * 1024 * 1024"),
        (1, "import Foundation", "import Foundation\nimport UIKit"),
    ]
    for index, before, after in cases:
        values = [media, loader]; values[index] = replace_once(values[index], before, after)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted regression: {before}")
    print(f"PASS: complete public catalog loader, exact default ports/bridge, unchanged package/screen; {len(cases)} rejected mutations", flush=True)


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    fixture = (repo / "scripts/verify_eagle_island_catalog_loader.swift").read_text()
    fixture += "\nnonisolated enum PublicLoader {\n    " + injected_reference() + "\n}\n"
    from verify_eagle_island_catalog import theme
    with tempfile.TemporaryDirectory(prefix="eagle-island-catalog-loader-") as directory:
        work = Path(directory)
        for label, identifier in (("a", "singularity-live"), ("b", "blue-flame")):
            (work / f"{label}.json").write_text(json.dumps({"schemaVersion": 1, "themes": [theme(identifier)]}))
        source = work / "Checks.swift"; binary = work / "verify"
        source.write_text(fixture)
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        str(repo / MODEL), str(repo / LOADER), str(source), "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary), str(work)], check=True, timeout=55)


if __name__ == "__main__":
    main()
