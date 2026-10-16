#!/usr/bin/env python3
"""Compare exact public/production Gallery stores in a disposable iOS Simulator.

The public Store uses counted networking/FileManager fixture seams; the actual
owned Store compiles unchanged and receives injected test services. The compiled
sources contain the benign Gallery data store, Core and adapters, not the app
or its native applying/access engine. All files belong to a fresh temporary
directory, and only a simulator created by this invocation is removed.
"""
from pathlib import Path
import argparse
import io
import json
import platform
import struct
import subprocess
import sys
import tempfile
import uuid
import zipfile
import zlib
from verify_eagle_core_project_membership import (
    APP_CORE_RELATIVE_PATHS, APP_ADAPTER_RELATIVE_PATHS,
)


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
STORE_MARKER = "@MainActor\nprivate final class RemoteDockGalleryStore:"
PACKAGE_PREPARER_PATH = "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparer.swift"
PACKAGE_CACHE_PATH = "lara/EagleAdapters/DockGallery/EagleDockGalleryPackageCache.swift"
PACKAGE_PREPARATION_PATH = "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparation.swift"
OWNED_STORE_PATH = "lara/EagleAdapters/DockGallery/EagleDockGalleryStore.swift"


def declaration(source, marker):
    assert source.count(marker) == 1, "Expected exactly one Gallery store"
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        assert end < len(source), "Unbalanced Gallery store declaration"
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def replace_counted(source, old, new, count, label):
    assert source.count(old) == count, f"Fixture seam changed: {label}"
    return source.replace(old, new)


def fixture_public_store(source):
    store = declaration(source, STORE_MARKER)
    assert all(value not in store for value in (
        "RemoteCall", "laramgr", "DockGalleryExecutor", "DarkSword",
    )), "Gallery store includes an out-of-scope native dependency"
    store = replace_counted(
        store, "private final class RemoteDockGalleryStore:",
        "final class PublicDockGalleryStore:", 1, "public class name/access",
    )
    store = replace_counted(
        store, "RemoteDockGalleryStore()", "PublicDockGalleryStore()", 1, "public shared store initializer",
    )
    store = replace_counted(
        store, "FileManager.default", "FixtureContext.fileManager",
        3, "public fixture FileManager",
    )
    store = replace_counted(
        store, "URLSession.shared.data(for: request)", "FixtureContext.fetch(request)",
        2, "public fixture transport",
    )
    assert "URLSession.shared" not in store and "FileManager.default" not in store
    assert "RemoteDockGalleryStore" not in store
    return store


def fixture_package_preparer(source):
    assert source.count("@MainActor\nenum EagleDockGalleryPackagePreparer {") == 1
    assert all(value not in source for value in (
        "RemoteCall", "laramgr", "DockGalleryExecutor", "DarkSword", "URLSession",
    )), "Package preparer includes an out-of-scope native or networking dependency"
    prepared = replace_counted(
        source, "FileManager.default", "FixtureContext.fileManager",
        1, "production package preparer FileManager",
    )
    assert "FileManager.default" not in prepared
    return prepared


def generated_stores(public):
    adapters = """import Foundation
import UIKit
import Combine
import CryptoKit

typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
typealias RemoteDockGalleryCatalog = EagleDockGalleryCatalog
typealias ProductionDockGalleryStore = EagleDockGalleryStore

private enum LaraL10n {
    static func text(en: String, es: String) -> String { FixtureLocalization.text(en: en, es: es) }
}

nonisolated private enum CurrentArchiveDiagnostics {
    static let log: @Sendable (String) -> Void = { _ in }
}

nonisolated extension ZipArchive {
    convenience init(data: Data) throws {
        try self.init(data: data, log: CurrentArchiveDiagnostics.log)
    }
}

"""
    fixture_factory = """extension EagleDockGalleryStore {
    static func fixture() -> EagleDockGalleryStore {
        EagleDockGalleryStore(
            catalogLoader: EagleDockGalleryCatalogLoader(fetch: { request in
                try await FixtureContext.fetch(request)
            }),
            packagePreparation: EagleDockGalleryPackagePreparation(
                downloader: EagleDockGalleryPackageDownloader(fetch: { request in
                    try await FixtureContext.fetch(request)
                }),
                cache: EagleDockGalleryPackageCache(directories:
                    EagleDockGalleryCacheDirectory(fileManager: { FixtureContext.fileManager }))
            ),
            catalogFailureMessage: {
                FixtureLocalization.text(
                    en: "The online collection could not be loaded.",
                    es: "No se pudo cargar la colección en línea."
                )
            },
            diagnostics: { CurrentArchiveDiagnostics.log }
        )
    }
}

"""
    extensions = ""
    for name in ("PublicDockGalleryStore", "EagleDockGalleryStore"):
        extensions += f"""extension {name}: FixtureStore {{
    var stateChanges: AnyPublisher<String?, Never> {{ $downloadingID.eraseToAnyPublisher() }}
    var loadingChanges: AnyPublisher<Bool, Never> {{ $loading.eraseToAnyPublisher() }}
    var themeChanges: AnyPublisher<[EagleDockGalleryTheme], Never> {{ $themes.eraseToAnyPublisher() }}
    var errorChanges: AnyPublisher<String?, Never> {{ $errorMessage.eraseToAnyPublisher() }}
}}
"""
    return adapters + fixture_public_store(public) + "\n\n" + fixture_factory + extensions


