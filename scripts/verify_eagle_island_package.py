#!/usr/bin/env python3
"""Full Island package extraction parity, real UIKit/ZIP/files and fake transport."""
from pathlib import Path
import hashlib
import io
import json
import platform
import struct
import subprocess
import tempfile
import uuid
import zipfile
import zlib
from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
MEDIA = "lara/views/new/IslandLiveMedia.swift"
PACKAGE = "lara/EagleAdapters/IslandGallery/EagleIslandGalleryPackage.swift"
MODEL = "lara/EagleCore/IslandGallery/EagleIslandGalleryCatalog.swift"
ARCHIVE = "lara/EagleCore/Archives/EagleZIPArchive.swift"
HEADER = '''static func prepare(
        theme: EagleIslandGalleryTheme? = nil,
        fileManager: @escaping @Sendable () -> FileManager = { .default },
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        },
        downloadPackage: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse) = {
            try await URLSession.shared.download(for: $0)
        },
        log: @escaping @Sendable (String) -> Void
    ) async throws -> URL'''
PREFIX = '''import Foundation
import UIKit
import CryptoKit

/// Owns Island package preparation, verified frame caching and staged extraction.
/// Keeps the detached worker and forwards cancellation without changing native applying.
nonisolated enum EagleIslandGalleryPackage {
'''
BRIDGE = '''    static func prepare(theme: IslandLiveTheme? = nil) async throws -> URL {
        try await EagleIslandGalleryPackage.prepare(theme: theme, log: EagleAppDiagnostics.log)
    }'''


def original_block():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{MEDIA}"], cwd=repo, text=True)
    return public[public.index("    static func prepare("):public.rindex("\n}")]


def inline_package(media):
    return replace_once(media, BRIDGE, original_block())


def injected_block():
    value = original_block()
    for old, new in (
        ("static func prepare(theme: IslandLiveTheme? = nil) async throws -> URL", HEADER),
        ("let fm = FileManager.default", "let fm = fileManager()"),
        ("URLSession.shared.data(for: request)", "fetch(request)"),
        ("URLSession.shared.download(for: request)", "downloadPackage(request)"),
        ("ZipArchive(data: data)", "ZipArchive(data: data, log: log)"),
    ):
        value = replace_once(value, old, new)
    assert value.count("IslandLiveManifest") == 2
    return value.replace("IslandLiveManifest", "EagleIslandGalleryManifest")


def verify_texts(media, package):
    assert hashlib.sha256(inline_package(media).encode()).hexdigest() == "d2cb9a8b5defb58465e8bb0e4d397f108a861ea2e7196a6db6612e39bc1ee680", "Unrelated media/catalog edit"
    assert package == PREFIX + injected_block() + "\n}\n", "Package differs from complete public implementation"


def verify_sources(repo):
    media, package = [(repo / p).read_text() for p in (MEDIA, PACKAGE)]
    verify_texts(media, package)
    from verify_eagle_island_load_flow import inline_load_flow
    screen = inline_load_flow((repo / "lara/views/new/IslandGalleryPresentation.swift").read_text())
    assert hashlib.sha256(screen.encode()).hexdigest() == "de94ea7f78da18d4de3937196592fc6ef158b6b91f45ef7e67cee6fc6d637d38"
    cases = [
        (0, "theme: theme, log:", "theme: nil, log:"),
        (0, "log: EagleAppDiagnostics.log", "log: { _ in }"),
        (1, "Task.detached(priority: .userInitiated)", "Task(priority: .background)"),
        (1, "worker.cancel()", "// no cancellation"),
        (1, "request.timeoutInterval = 20", "request.timeoutInterval = 25"),
        (1, "request.timeoutInterval = 90", "request.timeoutInterval = 20"),
        (1, "data.count <= 32 * 1024", "data.count < 32 * 1024"),
        (1, "manifest.id == themeID", "true"),
        (1, "size == manifest.byteCount", "size != nil"),
        (1, "digest(data) == manifest.sha256", "true"),
        (1, "entries.count == 17", "entries.count > 0"),
        (1, "Set(entries.map(\\.path)) == expected", "true"),
        (1, "!$0.isDirectory", "true"),
        (1, "$0.uncompressedSize > 0", "$0.uncompressedSize >= 0"),
        (1, "guard validFrames(in: staging, manifest: manifest)", "guard true"),
        (1, "digest(data) == manifest.frameSHA256[index - 1]", "true"),
        (1, "image.width == 1200 && image.height == 500", "image.width > 0"),
        (1, "log: log)", "log: { _ in })"),
        (1, "defer { try? fm.removeItem(at: download) }", "// no cleanup"),
        (1, "defer { try? fm.removeItem(at: staging) }", "// no cleanup"),
        (1, "try manifestData.write(to: savedManifest, options: .atomic)", "// not saved"),
    ]
    for index, old, new in cases:
        values = [media, package]; values[index] = replace_once(values[index], old, new)
        try:
            verify_texts(*values)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted regression: {old}")
    print(f"PASS: full public worker/hash/frame bodies, default ports and diagnostic bridge; {len(cases)} rejected mutations", flush=True)


