#!/usr/bin/env python3
"""Compare the injected catalog loader with the exact public async sequence."""
from pathlib import Path
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/DockGallery"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


public_catalog = declaration(baseline, "private struct RemoteDockGalleryCatalog:").replace(
    "private struct RemoteDockGalleryCatalog:", "nonisolated struct PublicDockGalleryCatalog:"
).replace("[RemoteDockGalleryTheme]", "[EagleDockGalleryTheme]")
public_support = declaration(baseline, "private static func isSupported(_ theme:").replace(
    "private static func isSupported(_ theme: RemoteDockGalleryTheme)",
    "nonisolated func publicDockCatalogSupports(_ theme: EagleDockGalleryTheme)"
)
url_line = next(line.strip() for line in baseline.splitlines() if line.strip().startswith("private let catalogURL ="))
start = baseline.index("            var request = URLRequest(url: catalogURL)")
end = baseline.index("\n        } catch {", start)
public_sequence = textwrap.dedent(baseline[start:end]).replace(
    "URLSession.shared.data(for: request)", "fetch(request)"
).replace("RemoteDockGalleryCatalog.self", "PublicDockGalleryCatalog.self").replace(
    "themes = catalog.themes.filter(Self.isSupported)", "return catalog.themes.filter(publicDockCatalogSupports)"
)
reference = (
    "import Foundation\n" + public_catalog + "\n" + public_support
    + "\n@MainActor func publicDockCatalogLoad(force: Bool = false, fetch: EagleDockGalleryCatalogLoader.Fetch) async throws -> [EagleDockGalleryTheme] {\n"
    + "    " + url_line.replace("private let", "let") + "\n"
    + textwrap.indent(public_sequence, "    ") + "\n}\n"
)
loader = core / "EagleDockGalleryCatalogLoader.swift"
production = loader.read_text()
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in ["laramgr", "LaraL10n", "SwiftUI", "UIKit", "FileManager", "DispatchQueue"])
assert url_line in production, "Catalog endpoint changed"
method = declaration(production, "func load(force: Bool = false)")
body = textwrap.dedent(method[method.index("{") + 1:-1]).strip()
expected = """var request = URLRequest(url: catalogURL)
request.timeoutInterval = 25
request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
let (data, response) = try await fetch(request)
try EagleDockGalleryCatalogResponse.validate(
    data: data,
    httpStatusCode: (response as? HTTPURLResponse)?.statusCode
)
return try EagleDockGalleryCatalog.decodeSupportedThemes(from: data)"""
assert body == expected, "Loader sequence differs from the approved public delegation"
flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
print("PASS: public endpoint/request/async validation order; Foundation-only injected loader", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-catalog-loader-") as directory:
    work = Path(directory)
    public = work / "PublicLoader.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library",
        *[str(core / name) for name in ["EagleDockGalleryTheme.swift", "EagleDockGalleryCatalog.swift", "EagleDockGalleryCatalogResponse.swift", "EagleDockGalleryCatalogLoader.swift"]],
        str(public), str(repo / "scripts/verify_eagle_dock_catalog_loader.swift"), "-o", str(binary)
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
