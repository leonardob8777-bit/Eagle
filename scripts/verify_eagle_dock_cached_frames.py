#!/usr/bin/env python3
"""Check cached-frame gating and traversal against the public Gallery sequence."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/DockGallery"
helper = core / "EagleDockGalleryCachedFrames.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
start = baseline.index("    private static func validFrames(in directory:")
end = baseline.index("\n    }", start)
body = baseline[start:end].split("-> Bool {\n", 1)[1]


def project(old, new):
    global body
    assert body.count(old) == 1, "Public projection changed: " + old
    body = body.replace(old, new)


project("guard isSupported(theme)", "guard theme.isSupportedPackage")
project("Data(contentsOf: url, options: .mappedIfSafe)", "read(url, .mappedIfSafe)")
project(",\n                  let image = UIImage(data: data)", "")
project("return image.cgImage?.width == theme.width && image.cgImage?.height == theme.height",
        "return validateFrame(data, theme)")
reference = (
    "import Foundation\n@MainActor func publicDockCachedFrames(\n"
    "    in directory: URL, theme: EagleDockGalleryTheme,\n"
    "    read: @MainActor @Sendable (URL, Data.ReadingOptions) throws -> Data,\n"
    "    validateFrame: @MainActor @Sendable (Data, EagleDockGalleryTheme) -> Bool\n"
    ") -> Bool {\n" + body + "\n}\n"
)
production = helper.read_text()
expected = '''@MainActor
enum EagleDockGalleryCachedFrames {
    typealias Read = @MainActor @Sendable (URL, Data.ReadingOptions) throws -> Data
    typealias ValidateFrame = @MainActor @Sendable (Data, EagleDockGalleryTheme) -> Bool

    static func areValid(
        in directory: URL,
        theme: EagleDockGalleryTheme,
        read: Read = { url, options in
            try Data(contentsOf: url, options: options)
        },
        validateFrame: ValidateFrame
    ) -> Bool {
''' + body + '''
    }
}'''
assert production[production.index("@MainActor\nenum "):].strip() == expected, "Actor, injected callbacks/default read or public traversal changed"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "UIKit", "SwiftUI", "UIImage", "CGImage", "URLSession",
    "FileManager", "Task", "DispatchQueue", "@unchecked",
]), "Traversal gained UI, app, scheduling or unrelated I/O dependencies"
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
sources = [str(core / "EagleDockGalleryTheme.swift"), str(helper)]
subprocess.run(["swiftc", *flags, "-typecheck", *sources], check=True)
print("PASS: counted independent public projections, exact actor/callback/default-read contracts and strict standalone Core compilation", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-cached-frames-") as directory:
    work = Path(directory)
    public = work / "PublicCachedFrames.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", *sources, str(public),
        str(repo / "scripts/verify_eagle_dock_cached_frames.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
