#!/usr/bin/env python3
"""Build the separate, offline Eagle interface preview, never the original app.

Only an explicit Swift/source/asset allowlist is used. There is no Xcode project,
bridging header, native engine, entitlements, provisioning profile or private key.
An IPA from this script is not distribution signed and requires external signing.
Importing this module does not build, generate resources or write files.
"""
from __future__ import annotations

import argparse
import colorsys
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib

from verify_eagle_core_project_membership import APP_CORE_RELATIVE_PATHS, APP_ADAPTER_RELATIVE_PATHS


NAME = "EagleInterfacePreview"
BUNDLE_ID = "com.leonardobaptiste.eagle.interfacepreview"
PREVIEW_ROOT = "preview/EagleInterfacePreview"
NEW_SOURCES = (f"{PREVIEW_ROOT}/PreviewModel.swift", f"{PREVIEW_ROOT}/PreviewApp.swift")
NOTIFICATION_SOURCES = (
    "lara/views/new/EagleDynamicNotification.swift",
    "lara/views/new/EagleNotificationMorph.swift",
)
RAINBOW_ORIGINAL = "lara/views/new/EagleRainbowLoadingView.swift"
RAINBOW_GENERATED = f"{PREVIEW_ROOT}/GeneratedRainbowComponents.swift"
RAINBOW_MARKERS = (
    "struct EagleRainbowSpinner: View {",
    "struct EagleRainbowProgressBar: View {",
    "private func eagleRainbowPhase(at date: Date, duration: TimeInterval) -> Double {",
)
ASSET_ROOT = "lara/other/media.xcassets"
ASSET_SETS = (
    "AppIcon.appiconset", "EagleBrandMark.imageset", "DockGalleryBubblegum.imageset",
    "PhotoAuraSky.imageset", "PhotoAuraVortex.imageset", "PhotoAuraRainbow.imageset",
    "PhotoAuraTraffic.imageset",
)
LICENSE_SOURCES = ("LICENSE", "lara/licenses/NOTICE_Dynamic_Notifications.txt")
DENIED_SOURCE = re.compile(
    r"\b(?:laramgr|RemoteCall|DarkSword|darksword|grabkernel|libgrabkernel|libxpf|"
    r"sandbox_extension_consume|sandbox_extension_issue_file|task_for_pid|mach_vm_write|"
    r"mach_vm_read|kernel_base|kernel_slide|dlsym|dlopen|SpringBoard)\b", re.IGNORECASE
)
DENIED_SYMBOL = re.compile(
    r"laramgr|RemoteCall|DarkSword|darksword|grabkernel|libxpf|sandbox_extension_|"
    r"task_for_pid|mach_vm_(?:write|read)|kernel_base|kernel_slide", re.IGNORECASE
)
WIDTH, HEIGHT = 1146, 318


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_file(repo: Path, relative: str) -> Path:
    parts = PurePosixPath(relative).parts
    if not parts or relative.startswith("/") or any(part in (".", "..") for part in parts):
        raise ValueError(f"Unsafe input path: {relative}")
    current = repo
    for part in parts:
        current /= part
        if current.is_symlink():
            raise ValueError(f"Symbolic-link input is not allowed: {relative}")
    if not current.is_file() or not current.resolve().is_relative_to(repo):
        raise ValueError(f"Missing or external input: {relative}")
    return current


def run(command: list[str], *, timeout: int = 55) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout[-12000:], file=sys.stderr)
        if error.stderr:
            print(error.stderr[-12000:], file=sys.stderr)
        raise


def extract_declaration(source: str, marker: str) -> str:
    if source.count(marker) != 1:
        raise ValueError(f"Rainbow declaration boundary changed: {marker}")
    start = source.index(marker)
    position = source.index("{", start) + 1
    depth = 1
    while depth:
        if position >= len(source):
            raise ValueError("Unbalanced rainbow declaration")
        depth += (source[position] == "{") - (source[position] == "}")
        position += 1
    return source[start:position]


