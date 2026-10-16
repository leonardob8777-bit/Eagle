#!/usr/bin/env python3
"""Build only benign Core/adapter/data-store static modules, never the full app.

The real project is read for source membership only. Compilation uses an exact
source allowlist and no app target, bridging header, signing or native engine.
Both temporary static libraries are removed after verification.
Registered app services have dedicated compile/runtime gates; they are not
included in or allowed to weaken this strict Core/data-adapter compilation.
"""
from pathlib import Path
import subprocess
import tempfile


def run(command):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=55)


STORE_RELATIVE_PATH = "lara/EagleAdapters/DockGallery/EagleDockGalleryStore.swift"


def declaration(source, marker):
    assert source.count(marker) == 1, f"Expected exactly one declaration: {marker}"
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        assert end < len(source), "Unbalanced declaration"
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def compact(source):
    return "".join(source.split())


def bootstrap_unit(repo):
    """Compile real app composition plus the exact StateObject binding in a tiny View."""
    from verify_eagle_gallery_services import verify_sources, VIEW_BINDING
    services = verify_sources(repo)
    source = (repo / "lara/views/new/DockGalleryView.swift").read_text()
    store = (repo / STORE_RELATIVE_PATH).read_text()
    assert [line for line in store.splitlines() if line.startswith("import ")] == [
        "import Foundation", "import Combine",
    ], "Gallery Store import boundary changed"
    declaration(store, "@MainActor\nfinal class EagleDockGalleryStore:")
    assert all(name not in store for name in [
        "RemoteCall", "laramgr", "DockGalleryExecutor", "DarkSword",
        "LaraL10n", "CurrentArchiveDiagnostics", "static let shared", "RemoteDockGallery",
        "UIImage", "SwiftUI", "URLSession", "FileManager",
    ]), "Gallery Store regained an app, UI, transport, file or native engine dependency"
    assert store.count("try await packagePreparation.prepare(") == 1
    compact_store = compact(store)
    for field in (
        "private let catalogLoader: EagleDockGalleryCatalogLoader",
        "private let packagePreparation: EagleDockGalleryPackagePreparation",
        "private let catalogFailureMessage: @MainActor @Sendable () -> String",
        "private let diagnostics: @MainActor @Sendable () -> (@Sendable (String) -> Void)",
    ):
        assert compact_store.count(compact(field)) == 1, "Gallery Store immutable injected field changed"
    initializer = declaration(store, "    init(")
    expected_initializer = '''    init(
        catalogLoader: EagleDockGalleryCatalogLoader = EagleDockGalleryCatalogLoader(),
        packagePreparation: EagleDockGalleryPackagePreparation = EagleDockGalleryPackagePreparation(),
        catalogFailureMessage: @escaping @MainActor @Sendable () -> String,
        diagnostics: @escaping @MainActor @Sendable () -> (@Sendable (String) -> Void)
    ) {
        self.catalogLoader = catalogLoader
        self.packagePreparation = packagePreparation
        self.catalogFailureMessage = catalogFailureMessage
        self.diagnostics = diagnostics
    }'''
    assert compact(initializer) == compact(expected_initializer), \
        "Gallery Store initializer defaults or required immutable callbacks changed"
    assert compact_store.count("errorMessage=catalogFailureMessage()") == 1
    assert compact_store.count("diagnostics:diagnostics,") == 1
    for field in (
        "@Published private(set) var themes: [EagleDockGalleryTheme] = []",
        "@Published private(set) var loading = false",
        "@Published private(set) var downloadingID: String?",
        "@Published private(set) var errorMessage: String?",
    ):
        assert compact_store.count(compact(field)) == 1, "Gallery Store published state changed"
    assert all(name not in store for name in (
        "EagleDockGalleryPackageDownloader", "EagleDockGalleryPackageCache",
        "EagleDockGalleryPackagePreparer", "packageDownloader", "packageCache",
        "let destination =", "let cache =", "download(theme)",
    )), "Production Store regained package preparation orchestration responsibilities"
    assert all(name not in store for name in (
        "EagleDockGalleryCacheCommit", "EagleDockGalleryPackageArchive",
        "EagleDockGalleryStagingDirectory", "EagleDockGalleryFrameWriter", "FileManager.default",
    )), "Production Store regained synchronous package preparation responsibilities"
    assert all(name not in store for name in (
        "EagleDockGalleryCacheDirectory", "EagleDockGalleryCachedFrames",
        "EagleDockGalleryFrameImage", "cacheDirectoryService", "func cacheDirectory(", "func validFrames(",
    )), "Production Store regained cache location or image validation responsibilities"
    assert "class RemoteDockGalleryStore" not in source and "class EagleDockGalleryStore" not in source, \
        "Gallery screen regained the Store class"
    assert all(name not in services for name in (
        "RemoteCall", "laramgr", "DockGalleryExecutor", "DarkSword",
    )), "Gallery composition includes a native engine dependency"
    return '''import SwiftUI

nonisolated private enum EagleAppDiagnostics {
    static let log: @Sendable (String) -> Void = { _ in }
}

''' + services + "\nprivate struct GalleryBindingCompileCheck: View {\n" + VIEW_BINDING + '''
    var body: some View { EmptyView() }
}
'''