def png_bytes(width, height, rgba=(32, 192, 240, 255)):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(
            ">I", zlib.crc32(kind + payload) & 0xFFFFFFFF,
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    assert len(rgba) == 4 and all(0 <= component <= 255 for component in rgba)
    row = b"\x00" + bytes(rgba) * width
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + \
        chunk(b"IDAT", zlib.compress(row * height, level=9)) + chunk(b"IEND", b"")


def archive_bytes(entries, *, deflated=False):
    buffer = io.BytesIO()
    method = zipfile.ZIP_DEFLATED if deflated else zipfile.ZIP_STORED
    with zipfile.ZipFile(buffer, "w", compression=method, allowZip64=False) as archive:
        for name, data in entries:
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = method
            archive.writestr(entry, data)
    return buffer.getvalue()


def write_fixtures(root):
    valid = png_bytes(1146, 318)
    wrong_width = png_bytes(1145, 318)
    invalid = b"Eagle fixture: not an image"
    live_frames = [
        png_bytes(1146, 318, rgba=((index * 13) % 256, (index * 29) % 256, (index * 47) % 256, 255))
        for index in range(1, 18)
    ]
    assert len(set(live_frames)) == 17, "Live frame payloads must be distinct"
    static = archive_bytes([("frame01.png", valid)])
    bad_crc = bytearray(static)
    end_record = bad_crc.rfind(b"PK\x05\x06")
    assert end_record >= 0, "Fixture archive has no end-of-central-directory record"
    central = struct.unpack_from("<I", bad_crc, end_record + 16)[0]
    assert bad_crc[central:central + 4] == b"PK\x01\x02"
    original_crc = struct.unpack_from("<I", bad_crc, central + 16)[0]
    assert original_crc == zlib.crc32(valid) & 0xFFFFFFFF
    struct.pack_into("<I", bad_crc, central + 16, original_crc ^ 1)
    assert bad_crc[:central] == static[:central], "Bad-CRC fixture changed local data"
    fixtures = {
        "static.zip": static,
        "live.zip": archive_bytes([
            (f"frame{index:02d}.png", data) for index, data in enumerate(live_frames, start=1)
        ], deflated=True),
        "livePartial.zip": archive_bytes([
            (f"frame{index:02d}.png", data if index < 17 else invalid)
            for index, data in enumerate(live_frames, start=1)
        ], deflated=True),
        "missing.zip": archive_bytes([("frame02.png", valid)]),
        "invalidImage.zip": archive_bytes([("frame01.png", invalid)]),
        "wrongWidth.zip": archive_bytes([("frame01.png", wrong_width)]),
        "badCRC.zip": bytes(bad_crc),
        "valid.png": valid,
        "invalid.bin": invalid,
        "invalid.zip": b"Eagle fixture: not a ZIP archive",
    }
    fixtures.update({
        f"live-frame{index:02d}.png": data for index, data in enumerate(live_frames, start=1)
    })
    for name, data in fixtures.items():
        path = root / name
        assert path.parent == root, "Fixture escaped its temporary directory"
        path.write_bytes(data)
    return len(fixtures)


def run(command, *, cwd=None):
    try:
        return subprocess.run(
            command, cwd=cwd, check=True, timeout=55, capture_output=True, text=True,
        )
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout[-8000:].rstrip(), file=sys.stderr)
        if error.stderr:
            print(error.stderr[-8000:].rstrip(), file=sys.stderr)
        raise