def rainbow_source(repo: Path) -> tuple[str, dict]:
    original = repo / RAINBOW_ORIGINAL
    if original.exists():
        original_data = safe_file(repo, RAINBOW_ORIGINAL).read_bytes()
        text = original_data.decode()
        declarations = [extract_declaration(text, marker) for marker in RAINBOW_MARKERS]
        generated = "import SwiftUI\n\n" + "\n\n".join(declarations) + "\n"
        origin = {"path": RAINBOW_ORIGINAL, "sha256": sha(original_data), "compiled": False}
    else:
        # The corresponding-source archive contains the extracted, safe file,
        # not the original mixed UI/access-manager source.
        generated = safe_file(repo, RAINBOW_GENERATED).read_text()
        expected = "import SwiftUI\n\n" + "\n\n".join(
            extract_declaration(generated, marker) for marker in RAINBOW_MARKERS
        ) + "\n"
        if generated != expected:
            raise ValueError("Standalone rainbow source contains extra declarations")
        origin = {"path": RAINBOW_GENERATED, "sha256": sha(generated.encode()), "compiled": True}
    if DENIED_SOURCE.search(generated):
        raise ValueError("Extracted rainbow source gained a forbidden dependency")
    return generated, origin


def validate_sources(repo: Path) -> tuple[list[Path], list[dict], str, dict]:
    if len(APP_CORE_RELATIVE_PATHS) != 17 or len(APP_ADAPTER_RELATIVE_PATHS) != 5:
        raise ValueError("Preview requires the reviewed 17 Core + 5 adapter registry")
    relatives = (*APP_CORE_RELATIVE_PATHS, *APP_ADAPTER_RELATIVE_PATHS,
                 *NOTIFICATION_SOURCES, *NEW_SOURCES)
    if len(relatives) != len(set(relatives)) or len(relatives) != 26:
        raise ValueError("Preview Swift allowlist changed or contains duplicates")
    inputs, hashes = [], []
    for relative in relatives:
        path = safe_file(repo, relative)
        data = path.read_bytes()
        text = data.decode()
        if DENIED_SOURCE.search(text):
            raise ValueError(f"Forbidden source dependency in {relative}")
        if relative in NEW_SOURCES:
            if re.search(r"\b(?:URLSession|EagleDockGalleryCore|EagleDockGalleryPort)\b|"
                         r"\.applyRemote\s*\(|\b(?:NSClassFromString|performSelector)\b", text):
                raise ValueError(f"Preview source uses live transport, executor or runtime lookup: {relative}")
        inputs.append(path)
        hashes.append({"path": relative, "sha256": sha(data), "unchanged_input": True})
    generated, origin = rainbow_source(repo)
    hashes.append({"path": RAINBOW_GENERATED, "sha256": sha(generated.encode()),
                   "unchanged_input": False, "extracted_declarations": list(RAINBOW_MARKERS)})
    return inputs, hashes, generated, origin


def verify_input_hashes(repo: Path, entries: list[dict]) -> None:
    for entry in entries:
        if sha(safe_file(repo, entry["path"]).read_bytes()) != entry["sha256"]:
            raise ValueError(f"Input changed during compilation: {entry['path']}")


def png_dimensions(data: bytes) -> tuple[int, int]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or data[12:16] != b"IHDR":
        raise ValueError("Expected PNG artwork")
    return struct.unpack_from(">II", data, 16)


def png_frame(index: int) -> bytes:
    phase = index / 17
    angle = 2 * math.pi * phase
    columns = [x / WIDTH for x in range(WIDTH)]
    wave = [0.075 * math.sin(x * math.pi * 4 - angle) for x in columns]
    rows = bytearray()
    for y in range(HEIGHT):
        rows.append(0)
        drift = 0.055 * math.sin(y / HEIGHT * math.pi * 3 + angle)
        for x, location in enumerate(columns):
            hue = (0.48 + location + phase + wave[x] + drift) % 1
            red, green, blue = colorsys.hsv_to_rgb(hue, 0.96, 1.0)
            rows.extend((int(red * 255), int(green * 255), int(blue * 255)))

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(
            ">I", zlib.crc32(kind + payload) & 0xffffffff
        )

    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)) + \
        chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def zip_bytes(entries: list[tuple[str, bytes]]) -> bytes:
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, data in entries:
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    return result.getvalue()


