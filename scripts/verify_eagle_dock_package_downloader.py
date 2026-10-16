#!/usr/bin/env python3
"""Compare the package downloader with the exact public request/validation sequence."""
from pathlib import Path
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/DockGallery"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
prepare = baseline.index("    func prepare(_ theme:")
start = baseline.index("        var request = URLRequest(url: theme.packageURL)", prepare)
end = baseline.index("\n\n        let archive = try ZipArchive(data: data)", start)
sequence = textwrap.dedent(baseline[start:end]).replace(
    "URLSession.shared.data(for: request)", "fetch(request)"
)
reference = (
    "import Foundation\nimport CryptoKit\n"
    "@MainActor func publicDockPackageDownload(_ theme: EagleDockGalleryTheme, "
    "fetch: EagleDockGalleryPackageDownloader.Fetch) async throws -> Data {\n"
    + textwrap.indent(sequence, "    ") + "\n    return data\n}\n"
)
production = (core / "EagleDockGalleryPackageDownloader.swift").read_text()
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert "@MainActor\nstruct EagleDockGalleryPackageDownloader {" in production
assert "typealias Fetch = @MainActor @Sendable (URLRequest) async throws -> (Data, URLResponse)" in production
initializer = '''    nonisolated init(fetch: @escaping Fetch = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.fetch = fetch
    }'''
assert initializer in production, "Default shared-session transport or initialization changed"
method = "    func download(_ theme: EagleDockGalleryTheme) async throws -> Data {"
actual = textwrap.dedent(production.split(method, 1)[1].rsplit("\n    }", 1)[0]).strip()
expected = '''var request = URLRequest(url: theme.packageURL)
request.timeoutInterval = 90
request.cachePolicy = .reloadIgnoringLocalCacheData
let (data, response) = try await fetch(request)
try EagleDockGalleryPackageValidation.validateDownload(
    data,
    httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
    expectedByteCount: theme.byteCount,
    expectedSHA256: theme.sha256
)
return data'''
assert actual == expected, "Package download pipeline changed beyond the public delegation"
assert all(name not in production for name in ["laramgr", "LaraL10n", "UIKit", "SwiftUI", "FileManager", "Task", "DispatchQueue"])
flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
with tempfile.TemporaryDirectory(prefix="eagle-dock-package-downloader-") as directory:
    work = Path(directory)
    public = work / "PublicPackageDownloader.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library",
        *[str(core / name) for name in [
            "EagleDockGalleryTheme.swift", "EagleDockGalleryPackageValidation.swift",
            "EagleDockGalleryPackageDownloader.swift"
        ]],
        str(public), str(repo / "scripts/verify_eagle_dock_package_downloader.swift"),
        "-o", str(binary)
    ], check=True)
    print("PASS: independent public request/await/guard/hash reference; explicit actor/shared-session contracts; Swift 5, complete concurrency, warnings as errors", flush=True)
    subprocess.run([str(binary)], check=True, timeout=30)
