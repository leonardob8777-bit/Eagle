#!/usr/bin/env python3
"""Verify the original cache replacement/cleanup scope using standalone Core."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
helper = repo / "lara/EagleCore/DockGallery/EagleDockGalleryCacheCommit.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
start_marker = "            if fm.fileExists(atPath: destination.path)"
end_marker = "\n        return destination"
assert baseline.count(start_marker) == 1, "Public replacement occurrence changed"
start = baseline.index(start_marker)
end = baseline.index(end_marker, start)
tail = baseline[start:end]
for old, count in [("fm.fileExists", 1), ("fm.removeItem", 2), ("fm.moveItem", 1)]:
    assert tail.count(old) == count, "Public filesystem sequence changed: " + old
    tail = tail.replace(old, old.replace("fm.", "fileManager."))
body = "        do {\n            try prepareFrames()\n" + tail
reference = (
    "import Foundation\n@MainActor func publicDockCacheCommit(\n"
    "    staging: URL, to destination: URL, fileManager: FileManager,\n"
    "    prepareFrames: @MainActor () throws -> Void\n"
    ") throws {\n" + body + "\n}\n"
)
production = helper.read_text()
expected = '''@MainActor
enum EagleDockGalleryCacheCommit {
    static func commit(
        staging: URL,
        to destination: URL,
        fileManager: FileManager,
        prepareFrames: @MainActor () throws -> Void
    ) throws {
''' + body + '''
    }
}'''
assert production[production.index("@MainActor\nenum "):].strip() == expected, "Cleanup scope, synchronous nonescaping callback, actor or original replacement order changed"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "UIKit", "SwiftUI", "URLSession", "Task", "DispatchQueue",
    "@unchecked", "@escaping", "@Sendable", "async", "FileManager.default", "replaceItem", "createDirectory",
]), "Cache commit gained scheduling, preparation, rollback or app dependencies"
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(helper)], check=True)
print("PASS: exact public replacement/cleanup projection, nonescaping synchronous actor callback and Foundation-only compilation", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-cache-commit-") as directory:
    work = Path(directory)
    public = work / "PublicCacheCommit.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(helper), str(public),
        str(repo / "scripts/verify_eagle_dock_cache_commit.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary), str(work)], check=True, timeout=30)
