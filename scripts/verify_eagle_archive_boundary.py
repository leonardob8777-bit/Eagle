#!/usr/bin/env python3
"""Prove this extraction preserves the public ZIP algorithms and Lara-free Core."""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_log_history import (
    HISTORY_PATH, DELIVERY_PATH, BINDING_PATH, verify_manager_sources,
)

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/Archives/EagleZIPArchive.swift"
adapter = repo / "lara/classes/zipmgr.swift"
verify_manager_sources(repo)
baseline = subprocess.check_output(
    ["git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/classes/zipmgr.swift"],
    cwd=repo, text=True,
)
marker = "nonisolated private let crcTable:"
body = core.read_text().split(marker, 1)[1]
# Reverse ONLY the logging-dependency edits. Every other implementation line
# must remain byte-for-byte equal to the public baseline, including errors.
body = body.replace("    private let log: @Sendable (String) -> Void\n", "")
body = body.replace("    public init(data: Data, log: @escaping @Sendable (String) -> Void) throws {",
                    "    public init(data: Data) throws {")
body = body.replace("        self.log = log\n", "")
body = body.replace("log(error)", "zipLog(error)")
body = body.replace("compressionMethod: UInt16 = 0, log: @Sendable (String) -> Void) throws {",
                    "compressionMethod: UInt16 = 0) throws {")
assert body == baseline.split(marker, 1)[1], "Archive algorithm changed beyond the logging boundary"
imports = [line for line in core.read_text().splitlines() if line.startswith("import ")]
assert imports == ["import Foundation", "import zlib"]
assert "laramgr" not in core.read_text(), "Core depends on the app access manager"
print("PASS: archive algorithms match public 1.0.5 after reversing only sink injection", flush=True)

flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
# No stub, adapter, bridging header, UI or app target is included in this check.
subprocess.run(["swiftc", *flags, "-typecheck", str(core)], check=True)
print("PASS: exact complete production Core compiles without Lara", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-archive-boundary-") as directory:
    binary = Path(directory) / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(core), str(adapter),
        str(repo / HISTORY_PATH), str(repo / DELIVERY_PATH), str(repo / BINDING_PATH),
        str(repo / "scripts/verify_eagle_archive_boundary.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
