#!/usr/bin/env python3
"""Check the pure catalog decoder against its exact public sequence and rule.

The reference projects only the public theme field type onto the previously
parity-tested EagleDockGalleryTheme; the catalog declaration, default decoder,
schema check, and support predicate come from the exact public source.
"""
from pathlib import Path
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[1]
core_dir = repo / "lara/EagleCore/DockGallery"
model = core_dir / "EagleDockGalleryTheme.swift"
catalog = core_dir / "EagleDockGalleryCatalog.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


public_catalog = declaration(baseline, "private struct RemoteDockGalleryCatalog:")
public_catalog = public_catalog.replace(
    "private struct RemoteDockGalleryCatalog:", "nonisolated struct PublicDockGalleryCatalog:"
).replace("[RemoteDockGalleryTheme]", "[EagleDockGalleryTheme]")
public_support = declaration(baseline, "private static func isSupported(_ theme:")
public_support = public_support.replace(
    "private static func isSupported(_ theme: RemoteDockGalleryTheme)",
    "nonisolated func publicDockCatalogSupports(_ theme: EagleDockGalleryTheme)"
)
start = baseline.index("            let catalog = try JSONDecoder().decode(RemoteDockGalleryCatalog.self, from: data)")
end = baseline.index("\n        } catch {", start)
public_sequence = textwrap.dedent(baseline[start:end])
assert public_sequence.count("\n") == 2, "Public catalog sequence changed"
reference_sequence = public_sequence.replace(
    "RemoteDockGalleryCatalog.self", "PublicDockGalleryCatalog.self"
).replace("themes = catalog.themes.filter(Self.isSupported)", "return catalog.themes.filter(publicDockCatalogSupports)")
reference = (
    "import Foundation\n" + public_catalog + "\n" + public_support
    + "\nnonisolated func publicDockCatalogDecode(_ data: Data) throws -> [EagleDockGalleryTheme] {\n"
    + textwrap.indent(reference_sequence, "    ") + "\n}\n"
)

production = catalog.read_text()
stored = [line.strip() for line in production.splitlines() if line.strip().startswith("let ") and "=" not in line]
assert stored == ["let schemaVersion: Int", "let themes: [EagleDockGalleryTheme]"], "Catalog fields changed"
method = declaration(production, "static func decodeSupportedThemes(from data: Data)")
actual_sequence = textwrap.dedent(method[method.index("{") + 1:-1]).strip()
expected_sequence = public_sequence.replace("RemoteDockGalleryCatalog.self", "EagleDockGalleryCatalog.self").replace(
    "themes = catalog.themes.filter(Self.isSupported)", "return catalog.themes.filter { $0.isSupportedPackage }"
)
assert actual_sequence == expected_sequence, "Catalog behavior changed beyond the explicit pure delegation"
support_body = public_support[public_support.index("{") + 1:-1].replace("theme.", "")
actual_support = declaration(model.read_text(), "var isSupportedPackage: Bool")
assert textwrap.dedent(actual_support[actual_support.index("{") + 1:-1]).strip() == textwrap.dedent(support_body).strip()
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "SwiftUI", "UIKit", "URLSession", "URLResponse", "FileManager", "Task", "DispatchQueue"
])
flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
print("PASS: exact public catalog fields, decode/schema/filter order and support rule; Foundation-only Core", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-catalog-") as directory:
    work = Path(directory)
    public = work / "PublicCatalog.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(model), str(catalog), str(public),
        str(repo / "scripts/verify_eagle_dock_catalog.swift"), "-o", str(binary)
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
