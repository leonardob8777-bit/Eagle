#!/usr/bin/env python3
"""Check staging creation against the exact public Gallery Foundation sequence."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
helper = repo / "lara/EagleCore/DockGallery/EagleDockGalleryStagingDirectory.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
start = baseline.index("        let staging = destination.deletingLastPathComponent()")
end = baseline.index("\n        do {", start)
body = baseline[start:end]
for old, new in [("theme.id", "themeID"), ("UUID()", "makeIdentifier()"),
                 ("fm.createDirectory", "fileManager.createDirectory")]:
    assert body.count(old) == 1, "Public staging projection changed: " + old
    body = body.replace(old, new)
body += "\n        return staging"
reference = (
    "import Foundation\n@MainActor func publicDockStagingDirectory(\n"
    "    beside destination: URL, themeID: String, fileManager: FileManager,\n"
    "    makeIdentifier: @MainActor @Sendable () -> UUID\n"
    ") throws -> URL {\n" + body + "\n}\n"
)
production = helper.read_text()
expected = '''@MainActor
enum EagleDockGalleryStagingDirectory {
    typealias MakeIdentifier = @MainActor @Sendable () -> UUID

    static func create(
        beside destination: URL,
        themeID: String,
        fileManager: FileManager,
        makeIdentifier: MakeIdentifier = { UUID() }
    ) throws -> URL {
''' + body + '''
    }
}'''
assert production[production.index("@MainActor\nenum "):].strip() == expected, "Actor, default identifier, state-free API or public creation sequence changed"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "UIKit", "SwiftUI", "URLSession", "Task", "DispatchQueue", "@unchecked",
    "FileManager.default", "removeItem", "moveItem", "write(",
]), "Staging creation gained app, I/O or scheduling dependencies"
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(helper)], check=True)
print("PASS: counted independent public projections, exact actor/default identifier/state-free API and strict Foundation-only compilation", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-staging-directory-") as directory:
    work = Path(directory)
    public = work / "PublicStagingDirectory.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(helper), str(public),
        str(repo / "scripts/verify_eagle_dock_staging_directory.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary), str(work)], check=True, timeout=30)
