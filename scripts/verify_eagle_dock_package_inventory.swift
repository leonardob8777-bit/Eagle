import Foundation

nonisolated private func entry(_ path: String, directory: Bool = false, marker: Int = 0) -> ZipEntry {
    ZipEntry(
        path: path, compressionMethod: UInt16(marker % 2 == 0 ? 0 : 8),
        compressedSize: UInt64(marker + 3), uncompressedSize: UInt64(marker + 9),
        crc32: UInt32(marker + 11), dataOffset: UInt64(marker + 17), isDirectory: directory
    )
}

nonisolated private func identical(_ lhs: ZipEntry, _ rhs: ZipEntry) -> Bool {
    lhs.path == rhs.path && lhs.compressionMethod == rhs.compressionMethod &&
        lhs.compressedSize == rhs.compressedSize && lhs.uncompressedSize == rhs.uncompressedSize &&
        lhs.crc32 == rhs.crc32 && lhs.dataOffset == rhs.dataOffset && lhs.isDirectory == rhs.isDirectory
}

nonisolated private func outcome(
    _ operation: () throws -> [ZipEntry]
) -> Result<[ZipEntry], URLError> {
    do { return .success(try operation()) }
    catch let error as URLError { return .failure(error) }
    catch { preconditionFailure("Unexpected inventory error: \(error)") }
}

nonisolated private func verify(_ entries: [ZipEntry], frames: Int, accepted: Bool? = nil) {
    let original = outcome { try publicDockPackageInventory(entries, frameCount: frames) }
    let actual = outcome { try EagleDockGalleryPackageInventory.frameFiles(in: entries, frameCount: frames) }
    switch (original, actual) {
    case (.success(let old), .success(let new)):
        precondition(accepted != false, "Invalid filenames were accepted")
        precondition(old.count == new.count && zip(old, new).allSatisfy { identical($0.0, $0.1) })
        let filtered = entries.filter { !$0.isDirectory }
        precondition(filtered.count == new.count && zip(filtered, new).allSatisfy { identical($0.0, $0.1) })
    case (.failure(let old), .failure(let new)):
        precondition(accepted != true, "Valid filenames were rejected")
        precondition(old.code == .cannotDecodeContentData && new.code == old.code)
        precondition((old as NSError).domain == (new as NSError).domain)
        precondition((old as NSError).userInfo.isEmpty && (new as NSError).userInfo.isEmpty)
    default:
        preconditionFailure("Core differs from the public filename rule")
    }
}

@main
private enum EagleDockPackageInventoryContract {
    static func main() async throws {
        var checked = 0
        for frames in [1, 2, 17, 100] {
            let valid = (1...frames).map { entry(String(format: "frame%02d.png", $0), marker: $0) }
            let directories = [entry("arbitrary/", directory: true), entry("frame01.png", directory: true)]
            verify(valid, frames: frames, accepted: true)
            verify(Array(valid.reversed()), frames: frames, accepted: true)
            verify(directories + valid + [valid[0]], frames: frames, accepted: true)
            verify([], frames: frames, accepted: false)
            verify(directories, frames: frames, accepted: false)
            verify(Array(valid.dropLast()), frames: frames, accepted: false)
            checked += 6
            for path in ["extra.png", "frame01.PNG", "Frame01.png", "nested/frame01.png", "frame1.png", "./frame01.png", ".DS_Store"] {
                verify(valid + [entry(path)], frames: frames, accepted: false)
                checked += 1
            }
            // Directory flags matter, even when a directory has an expected name.
            verify(Array(valid.dropFirst()) + [entry("frame01.png", directory: true)], frames: frames, accepted: false)
            checked += 1
        }

        // Reproducible mixtures of duplicate names, missing/extra paths and
        // directory flags also verify the returned entry metadata and order.
        var seed: UInt64 = 0xEA61E
        func pick(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        for frames in [1, 17] {
            let names = (1...frames).map { String(format: "frame%02d.png", $0) } + ["extra", "FRAME01.PNG", "sub/frame01.png"]
            for _ in 0..<500 {
                let entries = (0..<pick(40)).map { marker in
                    entry(names[pick(names.count)], directory: pick(4) == 0, marker: marker)
                }
                verify(entries, frames: frames)
                checked += 1
            }
        }

        // Exercise the boundary with entries produced by the exact production
        // writer/reader. Image decoding stays outside this filename-only stage.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("eagle-inventory-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for frames in [1, 17] {
            let source = root.appendingPathComponent("source-\(frames)")
            try fm.createDirectory(at: source.appendingPathComponent("ignored"), withIntermediateDirectories: true)
            for index in 1...frames {
                try Data([UInt8(index)]).write(to: source.appendingPathComponent(String(format: "frame%02d.png", index)))
            }
            let output = root.appendingPathComponent("package-\(frames).zip")
            try createZipArchive(fromDirectory: source, to: output, log: { _ in })
            let archive = try ZipArchive(data: Data(contentsOf: output), log: { _ in })
            verify(archive.entries, frames: frames, accepted: true)
            try Data([1]).write(to: source.appendingPathComponent("extra.txt"))
            let invalidOutput = root.appendingPathComponent("extra-\(frames).zip")
            try createZipArchive(fromDirectory: source, to: invalidOutput, log: { _ in })
            let invalidArchive = try ZipArchive(data: Data(contentsOf: invalidOutput), log: { _ in })
            verify(invalidArchive.entries, frames: frames, accepted: false)
            checked += 2
        }

        let entries = [entry("frame01.png")]
        let detached = try await Task.detached {
            try EagleDockGalleryPackageInventory.frameFiles(in: entries, frameCount: 1)
        }.value
        precondition(detached.count == 1 && identical(detached[0], entries[0]))
        print("PASS: \(checked) public inventory parity cases, exact errors, metadata/order, real ZIP entries and UI-independent execution")
    }
}
