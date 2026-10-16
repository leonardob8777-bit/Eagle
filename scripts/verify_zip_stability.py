#!/usr/bin/env python3
"""Check the production ZIP reader against valid and truncated media packages."""
from pathlib import Path
import io
import struct
import subprocess
import tempfile
import zipfile

repo = Path(__file__).resolve().parents[1]
core = repo / "lara/EagleCore/Archives/EagleZIPArchive.swift"
runner = r'''
var checked = 0
for path in CommandLine.arguments.dropFirst() {
    FileHandle.standardError.write(Data(("Checking " + URL(fileURLWithPath: path).lastPathComponent + "\n").utf8))
    let invalid = path.hasSuffix(".bad.zip")
    do {
        let archive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: path)), log: { _ in })
        for entry in archive.entries { _ = try archive.extract(entry) }
        precondition(!invalid, "Malformed archive was accepted: \(path)")
    } catch {
        precondition(invalid, "Valid archive failed: \(path): \(error)")
    }
    checked += 1
}
print("PASS: production ZIP reader, \(checked) valid/truncated/oversized cases")
'''
with tempfile.TemporaryDirectory(prefix="eagle-zip-qa-") as directory:
    work = Path(directory)
    swift = work / "main.swift"
    swift.write_text("import Foundation\n" + runner)
    binary = work / "verify"
    # Compile the exact complete production core; no Lara manager or source slicing.
    subprocess.run(["swiftc", "-swift-version", "5", str(core), str(swift), "-o", str(binary)], check=True)
    cases = []
    def case(name, data, bad=False):
        path = work / (name + (".bad.zip" if bad else ".zip"))
        path.write_bytes(data)
        cases.append(str(path))
    for method in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=method) as archive:
            archive.writestr("frame.png", b"image data" * 100)
            archive.writestr("empty", b"")
        case("valid-" + str(method), buffer.getvalue())
    data = buffer.getvalue()
    for count in range(0, len(data), 7):
        case("truncated-" + str(count), data[:count], True)
    central = data.index(b"PK\x01\x02")
    end = data.rfind(b"PK\x05\x06")
    for name, offset, fmt, value in [
        ("cd-name", central + 28, "H", 65535),
        ("cd-extra", central + 30, "H", 65535),
        ("cd-comment", central + 32, "H", 65535),
        ("lfh-offset", central + 42, "I", 0xFFFFFFFE),
        ("compressed-size", central + 20, "I", 0xFFFFFFFE),
        ("expanded-size", central + 24, "I", 0xFFFFFFFE),
        ("size-mismatch", central + 24, "I", 800),
        ("central-offset", end + 16, "I", 0xFFFFFFFE),
        ("central-size", end + 12, "I", 0xFFFFFFFE),
        ("entry-count", end + 10, "H", 65000),
        ("missing-zip64", central + 24, "I", 0xFFFFFFFF),
    ]:
        corrupt = bytearray(data)
        struct.pack_into("<" + fmt, corrupt, offset, value)
        case(name, corrupt, True)
    # A signature in the comment must not be scanned as a complete EOCD.
    comment = bytearray(data)
    struct.pack_into("<H", comment, end + 20, 4)
    comment.extend(b"PK\x05\x06")
    case("signature-comment", comment)
    # ZIP64 fields are present only for the corresponding sentinel values.
    partial = bytearray(data)
    compressed = struct.unpack_from("<I", partial, central + 20)[0]
    name_length = struct.unpack_from("<H", partial, central + 28)[0]
    struct.pack_into("<I", partial, central + 20, 0xFFFFFFFF)
    struct.pack_into("<H", partial, central + 30, 12)
    insert = central + 46 + name_length
    partial[insert:insert] = struct.pack("<HHQ", 1, 8, compressed)
    struct.pack_into("<I", partial, end + 12 + 12, struct.unpack_from("<I", data, end + 12)[0] + 12)
    case("zip64-compressed-only", partial)
    packages = repo.parent / "Eagle-Gallery-Builds/2026-09-06-island-gifs"
    cases.extend(str(path) for path in sorted(packages.glob("*/*-v1.zip")))
    subprocess.run([str(binary), *cases], check=True)
