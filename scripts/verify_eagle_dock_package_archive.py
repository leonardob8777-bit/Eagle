#!/usr/bin/env python3
"""Check package opening and lazy extraction against the public Dock sequence."""
from io import BytesIO
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import warnings
import zipfile

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore"
package = core / "DockGallery/EagleDockGalleryPackageArchive.swift"
archive = core / "Archives/EagleZIPArchive.swift"
inventory = core / "DockGallery/EagleDockGalleryPackageInventory.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)
start = baseline.index("        let archive = try ZipArchive(data: data)")
end = baseline.index("\n\n        let fm = FileManager.default", start)
# ZIP algorithms are separately parity-tested; project only their injected sink.
opening = baseline[start:end].replace(
    "ZipArchive(data: data)", "ZipArchive(data: data, log: log)"
).replace("theme.frameCount", "frameCount")
extract = next(line.strip().removeprefix("let frameData = ")
               for line in baseline[end:].splitlines()
               if line.strip().startswith("let frameData = try archive.extract(entry)"))
reference = (
    "import Foundation\nnonisolated struct PublicDockPackageArchive {\n"
    "    private let archive: ZipArchive\n    let files: [ZipEntry]\n"
    "    init(data: Data, frameCount: Int, log: @escaping @Sendable (String) -> Void) throws {\n"
    + opening + "\n        self.archive = archive\n        self.files = files\n    }\n"
    "    func extract(_ entry: ZipEntry) throws -> Data {\n        " + extract + "\n    }\n}\n"
)
production = package.read_text()
expected = '''nonisolated struct EagleDockGalleryPackageArchive {
    private let archive: ZipArchive
    let files: [ZipEntry]

    init(data: Data, frameCount: Int, log: @escaping @Sendable (String) -> Void) throws {
        let archive = try ZipArchive(data: data, log: log)
        self.files = try EagleDockGalleryPackageInventory.frameFiles(
            in: archive.entries, frameCount: frameCount
        )
        self.archive = archive
    }

    func extract(_ entry: ZipEntry) throws -> Data {
        try archive.extract(entry)
    }
}'''
assert production[production.index("nonisolated struct "):].strip() == expected, "Package constructor or lazy forwarding changed"
assert [line for line in production.splitlines() if line.startswith("import ")] == ["import Foundation"]
assert all(name not in production for name in [
    "laramgr", "LaraL10n", "UIKit", "SwiftUI", "UIImage", "FileManager",
    "URLSession", "Task", "DispatchQueue", "@unchecked", ": Sendable",
]), "Package boundary gained app, I/O, scheduling or Sendable dependencies"
flags = ["-swift-version", "5", "-default-isolation", "MainActor",
         "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(archive), str(inventory), str(package)], check=True)
print("PASS: exact synchronous package constructor/forwarding; Foundation-only wrapper; strict standalone Core compilation", flush=True)


def failure(kind, message=None):
    result = {"kind": kind}
    if message is not None:
        result["message"] = message
    if kind == "url":
        result.update(domain="NSURLErrorDomain", code=-1016, userInfoEmpty=True)
    return result


def zip_data(entries, method):
    """Return a small real ZIP plus metadata/payloads independent of Swift."""
    buffer = BytesIO()
    metadata, payloads = [], []
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Duplicate name:", category=UserWarning)
        with zipfile.ZipFile(buffer, "w", compression=method) as output:
            for path, payload, directory in entries:
                info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = method
                info.external_attr = 0x10 if directory else 0
                output.writestr(info, payload)
                if not directory:
                    metadata.append(dict(
                        path=path, compressionMethod=info.compress_type,
                        compressedSize=info.compress_size, uncompressedSize=info.file_size,
                        crc32=info.CRC, dataOffset=info.header_offset + 30 + len(path.encode("utf-8")),
                        isDirectory=False,
                    ))
                    payloads.append(payload.hex())
    return buffer.getvalue(), metadata, payloads


def frames(count):
    return [(f"frame{index:02d}.png", bytes([index, 0, 255]) + b"frame" * index, False)
            for index in range(1, count + 1)]


with tempfile.TemporaryDirectory(prefix="eagle-dock-package-archive-") as directory:
    work = Path(directory)
    fixtures = []

    def add(name, count, entries=None, method=zipfile.ZIP_STORED, *,
            open_error=None, extract_error=None, failure_index=None,
            logs=None, mutation=None, raw=None):
        data, metadata, payloads = zip_data(entries or [], method) if raw is None else (raw, [], [])
        if mutation is not None:
            data = mutation(bytearray(data))
        if open_error is not None:
            metadata, payloads = [], []
        if failure_index is not None:
            payloads = payloads[:failure_index]
        filename = name + ".zip"
        (work / filename).write_bytes(data)
        fixtures.append(dict(
            name=name, filename=filename, frameCount=count, files=metadata,
            payloads=payloads, openError=open_error, extractError=extract_error,
            failureIndex=failure_index, logs=logs or [],
        ))

    def signature(which):
        def mutate(data):
            offset = data.index(which)
            data[offset] ^= 1
            return bytes(data)
        return mutate

    def delayed(kind, index):
        def mutate(data):
            # Modify only an in-bounds central-directory field; all sizes stay small.
            eocd = data.rindex(b"PK\x05\x06")
            central = struct.unpack_from("<I", data, eocd + 16)[0]
            for _ in range(index):
                name, extra, comment = struct.unpack_from("<HHH", data, central + 28)
                central += 46 + name + extra + comment
            if kind == "crc":
                crc = struct.unpack_from("<I", data, central + 16)[0]
                struct.pack_into("<I", data, central + 16, crc ^ 1)
            else:
                struct.pack_into("<H", data, central + 10, 99)
            return bytes(data)
        return mutate

    for count in [1, 17]:
        for method in [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED]:
            label = "stored" if method == zipfile.ZIP_STORED else "deflated"
            entries = [("ignored/", b"", True)] + list(reversed(frames(count)))
            entries += [("frame01.png", b"duplicate payload", False),
                        ("frame01.png", b"directory marker", True),
                        ("flagged-directory", b"", True)]
            add(f"valid-{count}-{label}", count, entries, method)
        add(f"missing-{count}", count, frames(count)[:-1], open_error=failure("url"))
        add(f"extra-{count}", count, frames(count) + [("extra.png", b"extra", False)],
            open_error=failure("url"))
        method = zipfile.ZIP_STORED if count == 1 else zipfile.ZIP_DEFLATED
        for kind, message in [("crc", "(zip) crc mismatch"),
                              ("unsupported", "(zip) unsupported compression, not a valid .zip")]:
            index = 0 if count == 1 else 1
            add(f"lazy-{kind}-{count}", count, frames(count), method,
                extract_error=failure(kind), failure_index=index, logs=[message],
                mutation=delayed(kind, index))
            # Expected metadata reflects the mutation; opening still preserves it.
            field = "crc32" if kind == "crc" else "compressionMethod"
            value = fixtures[-1]["files"][index][field]
            fixtures[-1]["files"][index][field] = value ^ 1 if kind == "crc" else 99

    # Raw frameCount is forwarded; package opening adds no catalog support policy.
    add("raw-frame-count-2", 2, frames(2))
    # Inventory failure must precede even a payload error in an expected filename.
    add("extra-before-crc", 1, frames(1) + [("extra.png", b"extra", False)],
        open_error=failure("url"), mutation=delayed("crc", 0))
    for name, raw, message in [
        ("empty", b"", "(zip) too small"),
        ("no-eocd", bytes(22), "(zip) no eocd"),
    ]:
        add(name, 1, raw=raw, open_error=failure("corrupt", message), logs=[message])
    for name, sig, message in [
        ("bad-central-signature", b"PK\x01\x02", "(zip) bad cd sig"),
        ("bad-local-signature", b"PK\x03\x04", "(zip) bad lfh sig"),
    ]:
        add(name, 1, frames(1), open_error=failure("corrupt", message),
            logs=[message], mutation=signature(sig))

    (work / "fixtures.json").write_text(json.dumps(fixtures))
    public = work / "PublicPackageArchive.swift"
    public.write_text(reference)
    binary = work / "verify"
    subprocess.run([
        "swiftc", *flags, "-parse-as-library", str(archive), str(inventory), str(package),
        str(public), str(repo / "scripts/verify_eagle_dock_package_archive.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary), str(work)], check=True, timeout=30)