def main():
    from verify_eagle_core_project_membership import (
        APP_CORE_RELATIVE_PATHS, APP_ADAPTER_RELATIVE_PATHS,
        APP_VALIDATION_RELATIVE_PATHS, inspect_membership, load_project,
    )

    repo = Path(__file__).resolve().parents[1]
    membership = inspect_membership(load_project(repo), repo)
    assert membership["core_count"] == 76 and membership["adapter_count"] == 24
    assert membership["service_count"] == 3 and membership["source_count"] == 103
    assert membership["source_paths"] == list(APP_VALIDATION_RELATIVE_PATHS)
    print(
        f"PASS: real project membership verified for {membership['source_count']} sources "
        f"({membership['core_count']} Core, {membership['adapter_count']} adapters, "
        f"{membership['service_count']} app services; app services have separate compile gates)",
        flush=True,
    )
    core_sources = [repo / path for path in APP_CORE_RELATIVE_PATHS]
    adapter_sources = [repo / path for path in APP_ADAPTER_RELATIVE_PATHS]
    # SurfacePicker now uses the shared, visual-only button feedback. Compile the
    # real implementation, not a stub; keep the Core/adapter registry unchanged.
    press_style = repo / "lara/views/new/EaglePressableStyle.swift"
    assert [line for line in press_style.read_text().splitlines() if line.startswith("import ")] == ["import SwiftUI"]
    assert APP_ADAPTER_RELATIVE_PATHS.count(STORE_RELATIVE_PATH) == 1, \
        "Actual Gallery Store must be compiled exactly once through the source registry"
    sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"]).stdout.strip()
    common = [
        "-swift-version", "5", "-default-isolation", "MainActor",
        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
        "-target", "arm64-apple-ios16.0", "-sdk", sdk,
        "-enable-upcoming-feature", "MemberImportVisibility",
        "-emit-module", "-emit-library", "-static",
    ]
    with tempfile.TemporaryDirectory(prefix="eagle-core-module-build-") as directory:
        work = Path(directory)
        bootstrap = work / "ExactDockGalleryStoreBootstrap.swift"
        bootstrap.write_text(bootstrap_unit(repo))
        for profile, flags in [
            ("Debug", ["-D", "DEBUG", "-Onone"]),
            ("Release", ["-O", "-whole-module-optimization"]),
        ]:
            module = "EagleCoreValidation" + profile
            library = work / ("lib" + module + ".a")
            module_path = work / (module + ".swiftmodule")
            try:
                run([
                    "xcrun", "--sdk", "iphoneos", "swiftc", *common, *flags,
                    "-module-name", module, "-emit-module-path", str(module_path),
                    "-module-cache-path", str(work / "ModuleCache"),
                    *map(str, core_sources), *map(str, adapter_sources),
                    str(press_style),
                    str(bootstrap), "-o", str(library),
                ])
            except subprocess.CalledProcessError as error:
                if error.stdout:
                    print(error.stdout[-8000:].rstrip(), flush=True)
                if error.stderr:
                    print(error.stderr[-8000:].rstrip(), flush=True)
                raise
            assert library.is_file() and library.stat().st_size > 0
            assert module_path.is_file() and module_path.stat().st_size > 0
            architecture = run(["xcrun", "lipo", "-archs", str(library)]).stdout.strip()
            assert architecture == "arm64", "Isolated library architecture changed"
            symbols = run(["xcrun", "nm", "-u", str(library)]).stdout
            assert all(name not in symbols for name in [
                "laramgr", "RemoteCall", "DarkSword", "darksword", "grabkernel", "libxpf",
            ]), "Isolated module gained a native access/app-manager dependency"
            print(
                f"PASS: {profile} arm64 iOS static library and Swift module emitted from "
                f"{len(core_sources)} Core sources, {len(adapter_sources)} adapters "
                "including unchanged Store, owned composition and exact StateObject binding; no native engine dependency",
                flush=True,
            )
    print("PASS: temporary libraries/modules removed; no app, IPA, signing or installation", flush=True)


if __name__ == "__main__":
    main()
