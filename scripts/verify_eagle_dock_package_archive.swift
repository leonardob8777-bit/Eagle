import Foundation

nonisolated private struct EntryMetadata: Decodable, Equatable, Sendable {
    let path: String
    let compressionMethod: UInt16
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let crc32: UInt32
    let dataOffset: UInt64
    let isDirectory: Bool

    init(_ entry: ZipEntry) {
        path = entry.path
        compressionMethod = entry.compressionMethod
        compressedSize = entry.compressedSize
        uncompressedSize = entry.uncompressedSize
        crc32 = entry.crc32
        dataOffset = entry.dataOffset
        isDirectory = entry.isDirectory
    }
}

nonisolated private struct Failure: Decodable, Equatable, Sendable {
    let kind: String
    var message: String? = nil
    var domain: String? = nil
    var code: Int? = nil
    var userInfoEmpty: Bool? = nil

    static func capture(_ error: Error) -> Self {
        switch error {
        case ZipError.corruptArchive(let message): return Self(kind: "corrupt", message: message)
        case ZipError.crcMismatch: return Self(kind: "crc")
        case ZipError.unsupportedCompression: return Self(kind: "unsupported")
        case ZipError.notFound(let path): return Self(kind: "notFound", message: path)
        case let error as URLError:
            let nsError = error as NSError
            return Self(kind: "url", domain: nsError.domain, code: error.code.rawValue,
                        userInfoEmpty: nsError.userInfo.isEmpty)
        default: preconditionFailure("Unexpected package error: \(error)")
        }
    }
}

nonisolated private struct Fixture: Decodable, Sendable {
    let name: String
    let filename: String
    let frameCount: Int
    let files: [EntryMetadata]
    let payloads: [String]
    let openError: Failure?
    let extractError: Failure?
    let failureIndex: Int?
    let logs: [String]
}

// Only this test recorder is synchronized; the wrapper stays local to its caller.
nonisolated private final class RecordingPackageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

nonisolated private struct Snapshot: Equatable, Sendable {
    let files: [EntryMetadata]
    let payloads: [String]
    let openError: Failure?
    let extractError: Failure?
    let failureIndex: Int?
    let openingLogs: [String]
    let allLogs: [String]
}

nonisolated private func extract(
    files: [ZipEntry], using read: (ZipEntry) throws -> Data, log: RecordingPackageLog
) -> Snapshot {
    let openingLogs = log.snapshot
    var payloads: [String] = []
    for (index, entry) in files.enumerated() {
        do {
            let data = try read(entry)
            payloads.append(data.map { String(format: "%02x", $0) }.joined())
        } catch {
            return Snapshot(files: files.map(EntryMetadata.init), payloads: payloads,
                            openError: nil, extractError: Failure.capture(error), failureIndex: index,
                            openingLogs: openingLogs, allLogs: log.snapshot)
        }
    }
    return Snapshot(files: files.map(EntryMetadata.init), payloads: payloads,
                    openError: nil, extractError: nil, failureIndex: nil,
                    openingLogs: openingLogs, allLogs: log.snapshot)
}

nonisolated private func inspect(_ fixture: Fixture, data: Data, reference: Bool) -> Snapshot {
    let log = RecordingPackageLog()
    do {
        if reference {
            let archive = try PublicDockPackageArchive(
                data: data, frameCount: fixture.frameCount, log: { log.record($0) }
            )
            return extract(files: archive.files, using: archive.extract, log: log)
        }
        let archive = try EagleDockGalleryPackageArchive(
            data: data, frameCount: fixture.frameCount, log: { log.record($0) }
        )
        return extract(files: archive.files, using: archive.extract, log: log)
    } catch {
        return Snapshot(files: [], payloads: [], openError: Failure.capture(error),
                        extractError: nil, failureIndex: nil,
                        openingLogs: log.snapshot, allLogs: log.snapshot)
    }
}

nonisolated private func verify(_ fixture: Fixture, data: Data) -> Snapshot {
    let original = inspect(fixture, data: data, reference: true)
    let actual = inspect(fixture, data: data, reference: false)
    precondition(actual == original, "Public opening/extraction differs: \(fixture.name)")
    precondition(actual.files == fixture.files, "Metadata/order/duplicates changed: \(fixture.name)")
    precondition(actual.payloads == fixture.payloads, "Payload/order changed: \(fixture.name)")
    precondition(actual.openError == fixture.openError, "Opening error changed: \(fixture.name)")
    precondition(actual.extractError == fixture.extractError, "Extract error changed: \(fixture.name)")
    precondition(actual.failureIndex == fixture.failureIndex, "Lazy failure order changed: \(fixture.name)")
    precondition(actual.openingLogs == (fixture.openError == nil ? [] : fixture.logs),
                 "Extraction or diagnostic delivery happened during opening: \(fixture.name)")
    precondition(actual.allLogs == fixture.logs, "Injected diagnostic sink changed: \(fixture.name)")
    return actual
}

@main
private enum EagleDockPackageArchiveContract {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixtures = try JSONDecoder().decode(
            [Fixture].self, from: Data(contentsOf: root.appendingPathComponent("fixtures.json"))
        )
        for fixture in fixtures {
            let data = try Data(contentsOf: root.appendingPathComponent(fixture.filename))
            let synchronous = verify(fixture, data: data)
            // Construct/read/extract on the detached caller; only Sendable values return.
            let detached = await Task.detached { verify(fixture, data: data) }.value
            precondition(detached == synchronous, "Caller isolation changed: \(fixture.name)")
        }
        print("PASS: \(fixtures.count) real stored/deflated ZIP cases, independent public parity, metadata/order/duplicates, lazy errors/logs and detached local use")
    }
}
