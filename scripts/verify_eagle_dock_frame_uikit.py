#!/usr/bin/env python3
"""Run exact Dock frame adapters with UIKit in a disposable iOS Simulator."""
from pathlib import Path
import argparse
import json
import platform
import re
import subprocess
import tempfile
import textwrap
import uuid


def declaration(source, marker):
    assert source.count(marker) == 1, f"Expected exactly one declaration: {marker}"
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def compact(source):
    return re.sub(r"\s+", "", source)


def body(source, marker):
    value = declaration(source, marker)
    return value[value.index("{") + 1:-1]


def public_parts(source):
    # Include only the image guard, cache check and supported-format predicate.
    # The app, network/package orchestration and applying executor are excluded.
    start = source.index("                guard let image = UIImage(data: frameData),")
    write_marker = "                try frameData.write("
    assert source.count(write_marker) == 1, "Frame-write boundary changed"
    end = source.index(write_marker, start)
    guard = textwrap.dedent(source[start:end]).rstrip()
    cache = declaration(source, "private static func validFrames(in directory:")
    cache = cache.replace("private static func", "static func", 1)
    support = declaration(source, "private static func isSupported(_ theme:")
    support = support.replace("private static func", "static func", 1)
    expression_start = cache.index("            return ")
    expression_end = cache.index("\n        }", expression_start)
    image_expression = textwrap.dedent(cache[expression_start:expression_end])
    return guard, cache, support, image_expression


def public_adapter(parts):
    guard, cache, support, image_expression = parts
    return f"""@MainActor
enum PublicDockFrameAdapter {{
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    static func validate(_ frameData: Data, theme: RemoteDockGalleryTheme) throws {{
{textwrap.indent(guard, '        ')}
    }}
    static func dimensions(_ image: UIImage, theme: RemoteDockGalleryTheme) -> Bool {{
{textwrap.indent(image_expression, '        ')}
    }}
    {support}
    {cache}
}}
"""