def png(width, height):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress((b"\0" + b"\x20\x80\xff\xff" * width) * height)) + chunk(b"IEND", b"")


def fixtures(root):
    from verify_eagle_island_catalog import theme
    good = png(1200, 500)
    variants = ["valid", "deflated", "missing", "extra", "path", "directory", "empty", "huge", "badpng", "dimensions", "framehash", "badzip"]
    for variant in variants:
        directory = root / variant; directory.mkdir()
        frames = [good] * 17
        if variant == "badpng": frames[8] = b"not a PNG"
        if variant == "dimensions": frames[8] = png(1199, 500)
        entries = [(f"frame{i+1:02d}.png", frame) for i, frame in enumerate(frames)]
        if variant == "missing": entries.pop()
        if variant == "extra": entries.append(("extra.png", good))
        if variant == "path": entries[0] = ("../frame01.png", good)
        if variant == "directory": entries[0] = ("frame01.png/", b"")
        if variant == "empty": entries[0] = ("frame01.png", b"")
        if variant == "huge": entries[0] = ("frame01.png", b"x" * (2 * 1024 * 1024 + 1))
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED if variant in ("deflated", "huge") else zipfile.ZIP_STORED) as archive:
            for name, data in entries: archive.writestr(name, data)
        package = b"not a zip archive" if variant == "badzip" else buffer.getvalue()
        value = theme()
        value.update(byteCount=len(package), sha256=hashlib.sha256(package).hexdigest(),
                     frameSHA256=[hashlib.sha256(frame).hexdigest() for frame in frames])
        if variant == "framehash": value["frameSHA256"][8] = "b" * 64
        (directory / "theme.json").write_text(json.dumps(value))
        (directory / "manifest.json").write_text(json.dumps({k: v for k, v in value.items() if k not in ["title", "titleES", "accent", "previewURL", "posterURL"]}))
        (directory / "package.zip").write_bytes(package)
        cached = directory / "frames"; cached.mkdir()
        for index, frame in enumerate(frames): (cached / f"frame{index+1:02d}.png").write_bytes(frame)
    return variants


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"], text=True))["runtimes"]
    runtime = next(r for r in runtimes if r["isAvailable"] and r["name"].startswith("iOS ") and platform.machine() in r["supportedArchitectures"])
    device_type = next(d["identifier"] for d in runtime["supportedDeviceTypes"] if d["productFamily"] == "iPhone")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="eagle-island-package-") as directory:
        work = Path(directory)
        fixtures(work)
        source = work / "Reference.swift"
        source.write_text("import Foundation\nimport UIKit\nimport CryptoKit\nnonisolated enum PublicPackage {\n" + injected_block() + "\n}\n")
        binary = work / "verify"
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                        "-target", f"{platform.machine()}-apple-ios16.0-simulator", "-sdk", sdk,
                        str(repo / MODEL), str(repo / ARCHIVE), str(repo / PACKAGE), str(source),
                        str(repo / "scripts/verify_eagle_island_package.swift"), "-o", str(binary)], check=True, timeout=55)
        print("PASS: actual owned/public package pipeline compiles with UIKit, CryptoKit and owned ZIP implementation", flush=True)
        device = None
        try:
            device = str(uuid.UUID(subprocess.check_output(["xcrun", "simctl", "create", f"Eagle-Island-Package-QA-{uuid.uuid4().hex[:8]}", device_type, runtime["identifier"]], text=True, timeout=30).strip())).upper()
            print(f"Temporary iOS {runtime['version']} Simulator: {device}", flush=True)
            subprocess.run(["xcrun", "simctl", "boot", device], check=True, timeout=45)
            for attempt in range(3):
                try:
                    subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, timeout=55)
                    break
                except subprocess.TimeoutExpired:
                    if attempt == 2: raise
            subprocess.run(["xcrun", "simctl", "spawn", device, str(binary), str(work)], check=True, timeout=55)
        finally:
            if device:
                subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, capture_output=True, timeout=30)
                subprocess.run(["xcrun", "simctl", "delete", device], check=True, timeout=30)
                print(f"Removed temporary simulator: {device}", flush=True)


if __name__ == "__main__":
    main()
