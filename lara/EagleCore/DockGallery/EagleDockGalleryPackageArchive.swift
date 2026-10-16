import Foundation

/// Opens a theme package and retains its accepted entries for lazy extraction.
/// Parsing and extraction remain synchronous; the caller supplies diagnostics.
nonisolated struct EagleDockGalleryPackageArchive {
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
}