def production_adapter(source, store_source, package_preparation_source, package_preparer_source, package_cache_source):
    from verify_eagle_gallery_services import verify_sources as verify_gallery_services
    verify_gallery_services(Path(__file__).resolve().parents[1])
    assert "class RemoteDockGalleryStore:" not in source, "The Gallery screen must no longer declare its Store"
    store_prepare = declaration(store_source, "func prepare(_ theme: EagleDockGalleryTheme)")
    assert store_source.count("private let packagePreparation: EagleDockGalleryPackagePreparation") == 1
    assert store_source.count("packagePreparation: EagleDockGalleryPackagePreparation = EagleDockGalleryPackagePreparation()") == 1
    assert "packageCache" not in store_source, "The Store must no longer own its package-cache probe"
    assert "packageDownloader" not in store_source, "The Store must no longer own its package downloader"
    assert "cacheDirectoryService" not in store_source, "The Store must no longer own the cache-directory service"
    assert "private func cacheDirectory(" not in store_source, "The Store must no longer own cache location"
    assert "private static func validFrames(" not in store_source, "The Store must no longer own cached-frame validation"
    assert compact(store_prepare) == compact("""
        func prepare(_ theme: EagleDockGalleryTheme) async throws -> URL {
            return try await packagePreparation.prepare(
                theme,
                diagnostics: diagnostics,
                willDownload: { self.downloadingID = theme.id },
                didFinish: { self.downloadingID = nil }
            )
        }
    """), "The Store must delegate once with late diagnostics and its original download-state callbacks"
    assert store_source.count("packagePreparation.prepare(") == 1
    assert store_source.count("EagleDockGalleryPackagePreparer.prepare(") == 0
    assert "LaraL10n" not in store_source and "CurrentArchiveDiagnostics" not in store_source

    # Follow the actual async delegation boundary in source only. The complete
    # coordinator/download/package flow belongs to the separate pipeline harness;
    # this executable's allowlist remains limited to image/cache interpretation.
    coordination = declaration(package_preparation_source, "func prepare(")
    coordination_body = body(package_preparation_source, "func prepare(")
    download_state_marker = "willDownload()"
    assert coordination.count(download_state_marker) == 1, "Expected one start callback after a cache miss"
    assert compact(coordination_body[:coordination_body.index(download_state_marker)]) == compact("""
        let location = try cache.locate(theme)
        let destination = location.directory
        if location.isValid { return destination }
    """), "The coordinator must locate and validate cache before the first callback"
    download_marker = "let data = try await downloader.download(theme)"
    assert coordination.count(download_marker) == 1, "Expected one package download before preparation"
    after_start = coordination[coordination.index(download_state_marker):coordination.index(download_marker)]
    assert compact(after_start) == compact("""
        willDownload()
        defer { didFinish() }
    """), "The coordinator must restore download state after every post-start outcome"
    after_download = coordination[coordination.index(download_marker):]
    assert compact(after_download) == compact("""
        let data = try await downloader.download(theme)
        return try EagleDockGalleryPackagePreparer.prepare(
            data,
            theme: theme,
            destination: destination,
            log: diagnostics()
        )
    }"""), "The coordinator must request diagnostics only after download succeeds and then prepare directly"
    assert package_preparation_source.count("diagnostics()") == 1
    assert package_preparation_source.count("EagleDockGalleryPackagePreparer.prepare(") == 1

    # The real synchronous helper now owns this extraction/validation/write loop.
    # Compile only its exact image-validation call here; the integrated pipeline
    # separately exercises the complete package preparer and filesystem sequence.
    prepare = declaration(package_preparer_source, "static func prepare(")
    extract_marker = "let frameData = try archive.extract(entry)"
    validate_marker = "try EagleDockGalleryFrameImage.validate(frameData, theme: theme)"
    write_marker = "try EagleDockGalleryFrameWriter.write("
    assert prepare.count(extract_marker) == 1, "Frame-extraction boundary changed"
    assert store_source.count(validate_marker) == 0, "The Store must no longer own decoded-frame validation"
    assert package_preparer_source.count(validate_marker) == 1, "Expected one production frame-validation call"
    assert prepare.count(write_marker) == 1, "Frame-write boundary changed"
    start = prepare.index(extract_marker) + len(extract_marker)
    end = prepare.index(write_marker, start)
    validate = textwrap.dedent(prepare[start:end]).strip()
    assert compact(validate) == compact(validate_marker), "Validation must stay between extraction and write"
    support = declaration(store_source, "private static func isSupported(_ theme:")
    support = support.replace("private static func", "static func", 1)
    assert store_source.count("EagleDockGalleryFrameImage.isValid(data, theme: theme)") == 0
    assert compact(declaration(package_cache_source, "static func isValid(in directory: URL, theme: EagleDockGalleryTheme) -> Bool")) == compact("""static func isValid(in directory: URL, theme: EagleDockGalleryTheme) -> Bool {
        EagleDockGalleryCachedFrames.areValid(in: directory, theme: theme) { data, theme in
            EagleDockGalleryFrameImage.isValid(data, theme: theme)
        }
    }"""), "Production cached-frame callback changed"
    assert package_cache_source.count("EagleDockGalleryFrameImage.isValid(data, theme: theme)") == 1
    assert prepare.count("EagleDockGalleryPackageCache.isValid(in: staging, theme: theme)") == 1
    assert prepare.count("EagleDockGalleryCachedFrames.areValid(") == 0
    assert prepare.count("EagleDockGalleryFrameImage.isValid(") == 0
    assert compact("""guard EagleDockGalleryPackageCache.isValid(in: staging, theme: theme) else {
        throw URLError(.cannotDecodeContentData)
    }""") in compact(prepare), "Staging must retain the exact cached-frame predicate and decode error"
    cache = """static func validFrames(in directory: URL, theme: RemoteDockGalleryTheme) -> Bool {
        EagleDockGalleryPackageCache.isValid(in: directory, theme: theme)
    }"""
    return f"""@MainActor
enum ProductionDockFrameAdapter {{
    typealias RemoteDockGalleryTheme = EagleDockGalleryTheme
    static func validate(_ frameData: Data, theme: RemoteDockGalleryTheme) throws {{
        {validate}
    }}
    static func dimensions(_ image: UIImage, theme: RemoteDockGalleryTheme) -> Bool {{
        EagleDockGalleryFrameImage.matches(image, theme: theme)
    }}
    {support}
    {cache}
}}
"""