def generate_resources(repo: Path, app: Path) -> tuple[list[str], list[dict]]:
    # Resources at the bundle root is a legacy layout marker for Foundation;
    # it makes the root Info.plist invisible. Keep fixtures in a distinct folder.
    resources = app / "PreviewResources"
    (resources / "packages").mkdir(parents=True)
    (resources / "previews").mkdir()
    bubblegum = safe_file(repo, f"{ASSET_ROOT}/DockGalleryBubblegum.imageset/DockGalleryBubblegum.png").read_bytes()
    if png_dimensions(bubblegum) != (WIDTH, HEIGHT):
        raise ValueError("Original Bubblegum PNG no longer matches public dimensions")
    animated = [png_frame(index) for index in range(17)]
    if len(set(map(sha, animated))) != 17:
        raise ValueError("Live preview frames must be distinct")
    themes, members = [], []
    for identifier, title, title_es, subtitle, subtitle_es, accent, frames, fps in (
        ("bubblegum-preview", "Bubblegum", "Chicle", "Original Eagle artwork", "Arte original de Eagle", "#FF2D9E", [bubblegum], 1),
        ("spectrum-preview", "Spectrum Flow", "Flujo espectral", "Vivid seamless 17-frame loop", "Bucle intenso y fluido de 17 fotogramas", "#00BDFF", animated, 6),
    ):
        entries = [(f"frame{index:02d}.png", frame) for index, frame in enumerate(frames, 1)]
        package = zip_bytes(entries)
        if not 0 < len(package) <= 30 * 1024 * 1024:
            raise ValueError("Generated preview package exceeds supported size")
        package_path = resources / "packages" / f"{identifier}.zip"
        package_path.write_bytes(package)
        (resources / "previews" / f"{identifier}.png").write_bytes(frames[0])
        theme = {
            "id": identifier, "version": 1, "title": title, "titleES": title_es,
            "subtitle": subtitle, "subtitleES": subtitle_es, "accent": accent,
            "previewURL": f"https://preview.invalid/previews/{identifier}.png",
            "packageURL": f"https://preview.invalid/packages/{identifier}.zip",
            "sha256": sha(package), "byteCount": len(package), "frameCount": len(frames),
            "fps": fps, "width": WIDTH, "height": HEIGHT,
        }
        themes.append(theme)
        with zipfile.ZipFile(io.BytesIO(package)) as archive:
            if archive.namelist() != [name for name, _ in entries] or archive.testzip() is not None:
                raise ValueError("Generated ZIP member/CRC validation failed")
            if any(png_dimensions(archive.read(name)) != (WIDTH, HEIGHT) for name, _ in entries):
                raise ValueError("Generated frame dimensions changed")
        members.append({"id": identifier, "sha256": sha(package), "byte_count": len(package),
                        "frames": [name for name, _ in entries], "fps": fps})
    (resources / "catalog.json").write_text(json.dumps({"schemaVersion": 1, "themes": themes}, ensure_ascii=False, indent=2) + "\n")
    licenses = resources / "Licenses"
    licenses.mkdir()
    for source in LICENSE_SOURCES:
        target = "LICENSE.txt" if source == "LICENSE" else Path(source).name
        shutil.copyfile(safe_file(repo, source), licenses / target)
    return [str(path.relative_to(app)) for path in resources.rglob("*") if path.is_file()], members


