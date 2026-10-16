#!/usr/bin/env python3
"""Typecheck the actual Gallery Store, benign Core and adapters with the iOS SDK.

This creates no app or executable and excludes Prepare and native executors.
Only the diagnostic logger is stubbed in the exact owned composition; localization
uses the registered Core source, and the Store is compiled unchanged once.
"""
from pathlib import Path
import subprocess
import tempfile
from verify_eagle_core_project_membership import (
    APP_CORE_RELATIVE_PATHS, APP_ADAPTER_RELATIVE_PATHS,
)
from verify_eagle_core_module_build import STORE_RELATIVE_PATH, bootstrap_unit

repo = Path(__file__).resolve().parents[1]
bootstrap = bootstrap_unit(repo)
core_sources = [repo / path for path in APP_CORE_RELATIVE_PATHS]
adapter_sources = [repo / path for path in APP_ADAPTER_RELATIVE_PATHS]
assert len(core_sources) == 76 and len(adapter_sources) == 24
assert APP_ADAPTER_RELATIVE_PATHS.count(STORE_RELATIVE_PATH) == 1
assert all(path.is_file() for path in core_sources + adapter_sources)
sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors",
         "-target", "arm64-apple-ios16.0", "-sdk", sdk, "-typecheck"]
with tempfile.TemporaryDirectory(prefix="eagle-dock-store-compile-") as directory:
    unit = Path(directory) / "ExactDockGalleryStoreBootstrap.swift"
    unit.write_text(bootstrap)
    subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", *flags,
                    *map(str, core_sources), *map(str, adapter_sources),
                    str(repo / "lara/views/new/EaglePressableStyle.swift"),
                    str(unit)], check=True, timeout=55)
print("PASS: unchanged production Gallery Store source, 76 benign Core files and 24 adapters "
      "typecheck together for iOS with owned composition, exact StateObject binding, localization and an inert logger; "
      "no duplicate Store, native engine or app binary")
