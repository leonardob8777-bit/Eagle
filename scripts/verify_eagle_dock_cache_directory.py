#!/usr/bin/env python3
"""Check cache-location delegation against the exact public Foundation sequence."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/DockGallery"
production_path = core / "EagleDockGalleryCacheDirectory.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
start = baseline.index("    private func cacheDirectory(for theme:")
end = baseline.index("\n    }", start)
body = baseline[start:end].split("throws -> URL {\n", 1)[1]
body = body.replace("FileManager.default", "fileManager()")
reference = (
    "import Foundation\n@MainActor func publicDockCacheDirectory(\n"
    "    for theme: EagleDockGalleryTheme,\n"
    "    fileManager: @MainActor @Sendable () -> FileManager\n"
    ") throws -> URL {\n" + body + "\n}\n"
)
production = production_path.read_text()
expected = '''@MainActor
struct EagleDockGalleryCacheDirectory {
    typealias FileManagerProvider = @MainActor @Sendable () -> FileManager

    private let fileManager: FileManagerProvider

    nonisolated init(fileManager: @escaping FileManagerProvider = { FileManager.default }) {
        self.fileManager = fileManager
    }

    func directory(for theme: EagleDockGalleryTheme) throws -> URL {
''' + body + '''
    }
}'''
assert production[production.index("@MainActor\nstruct "):].strip() == expected, "Actor, provider/default initializer or public directory sequence changed"
assert body.count("fileManager()") == 2, "Public per-operation manager lookup changed"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "UIKit", "SwiftUI", "URLSession", "Task", "DispatchQueue", "@unchecked",
]), "Cache-location boundary gained app, network or scheduling dependencies"
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
sources = [str(core / "EagleDockGalleryTheme.swift"), str(production_path)]
subprocess.run(["swiftc", *flags, "-typecheck", *sources], check=True)
print("PASS: exact public cache sequence, explicit actor/provider/default initializer and strict standalone Core compilation", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-cache-directory-") as directory:
    work = Path(directory)
    public = work / "PublicCacheDirectory.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", *sources, str(public),
        str(repo / "scripts/verify_eagle_dock_cache_directory.swift"), "-o", str(binary),
    ], check=True)
    # Both intercepted real mkdir cases stay inside this automatically removed root.
    subprocess.run([str(binary), str(work)], check=True, timeout=30)
