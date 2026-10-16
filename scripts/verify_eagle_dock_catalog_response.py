#!/usr/bin/env python3
"""Compare the pure catalog response gate with the exact public rule."""

from pathlib import Path
import subprocess
import tempfile
import textwrap


repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/DockGallery/EagleDockGalleryCatalogResponse.swift"
view = repo / "lara/views/new/DockGalleryView.swift"
baseline = subprocess.check_output(
    [
        "git",
        "show",
        "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift",
    ],
    cwd=repo,
    text=True,
)

load_start = baseline.index("    func load(force: Bool = false) async {")
rule_start = baseline.index("            guard let http = response as? HTTPURLResponse,", load_start)
rule_end = baseline.index("\n            let catalog = try JSONDecoder()", rule_start)
public_rule = textwrap.dedent(baseline[rule_start:rule_end]).strip()
reference = (
    "import Foundation\n"
    "nonisolated func publicDockCatalogResponseValidate(_ data: Data, response: URLResponse) throws {\n"
    + textwrap.indent(public_rule, "    ")
    + "\n}\n"
)

production = core.read_text()
body_start = production.index("        guard let httpStatusCode,")
body_end = production.index("\n    }", body_start)
actual_rule = textwrap.dedent(production[body_start:body_end]).strip()
projected_rule = public_rule.replace(
    "guard let http = response as? HTTPURLResponse,", "guard let httpStatusCode,"
).replace("http.statusCode", "httpStatusCode")
assert actual_rule == projected_rule, "Catalog response guard changed beyond the HTTP status projection"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(
    name not in production
    for name in ["laramgr", "LaraL10n", "UIKit", "SwiftUI", "URLSession", "URLResponse", "FileManager", "Task", "DispatchQueue"]
), "Catalog response Core gained a UI, network, filesystem, or scheduling dependency"

loader = repo / "lara/EagleCore/DockGallery/EagleDockGalleryCatalogLoader.swift"
current_load = loader.read_text().split("    func load(force: Bool = false) async throws", 1)[1]
receive = current_load.index("let (data, response) = try await fetch(request)")
validate = current_load.index("try EagleDockGalleryCatalogResponse.validate(")
decode = current_load.index("return try EagleDockGalleryCatalog.decodeSupportedThemes(from: data)")
assert receive < validate < decode, "Catalog response validation moved relative to receive/decode"
assert "httpStatusCode: (response as? HTTPURLResponse)?.statusCode" in current_load[
    validate:decode
], "Catalog response no longer receives the original HTTP status"
from verify_eagle_core_module_build import STORE_RELATIVE_PATH, bootstrap_unit
bootstrap_unit(repo)  # Exact extracted Store/composition boundary, not a copied Store.
current_store_load = (repo / STORE_RELATIVE_PATH).read_text().split("    func load(force: Bool = false) async {", 1)[1].split("\n    func prepare(", 1)[0]
assert current_store_load.count("themes = try await catalogLoader.load(force: force)") == 1

flags = [
    "-swift-version", "5", "-default-isolation", "MainActor",
    "-strict-concurrency=complete", "-warnings-as-errors",
]
subprocess.run(["swiftc", *flags, "-typecheck", str(core)], check=True)
print("PASS: exact public catalog response rule, Foundation-only Core and original receive/decode order", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-catalog-response-") as directory:
    work = Path(directory)
    public = work / "PublicCatalogResponse.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run(
        [
            "swiftc", *flags, "-parse-as-library", str(core), str(public),
            str(repo / "scripts/verify_eagle_dock_catalog_response.swift"), "-o", str(binary),
        ],
        check=True,
    )
    subprocess.run([str(binary)], check=True, timeout=30)