def copy_assets(repo: Path, work: Path) -> tuple[Path, list[str]]:
    catalog = work / "PreviewAssets.xcassets"
    catalog.mkdir()
    (catalog / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
    copied = []
    for asset in ASSET_SETS:
        relative = f"{ASSET_ROOT}/{asset}"
        description = safe_file(repo, f"{relative}/Contents.json")
        metadata = json.loads(description.read_text())
        names = {"Contents.json", *(image["filename"] for image in metadata["images"] if "filename" in image)}
        directory = repo / relative
        if {path.name for path in directory.iterdir()} != names or any(Path(name).name != name for name in names):
            raise ValueError(f"Asset directory contains unapproved files: {asset}")
        destination = catalog / asset
        destination.mkdir()
        for name in sorted(names):
            item = f"{relative}/{name}"
            shutil.copyfile(safe_file(repo, item), destination / name)
            copied.append(item)
    return catalog, copied


def audit_binary(binary: Path, selected_platform: str, architecture: str) -> dict:
    data = binary.read_bytes()
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xfeedfacf:
        raise ValueError("Preview executable must be a thin 64-bit Mach-O")
    _, cpu, _, filetype, count, _, _, _ = struct.unpack_from("<8I", data)
    expected_cpu = 0x0100000c if architecture == "arm64" else 0x01000007
    if cpu != expected_cpu or filetype != 2:
        raise ValueError("Preview executable architecture or file type changed")
    offset, platforms = 32, []
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x32:
            platforms.append(struct.unpack_from("<I", data, offset + 8)[0])
        offset += size
    if platforms != [2 if selected_platform == "device" else 7]:
        raise ValueError(f"Unexpected Mach-O build platform: {platforms}")
    symbols = run(["xcrun", "nm", str(binary)]).stdout
    if DENIED_SYMBOL.search(symbols):
        raise ValueError("Preview binary contains a forbidden native-engine symbol")
    linked = run(["xcrun", "otool", "-L", str(binary)]).stdout.splitlines()[1:]
    libraries = [line.strip().split(" (", 1)[0] for line in linked]
    for library in libraries:
        if not (library.startswith("/System/Library/Frameworks/") or library.startswith("/usr/lib/") or
                re.fullmatch(r"@rpath/libswift[A-Za-z0-9_]+\.dylib", library)):
            raise ValueError(f"Non-system dependency: {library}")
    signing = subprocess.run(
        ["/usr/bin/codesign", "--display", "--verbose=4", "--entitlements", ":-", str(binary)],
        check=False, capture_output=True, text=True, timeout=55,
    )
    if signing.returncode == 0 and "Signature=adhoc" in signing.stderr and "Authority=" not in signing.stderr:
        signature_state = "ad-hoc executable signature; no distribution identity"
        if signing.stdout.strip() and plistlib.loads(signing.stdout.encode()):
            raise ValueError("Preview executable unexpectedly carries entitlements")
    elif signing.returncode != 0 and "not signed at all" in signing.stderr:
        signature_state = "unsigned executable"
    else:
        raise ValueError("Preview signing state is neither unsigned nor ad-hoc without identity")
    return {"format": "Mach-O 64-bit executable", "architecture": architecture,
            "platform": selected_platform, "native_engine_symbol_audit": "passed",
            "system_libraries": libraries, "signature_state": signature_state,
            "entitlements": "none", "sha256": sha(data)}


def audit_bundle(app: Path, resource_paths: list[str]) -> list[dict]:
    if any((app / name).exists() for name in ("Resources", "Contents", "Versions")):
        raise ValueError("Reserved legacy bundle layout directory in flat iOS app")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != NAME:
        raise ValueError("Preview bundle identity changed")
    files = []
    allowed_roots = {NAME, "Info.plist", "Assets.car"}
    for path in sorted(app.rglob("*")):
        if path.is_symlink():
            raise ValueError("Preview bundle may not contain symbolic links")
        if path.is_dir():
            continue
        relative = str(path.relative_to(app))
        approved = relative in allowed_roots or relative in resource_paths or \
            bool(re.fullmatch(r"AppIcon[A-Za-z0-9@~.-]*\.png", relative))
        if not approved or path.suffix in (".dylib", ".framework", ".mobileprovision"):
            raise ValueError(f"Unexpected preview bundle member: {relative}")
        files.append({"path": relative, "byte_count": path.stat().st_size, "sha256": sha(path.read_bytes())})
    if not any(item["path"] == "Assets.car" for item in files):
        raise ValueError("Compiled allowlisted asset catalog missing")
    if not set(resource_paths).issubset({item["path"] for item in files}):
        raise ValueError("An expected offline resource is missing")
    return files


def sources_archive(repo: Path, work: Path, hashes: list[dict], generated: str,
                    assets: list[str], app: Path) -> Path:
    destination = work / "Sources.zip"
    inputs = [item["path"] for item in hashes if item["unchanged_input"]]
    inputs += ["scripts/build_eagle_interface_preview.py", "scripts/verify_eagle_core_project_membership.py",
               f"{PREVIEW_ROOT}/README.md", *LICENSE_SOURCES, *assets]
    inputs = sorted(set(inputs))
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative in inputs:
            archive.writestr(relative, safe_file(repo, relative).read_bytes())
        archive.writestr(RAINBOW_GENERATED, generated)
        for path in sorted((app / "PreviewResources").rglob("*")):
            if path.is_file():
                archive.writestr(f"{PREVIEW_ROOT}/{path.relative_to(app)}", path.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(set(archive.namelist())):
            raise ValueError("Corresponding-source archive validation failed")
        if RAINBOW_ORIGINAL in archive.namelist() or any(name.endswith((".c", ".h", ".m", ".dylib")) for name in archive.namelist()):
            raise ValueError("Corresponding-source archive contains forbidden inputs")
    return destination


def build(args: argparse.Namespace) -> None:
    repo = Path(__file__).resolve().parents[1]
    inputs, hashes, generated, origin = validate_sources(repo)
    output = Path(args.output)
    if not output.is_absolute() or output.is_symlink():
        raise ValueError("--output must be an absolute, nonsymlink directory")
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    products = [output / f"{NAME}.app", output / "Sources.zip", output / "PreviewBuildManifest.json"]
    if args.platform == "device" and not (args.compile_only or args.no_package):
        products.append(output / f"{NAME}-0.1.0-1.ipa")
    if not args.compile_only and any(path.exists() for path in products):
        raise ValueError("Output artifacts already exist; choose a fresh output directory")
    sdk_name = "iphoneos" if args.platform == "device" else "iphonesimulator"
    architecture = "arm64" if args.platform == "device" else platform.machine()
    if architecture not in ("arm64", "x86_64"):
        raise ValueError("Unsupported host architecture")
    sdk = run(["xcrun", "--sdk", sdk_name, "--show-sdk-path"]).stdout.strip()
    sdk_version = run(["xcrun", "--sdk", sdk_name, "--show-sdk-version"]).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="eagle-interface-preview-") as temporary:
        work = Path(temporary)
        app = work / f"{NAME}.app"
        app.mkdir()
        generated_path = work / "GeneratedRainbowComponents.swift"
        generated_path.write_text(generated)
        catalog, asset_inputs = copy_assets(repo, work)
        asset_input_hashes = [{
            "path": relative,
            "sha256": sha((catalog / PurePosixPath(relative).relative_to(ASSET_ROOT)).read_bytes()),
        } for relative in asset_inputs]
        resource_paths, package_manifest = generate_resources(repo, app)
        partial_info = work / "AssetInfo.plist"
        run(["xcrun", "--sdk", sdk_name, "actool", str(catalog), "--compile", str(app),
             "--platform", sdk_name, "--minimum-deployment-target", "16.0", "--app-icon", "AppIcon",
             "--target-device", "iphone", "--output-partial-info-plist", str(partial_info),
             "--output-format", "human-readable-text"])
        info = {
            "CFBundleInfoDictionaryVersion": "6.0", "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": BUNDLE_ID, "CFBundleName": NAME,
            "CFBundleDisplayName": "Eagle Preview", "CFBundleExecutable": NAME,
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1", "MinimumOSVersion": "16.0", "UIDeviceFamily": [1],
            "CFBundleSupportedPlatforms": ["iPhoneOS" if args.platform == "device" else "iPhoneSimulator"],
            "UILaunchScreen": {}, "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
            "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
            "LSRequiresIPhoneOS": True,
        }
        info.update(plistlib.loads(partial_info.read_bytes()))
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        target = f"{architecture}-apple-ios16.0" + ("-simulator" if args.platform == "simulator" else "")
        command = ["xcrun", "--sdk", sdk_name, "swiftc", "-swift-version", "5",
                   "-default-isolation", "MainActor", "-strict-concurrency=complete",
                   "-warnings-as-errors", "-parse-as-library", "-O", "-whole-module-optimization",
                   "-target", target, "-sdk", sdk, "-module-name", NAME,
                   "-module-cache-path", str(work / "ModuleCache"),
                   *map(str, inputs), str(generated_path), "-o", str(app / NAME)]
        print(f"Compiling only {len(hashes)} allowlisted Swift inputs for {args.platform}; no original app target", flush=True)
        run(command)
        binary_audit = audit_binary(app / NAME, args.platform, architecture)
        bundle_files = audit_bundle(app, resource_paths)
        full_source_hashes = [item for item in hashes if item["unchanged_input"]]
        verify_input_hashes(repo, [*full_source_hashes, *asset_input_hashes, origin])
        source_zip = sources_archive(repo, work, hashes, generated, asset_inputs, app)
        verify_input_hashes(repo, [*full_source_hashes, *asset_input_hashes, origin])
        with zipfile.ZipFile(source_zip) as archive:
            for entry in [*hashes, *asset_input_hashes]:
                if sha(archive.read(entry["path"])) != entry["sha256"]:
                    raise ValueError(f"Corresponding source does not match audited input: {entry['path']}")
        manifest = {
            "schema_version": 1, "name": NAME, "bundle_id": BUNDLE_ID, "version": "0.1.0", "build": "1",
            "scope": "Offline interface and local theme preview only; no privileged engine or system theme applying",
            "signing": "No distribution signing, provisioning profile, entitlements or private key; external signing required",
            "platform": args.platform, "sdk_version": sdk_version, "deployment_target": "16.0",
            "core_sources": 17, "adapter_sources": 5, "compiled_input_count": len(hashes),
            "sources": hashes, "rainbow_origin": origin, "asset_inputs": asset_inputs,
            "asset_input_hashes": asset_input_hashes,
            "resource_paths": sorted(resource_paths), "offline_packages": package_manifest,
            "binary_audit": binary_audit, "bundle_files": bundle_files,
            "corresponding_sources": {"filename": "Sources.zip", "sha256": sha(source_zip.read_bytes())},
            "excluded": ["original lara application target", "bridging headers", "C/native engine",
                         "privileged APIs", "live network requests (Preview uses injected bundle transport)",
                         "system theme applying", "distribution signing"],
        }
        if args.compile_only:
            print("PASS: isolated preview compilation, Mach-O/platform/native-symbol/dependency/resource/source audits; no exported app or IPA", flush=True)
            return
        ipa = None
        if args.platform == "device" and not args.no_package:
            ipa = work / f"{NAME}-0.1.0-1.ipa"
            with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
                for item in bundle_files:
                    path = app / item["path"]
                    archive.write(path, f"Payload/{app.name}/{item['path']}")
            with zipfile.ZipFile(ipa) as archive:
                expected = {f"Payload/{app.name}/{item['path']}" for item in bundle_files}
                if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected) or archive.testzip() is not None:
                    raise ValueError("IPA members differ from the audited standalone bundle")
            manifest["ipa"] = {"filename": ipa.name, "sha256": sha(ipa.read_bytes()), "byte_count": ipa.stat().st_size}
        manifest_file = work / "PreviewBuildManifest.json"
        manifest_file.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        shutil.copytree(app, output / app.name)
        shutil.copyfile(source_zip, output / source_zip.name)
        shutil.copyfile(manifest_file, output / manifest_file.name)
        if ipa is not None:
            shutil.copyfile(ipa, output / ipa.name)
        print(f"PASS: audited standalone preview exported to {output}", flush=True)
        if ipa is not None:
            print("IPA is not distribution signed; externally sign before installing. Public Eagle is unchanged.", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("simulator", "device"), default="device")
    parser.add_argument("--output", required=True, help="Absolute fresh output directory; existing artifacts are never overwritten")
    parser.add_argument("--compile-only", action="store_true", help="Compile and audit in temporary storage without exporting app or IPA")
    parser.add_argument("--no-package", action="store_true", help="Export app, manifest and corresponding sources without creating an IPA")
    args = parser.parse_args()
    try:
        build(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Standalone Eagle preview build failed: {error}\n")


if __name__ == "__main__":
    main()
