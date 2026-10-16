#!/usr/bin/env python3
"""Compare the production dimension rule and lazy reads to the public policy."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
dimensions = repo / "lara/EagleCore/DockGallery/EagleDockGalleryFrameDimensions.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
line = next(line.strip() for line in baseline.splitlines()
            if line.strip().startswith("return image.cgImage?.width == theme.width &&"))
expression = line.removeprefix("return ").replace("image.cgImage?.width", "width")
expression = expression.replace("image.cgImage?.height", "height()")
expression = expression.replace("theme.width", "expectedWidth").replace("theme.height", "expectedHeight()")
reference = "nonisolated func publicDockFrameDimensions(width: Int?, height: @autoclosure () -> Int?, expectedWidth: Int, expectedHeight: @autoclosure () -> Int) -> Bool {\n    " + expression + "\n}\n"
production = dimensions.read_text()
assert production.split("-> Bool {", 1)[1].split("\n    }", 1)[0].strip() == expression
assert not any(line.startswith("import ") for line in production.splitlines())
assert all(name not in production for name in ["laramgr", "LaraL10n", "UIKit", "SwiftUI", "UIImage", "CGImage", "URLSession", "FileManager"])
flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(dimensions)], check=True)
print("PASS: exact public dimension rule compiles with Swift alone, without the image decoder or app", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-dimensions-") as directory:
    work = Path(directory)
    public = work / "PublicFrameDimensions.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(dimensions), str(public),
        str(repo / "scripts/verify_eagle_dock_frame_dimensions.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
