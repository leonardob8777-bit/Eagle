#!/usr/bin/env python3
"""Require the Eagle-owned preview loader and its UI wiring to match public Eagle."""

from pathlib import Path
import subprocess
from verify_eagle_remote_media_preview import verify_sources


repo = Path(__file__).resolve().parents[1]
view_path = "lara/views/new/LaraRemoteMediaPreview.swift"
adapter_path = "lara/EagleAdapters/EagleRemoteMediaLoader.swift"
public = subprocess.run(
    ["git", "show", f"823ab22:{view_path}"],
    cwd=repo, check=True, capture_output=True, text=True,
).stdout
adapter = (repo / adapter_path).read_text()

old_marker = "@MainActor\nprivate final class LaraRemoteMediaLoader: ObservableObject {"
new_marker = "@MainActor\nfinal class EagleRemoteMediaLoader: ObservableObject {"
view_marker = "\nstruct LaraRemoteMediaPreview: View {"
assert public.count(old_marker) == 1
assert public.count(view_marker) == 1
start = public.index(old_marker)
end = public.index(view_marker, start)
old_loader = public[start:end]
expected_adapter = (
    "import Foundation\nimport Combine\nimport ImageIO\n\n"
    + old_loader.replace(old_marker, new_marker, 1)
)
assert adapter == expected_adapter, "Media request, cache or cancellation behavior differs from public Eagle"

current_view, _ = verify_sources(repo, public)
assert current_view.count("@StateObject private var loader = EagleRemoteMediaLoader()") == 1
assert current_view.count("EagleRemoteMediaLoader.clearCache()") == 1
assert all(name not in adapter for name in (
    "laramgr", "DarkSword", "RemoteCall", "LaraL10n", "SwiftUI", "WebKit",
)), "Eagle-owned loader gained a screen or native engine dependency"
print("PASS: complete public media loader behavior moved unchanged into EagleAdapters")
print("PASS: owned preview and app bridge preserve public behavior and exact loader wiring")
