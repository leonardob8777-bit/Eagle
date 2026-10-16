import Foundation
import UIKit
import CryptoKit

/// Owns Island package preparation, verified frame caching and staged extraction.
/// Keeps the detached worker and forwards cancellation without changing native applying.
nonisolated enum EagleIslandGalleryPackage {
    static func prepare(
        theme: EagleIslandGalleryTheme? = nil,
        fileManager: @escaping @Sendable () -> FileManager = { .default },
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        },
        downloadPackage: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse) = {
            try await URLSession.shared.download(for: $0)
        },
        log: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        // PNG validation and ZIP extraction must not stall the gallery UI.
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let fm = fileManager()
            let root = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true)
                .appendingPathComponent("EagleGallery/Island", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if let theme, !theme.isSupported { throw URLError(.cannotParseResponse) }
            let themeID = theme?.id ?? "singularity-live"
            let savedManifest = root.appendingPathComponent("\(themeID)-v1.json")
            let manifestURL = URL(string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/island-live-v1.json")!
            var request = URLRequest(url: manifestURL)
            request.timeoutInterval = 20
            let manifestData: Data
            if let theme {
                manifestData = try JSONEncoder().encode(theme.manifest)
            } else { do {
                let (data, response) = try await fetch(request)
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200, data.count <= 32 * 1024 else {
                    throw URLError(.badServerResponse)
                }
                manifestData = data
            } catch {
                manifestData = try Data(contentsOf: savedManifest)
            } }
            let manifest = try JSONDecoder().decode(EagleIslandGalleryManifest.self, from: manifestData)
            try Task.checkCancellation()
            guard manifest.isSupported, manifest.id == themeID else { throw URLError(.cannotParseResponse) }
            let destination = root.appendingPathComponent("\(manifest.id)-v\(manifest.version)", isDirectory: true)
            if validFrames(in: destination, manifest: manifest) { return destination }

            request = URLRequest(url: manifest.packageURL)
            request.timeoutInterval = 90
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (download, response) = try await downloadPackage(request)
            defer { try? fm.removeItem(at: download) }
            try Task.checkCancellation()
            let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, size == manifest.byteCount else {
                throw URLError(.badServerResponse)
            }
            let data = try Data(contentsOf: download, options: .mappedIfSafe)
            guard digest(data) == manifest.sha256 else { throw URLError(.secureConnectionFailed) }
            let archive = try ZipArchive(data: data, log: log)
            let expected = Set((1...17).map { String(format: "frame%02d.png", $0) })
            let entries = archive.entries
            guard entries.count == 17, Set(entries.map(\.path)) == expected,
                  entries.allSatisfy({ !$0.isDirectory && $0.uncompressedSize > 0 && $0.uncompressedSize <= 2 * 1024 * 1024 }) else {
                throw URLError(.cannotDecodeContentData)
            }
            let staging = root.appendingPathComponent(".island-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            for entry in entries {
                try Task.checkCancellation()
                try autoreleasepool {
                    try archive.extract(entry).write(to: staging.appendingPathComponent(entry.path), options: .atomic)
                }
            }
            guard validFrames(in: staging, manifest: manifest) else { throw URLError(.cannotDecodeContentData) }
            try Task.checkCancellation()
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
            try manifestData.write(to: savedManifest, options: .atomic)
            return destination
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validFrames(in directory: URL, manifest: EagleIslandGalleryManifest) -> Bool {
        (1...17).allSatisfy { index in
            autoreleasepool {
            let file = directory.appendingPathComponent(String(format: "frame%02d.png", index))
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= 2 * 1024 * 1024,
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                  digest(data) == manifest.frameSHA256[index - 1],
                  let image = UIImage(data: data)?.cgImage else { return false }
            return image.width == 1200 && image.height == 500
            }
        }
    }
}