def select_runtime(version, architecture):
    runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "-j"]).stdout)["runtimes"]
    runtime = next((value for value in runtimes if value["isAvailable"]
                    and value["name"].startswith("iOS ")
                    and value["version"] == version), None)
    if runtime is None:
        raise RuntimeError(f"Available iOS Simulator runtime {version} required")
    if architecture not in runtime["supportedArchitectures"]:
        raise RuntimeError(f"Runtime does not support host architecture {architecture}")
    device_type = next((value["identifier"] for value in runtime["supportedDeviceTypes"]
                        if value["productFamily"] == "iPhone"), None)
    if device_type is None:
        raise RuntimeError("The selected runtime has no supported iPhone simulator")
    return runtime, device_type


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-version", default="26.5")
    parser.add_argument(
        "--compile-only", action="store_true",
        help="Compile the isolated integration binary without creating a simulator",
    )
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    view_path = "lara/views/new/DockGalleryView.swift"
    public = run(["git", "show", f"{PUBLIC_COMMIT}:{view_path}"], cwd=repo).stdout
    generated = generated_stores(public)
    runner = repo / "scripts/verify_eagle_dock_store_pipeline.swift"
    assert runner.is_file(), "The bounded Gallery store pipeline runner is required"
    core_sources = [repo / path for path in APP_CORE_RELATIVE_PATHS]
    adapter_sources = [repo / path for path in APP_ADAPTER_RELATIVE_PATHS]
    assert len(core_sources) == 76 and len(adapter_sources) == 24
    adapter_sources.append(repo / "lara/views/new/EaglePressableStyle.swift")
    assert APP_ADAPTER_RELATIVE_PATHS.count(PACKAGE_PREPARER_PATH) == 1
    assert APP_ADAPTER_RELATIVE_PATHS.count(PACKAGE_CACHE_PATH) == 1
    assert APP_ADAPTER_RELATIVE_PATHS.count(PACKAGE_PREPARATION_PATH) == 1
    assert APP_ADAPTER_RELATIVE_PATHS.count(OWNED_STORE_PATH) == 1
    assert all(path.is_file() for path in core_sources + adapter_sources)
    owned_store = (repo / OWNED_STORE_PATH).read_text()
    assert all(value not in owned_store for value in (
        "RemoteCall", "laramgr", "DockGalleryExecutor", "DarkSword", "LaraL10n",
        "CurrentArchiveDiagnostics", "URLSession", "FileManager", "UIKit", "SwiftUI",
    )), "The exact owned Store gained a native/UI/I/O dependency"
    assert owned_store.count("@MainActor\nfinal class EagleDockGalleryStore:") == 1
    assert "final class EagleDockGalleryStore:" not in generated
    architecture = platform.machine()
    assert architecture in ("arm64", "x86_64"), "Unsupported simulator host architecture"
    sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).stdout.strip()
    flags = [
        "-swift-version", "5", "-default-isolation", "MainActor",
        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
        "-target", f"{architecture}-apple-ios16.0-simulator", "-sdk", sdk,
    ]
    with tempfile.TemporaryDirectory(prefix="eagle-dock-store-pipeline-") as directory:
        work = Path(directory).resolve()
        stores = work / "ExactDockGalleryStores.swift"
        stores.write_text(generated)
        preparer = work / "FixtureDockGalleryPackagePreparer.swift"
        preparer.write_text(fixture_package_preparer((repo / PACKAGE_PREPARER_PATH).read_text()))
        fixture_adapter_sources = [
            preparer if path == repo / PACKAGE_PREPARER_PATH else path for path in adapter_sources
        ]
        assert fixture_adapter_sources.count(preparer) == 1
        assert fixture_adapter_sources.count(repo / OWNED_STORE_PATH) == 1, "Compile the unmodified owned Store exactly once"
        fixture_count = write_fixtures(work)
        binary = work / "verify-dock-store-pipeline"
        run([
            "xcrun", "--sdk", "iphonesimulator", "swiftc", *flags,
            *map(str, core_sources), *map(str, fixture_adapter_sources),
            str(stores), str(runner), "-o", str(binary),
        ])
        print(
            f"PASS: counted public fixture seams and unmodified owned Store, {len(core_sources)} benign Core files "
            f"and {len(adapter_sources)} adapters compile; {fixture_count} local fixtures; "
            "FileManager seams: public Store 3, production Store 0, production preparer 1",
            flush=True,
        )
        if args.compile_only:
            return
        runtime, device_type = select_runtime(args.runtime_version, architecture)
        device = None
        try:
            created = run([
                "xcrun", "simctl", "create", f"Eagle-Dock-Store-QA-{uuid.uuid4().hex[:8]}",
                device_type, runtime["identifier"],
            ]).stdout.strip()
            device = str(uuid.UUID(created)).upper()
            print(f"Temporary iOS {runtime['version']} Simulator: {device}", flush=True)
            run(["xcrun", "simctl", "boot", device])
            for attempt in range(3):
                try:
                    run(["xcrun", "simctl", "bootstatus", device, "-b"])
                    break
                except subprocess.TimeoutExpired:
                    if attempt == 2:
                        raise
                    print("Temporary simulator is still booting; waiting for readiness", flush=True)
            result = run(["xcrun", "simctl", "spawn", device, str(binary), str(work)])
            if result.stdout.strip():
                print(result.stdout.strip(), flush=True)
        finally:
            if device is not None:
                # Both lifecycle operations target only this invocation's new UUID.
                try:
                    subprocess.run(
                        ["xcrun", "simctl", "shutdown", device], check=False,
                        timeout=55, capture_output=True, text=True,
                    )
                finally:
                    run(["xcrun", "simctl", "delete", device])
                    print(f"Removed temporary Simulator: {device}", flush=True)


if __name__ == "__main__":
    main()
