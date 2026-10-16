import Foundation

/// The public Dock package's filename rule, isolated from download and UI code.
/// The caller supplies a positive frame count, as the existing catalog gate does.
nonisolated enum EagleDockGalleryPackageInventory {
    static func frameFiles(in entries: [ZipEntry], frameCount: Int) throws -> [ZipEntry] {
        let expected = Set((1...frameCount).map { String(format: "frame%02d.png", $0) })
        let files = entries.filter { !$0.isDirectory }
        guard Set(files.map(\.path)) == expected else { throw URLError(.cannotDecodeContentData) }
        return files
    }
}
