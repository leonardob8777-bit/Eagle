#!/usr/bin/env python3
"""Validate the production pure download rule against the exact public code."""
from pathlib import Path
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[1]
validation = repo / "lara/EagleCore/DockGallery/EagleDockGalleryPackageValidation.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
prepare = baseline.index("    func prepare(_ theme:")
start = baseline.index("        guard let http = response as? HTTPURLResponse,", prepare)
end = baseline.index("\n\n        let archive = try ZipArchive(data: data)", start)
rule = baseline[start:end].replace("theme.byteCount", "expectedByteCount").replace("theme.sha256", "expectedSHA256")
reference = "import Foundation\nimport CryptoKit\nnonisolated func publicDockDownloadValidation(_ data: Data, response: URLResponse, expectedByteCount: Int, expectedSHA256: String) throws {\n" + rule + "\n}\n"
production = validation.read_text()
body = production[production.index("        guard let httpStatusCode,"):].rsplit("\n    }", 1)[0]
body = body.replace("guard let httpStatusCode,", "guard let http = response as? HTTPURLResponse,")
body = body.replace("contains(httpStatusCode)", "contains(http.statusCode)")
assert textwrap.dedent(body).strip() == textwrap.dedent(rule).strip(), "Public download rule changed beyond the scalar status projection"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation", "import CryptoKit"]
assert all(name not in production for name in ["laramgr", "LaraL10n", "UIKit", "SwiftUI", "URLSession", "URLResponse", "FileManager", "Task", "DispatchQueue"])
flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(validation)], check=True)
print("PASS: exact public download rule compiles without UI/Lara/network/filesystem or scheduling changes", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-download-") as directory:
    work = Path(directory)
    public = work / "PublicDownloadValidation.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(validation), str(public),
        str(repo / "scripts/verify_eagle_dock_download.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
