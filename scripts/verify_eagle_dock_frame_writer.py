#!/usr/bin/env python3
"""Check the atomic frame-write delegation against the exact public statement."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
helper = repo / "lara/EagleCore/DockGallery/EagleDockGalleryFrameWriter.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
statement = next(line.strip() for line in baseline.splitlines()
                 if line.strip().startswith("try frameData.write(to: staging."))
assert baseline.count(statement) == 1, "Public atomic-write occurrence changed"
for old, new in [("frameData.write(to: ", "write(data, "), ("staging", "directory"),
                 ("entry.path", "framePath"), ("options: .atomic", ".atomic")]:
    assert statement.count(old) == 1, "Public write projection changed: " + old
    statement = statement.replace(old, new)
reference = (
    "import Foundation\n@MainActor func publicDockFrameWrite(\n"
    "    _ data: Data, framePath: String, in directory: URL,\n"
    "    using write: @MainActor @Sendable (Data, URL, Data.WritingOptions) throws -> Void\n"
    ") throws {\n    " + statement + "\n}\n"
)
production = helper.read_text()
expected = '''@MainActor
enum EagleDockGalleryFrameWriter {
    typealias Write = @MainActor @Sendable (Data, URL, Data.WritingOptions) throws -> Void

    static func write(
        _ data: Data,
        framePath: String,
        in directory: URL,
        using write: Write = { data, url, options in
            try data.write(to: url, options: options)
        }
    ) throws {
        ''' + statement + '''
    }
}'''
assert production[production.index("@MainActor\nenum "):].strip() == expected, "Actor, default write, state-free API or public atomic delegation changed"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "UIKit", "SwiftUI", "UIImage", "CGImage", "FileManager", "URLSession",
    "Task", "DispatchQueue", "@unchecked", "removeItem", "moveItem",
]), "Frame writing gained validation, cleanup, app or scheduling dependencies"
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(helper)], check=True)
print("PASS: counted independent public write projection, exact actor/default-write/state-free API and strict Foundation-only compilation", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-frame-writer-") as directory:
    work = Path(directory)
    public = work / "PublicFrameWriter.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(helper), str(public),
        str(repo / "scripts/verify_eagle_dock_frame_writer.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary), str(work)], check=True, timeout=30)
