#!/usr/bin/env python3
"""Check the production filename rule against the exact public implementation."""
from pathlib import Path
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[1]
inventory = repo / "lara/EagleCore/DockGallery/EagleDockGalleryPackageInventory.swift"
archive = repo / "lara/EagleCore/Archives/EagleZIPArchive.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
start = baseline.index('        let expected = Set((1...theme.frameCount).map')
end = baseline.index('\n', baseline.index('guard Set(files.map(\\.path)) == expected', start))
rule = baseline[start:end].replace("theme.frameCount", "frameCount").replace("archive.entries", "entries")
reference = "import Foundation\nnonisolated func publicDockPackageInventory(_ entries: [ZipEntry], frameCount: Int) throws -> [ZipEntry] {\n" + rule + "\n        return files\n}\n"
production = inventory.read_text()
assert textwrap.dedent(rule).strip() == textwrap.dedent(production[production.index('        let expected'):production.index('        return files')]).strip(), "Filename rule changed during extraction"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in ["laramgr", "LaraL10n", "SwiftUI", "UIKit", "FileManager", "URLSession"])
flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(archive), str(inventory)], check=True)
print("PASS: exact public filename rule isolated without the screen, access manager or I/O", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-inventory-") as directory:
    work = Path(directory)
    public = work / "PublicInventory.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(archive), str(inventory), str(public),
        str(repo / "scripts/verify_eagle_dock_package_inventory.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