def verify_image_adapter(image_source, dimensions_source, parts):
    guard, cache, _, image_expression = parts
    # Map both exact public decode predicates onto the extracted UIKit methods.
    # The pure matcher retains the public && short circuit and independent reads.
    raw_dimensions = "image.cgImage?.width == theme.width && image.cgImage?.height == theme.height"
    assert compact(image_expression) == compact(f"return {raw_dimensions}")
    public_validate = compact(guard).replace("frameData", "data")
    raw_guard = compact("image.cgImage?.width == theme.width, image.cgImage?.height == theme.height")
    assert public_validate.count(raw_guard) == 1
    expected_validate = public_validate.replace(raw_guard, compact("matches(image, theme: theme)"))
    validate = declaration(image_source, "static func validate(_ data: Data, theme: EagleDockGalleryTheme) throws")
    assert compact(body(image_source, "static func validate(_ data: Data, theme: EagleDockGalleryTheme) throws")) == expected_validate

    cache_guard_start = cache.index("let image = UIImage(data: data)")
    cache_guard_end = cache.index("else { return false }", cache_guard_start) + len("else { return false }")
    cache_guard = cache[cache_guard_start:cache_guard_end]
    expected_is_valid = f"guard {cache_guard}\nreturn matches(image, theme: theme)"
    is_valid = declaration(image_source, "static func isValid(_ data: Data, theme: EagleDockGalleryTheme) -> Bool")
    assert compact(body(image_source, "static func isValid(_ data: Data, theme: EagleDockGalleryTheme) -> Bool")) == compact(expected_is_valid)

    matches = declaration(image_source, "static func matches(_ image: UIImage, theme: EagleDockGalleryTheme) -> Bool")
    assert compact(body(image_source, "static func matches(_ image: UIImage, theme: EagleDockGalleryTheme) -> Bool")) == compact("""
        EagleDockGalleryFrameDimensions.matches(
            width: image.cgImage?.width,
            height: image.cgImage?.height,
            expectedWidth: theme.width,
            expectedHeight: theme.height
        )
    """)
    pure_dimensions = raw_dimensions.replace("image.cgImage?.width", "width")
    pure_dimensions = pure_dimensions.replace("image.cgImage?.height", "height()")
    pure_dimensions = pure_dimensions.replace("theme.width", "expectedWidth").replace("theme.height", "expectedHeight()")
    assert compact(body(dimensions_source, "static func matches(")) == compact(pure_dimensions)

    code = re.sub(r"//[^\n]*", "", image_source)
    image_enum = declaration(code, "@MainActor\nenum EagleDockGalleryFrameImage")
    for method in (validate, is_valid, matches):
        image_enum = image_enum.replace(method, "", 1)
    assert compact(image_enum) == compact("@MainActor enum EagleDockGalleryFrameImage {}"), "Adapter must only contain synchronous image methods"
    imports = re.findall(r"(?m)^import (\w+)$", code)
    assert imports == ["Foundation", "UIKit"]
    outer = code.replace(declaration(code, "@MainActor\nenum EagleDockGalleryFrameImage"), "", 1)
    assert compact(outer.replace("import Foundation", "").replace("import UIKit", "")) == ""
    assert image_source.count("UIImage(data: data)") == 2
    assert image_source.count("UIImage(") == 2, "Use the default UIImage(data:) initialization only"
    assert not any(token in code for token in (
        "async", "await", "Task", "nonisolated", "FileManager", "URLSession", "Data(contentsOf:",
        "laramgr", "DockGalleryExecutor", "LaraL10n", "SwiftUI"
    )), "Image validation must remain synchronous on MainActor without I/O or the app manager"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-version", default="26.5")
    parser.add_argument("--compile-only", action="store_true", help="Compile without creating or booting a Simulator")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    view_path = "lara/views/new/DockGalleryView.swift"
    current = (repo / view_path).read_text()
    public = subprocess.check_output([
        "git", "show", f"823ab22c60ac6289314577034085784b8fdc24a4:{view_path}"
    ], cwd=repo, text=True)
    image_path = repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryFrameImage.swift"
    package_preparer_path = repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparer.swift"
    package_preparation_path = repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparation.swift"
    package_cache_path = repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryPackageCache.swift"
    store_path = repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryStore.swift"
    dimensions_path = repo / "lara/EagleCore/DockGallery/EagleDockGalleryFrameDimensions.swift"
    parts = public_parts(public)
    verify_image_adapter(image_path.read_text(), dimensions_path.read_text(), parts)
    generated = "import Foundation\nimport UIKit\n" + public_adapter(parts)
    generated += production_adapter(current, store_path.read_text(), package_preparation_path.read_text(), package_preparer_path.read_text(), package_cache_path.read_text())
    assert generated.count("UIImage(data: frameData)") == 1
    assert generated.count("Data(contentsOf: url, options: .mappedIfSafe)") == 1
    assert generated.count("EagleDockGalleryCachedFrames.areValid(") == 0
    assert generated.count("EagleDockGalleryPackageCache.isValid(in: directory, theme: theme)") == 1
    assert generated.count("EagleDockGalleryFrameImage.validate(frameData, theme: theme)") == 1
    assert generated.count("EagleDockGalleryFrameImage.isValid(") == 0
    assert generated.count("EagleDockGalleryFrameImage.matches(image, theme: theme)") == 1
    assert "EagleDockGalleryFrameDimensions.matches(" not in generated
    print("PASS: new UIKit adapter retains the exact public decode predicates and synchronous image boundary", flush=True)

    architecture = platform.machine()
    if not args.compile_only:
        runtimes = json.loads(subprocess.check_output([
            "xcrun", "simctl", "list", "runtimes", "-j"
        ], text=True))["runtimes"]
        runtime = next((value for value in runtimes if value["isAvailable"]
                        and value["name"].startswith("iOS ")
                        and value["version"] == args.runtime_version), None)
        if runtime is None:
            raise RuntimeError(f"Available iOS Simulator runtime {args.runtime_version} required")
        if architecture not in runtime["supportedArchitectures"]:
            raise RuntimeError(f"Runtime does not support host architecture {architecture}")
        device_type = next(value["identifier"] for value in runtime["supportedDeviceTypes"]
                           if value["productFamily"] == "iPhone")
    sdk = subprocess.check_output([
        "xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"
    ], text=True).strip()
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
             "-target", f"{architecture}-apple-ios16.0-simulator", "-sdk", sdk]
    device = None
    with tempfile.TemporaryDirectory(prefix="eagle-dock-frame-uikit-") as directory:
        work = Path(directory)
        adapters = work / "ExactDockFrameAdapters.swift"
        adapters.write_text(generated)
        binary = work / "verify-dock-frame-uikit"
        subprocess.run([
            "xcrun", "--sdk", "iphonesimulator", "swiftc", *flags,
            str(repo / "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift"),
            str(dimensions_path),
            str(repo / "lara/EagleCore/DockGallery/EagleDockGalleryCachedFrames.swift"),
            str(repo / "lara/EagleCore/DockGallery/EagleDockGalleryCacheDirectory.swift"),
            str(image_path),
            str(package_cache_path),
            str(adapters), str(repo / "scripts/verify_eagle_dock_frame_uikit.swift"),
            "-o", str(binary)
        ], check=True, timeout=55)
        print("PASS: exact production/public image guard and cache adapters compile with UIKit", flush=True)
        if args.compile_only:
            return
        try:
            created = subprocess.check_output([
                "xcrun", "simctl", "create", f"Eagle-Dock-Frame-QA-{uuid.uuid4().hex[:8]}",
                device_type, runtime["identifier"]
            ], text=True, timeout=30).strip()
            device = str(uuid.UUID(created)).upper()
            print(f"Temporary iOS {runtime['version']} Simulator: {device}", flush=True)
            subprocess.run(["xcrun", "simctl", "boot", device], check=True, timeout=45)
            for attempt in range(3):
                try:
                    subprocess.run([
                        "xcrun", "simctl", "bootstatus", device, "-b"
                    ], check=True, timeout=55)
                    break
                except subprocess.TimeoutExpired:
                    if attempt == 2:
                        raise
                    print("Temporary simulator is still booting; waiting for readiness", flush=True)
            subprocess.run([
                "xcrun", "simctl", "spawn", device, str(binary)
            ], check=True, timeout=55)
        finally:
            if device is not None:
                # These commands target only the UUID created by this invocation.
                try:
                    subprocess.run([
                        "xcrun", "simctl", "shutdown", device
                    ], check=False, timeout=30, capture_output=True, text=True)
                finally:
                    subprocess.run([
                        "xcrun", "simctl", "delete", device
                    ], check=True, timeout=30)
                    print(f"Removed temporary Simulator: {device}", flush=True)


if __name__ == "__main__":
    main()
