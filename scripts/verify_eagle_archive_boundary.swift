import Foundation

// Only the final logger is a recorder. History, delivery, app composition and
// the ZIP adapter are production code; no access manager is present.
@MainActor
final class ArchiveDiagnosticRecorder {
    private var messages: [String] = []
    private var waiter: CheckedContinuation<[String], Never>?
    private var expectedCount = 0

    func log(_ message: String) {
        MainActor.assertIsolated()
        messages.append(message)
        if messages.count == expectedCount, let waiter {
            self.waiter = nil
            waiter.resume(returning: messages)
        }
    }

    func waitForMessages(_ count: Int) async -> [String] {
        if messages.count >= count { return messages }
        expectedCount = count
        return await withCheckedContinuation { waiter = $0 }
    }

    var messageCount: Int { messages.count }
}

let globallogger = ArchiveDiagnosticRecorder()

nonisolated private final class RecordingArchiveLog: @unchecked Sendable {
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

@main
private enum EagleArchiveBoundaryContract {
    @MainActor
    static func main() async throws {
        let readerLog = RecordingArchiveLog()
        let writerLog = RecordingArchiveLog()
        do {
            _ = try ZipArchive(data: Data(), log: { readerLog.record($0) })
            preconditionFailure("Empty data was accepted")
        } catch ZipError.corruptArchive(let message) {
            precondition(message == "(zip) too small")
        }
        precondition(readerLog.snapshot == ["(zip) too small"])
        precondition(writerLog.snapshot.isEmpty)
        precondition(globallogger.messageCount == 0)

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "eagle-archive-contract-\(UUID().uuidString)", isDirectory: true
        )
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let payload = Data([0, 1, 127, 128, 255])
        try payload.write(to: source.appendingPathComponent("frame01.png"))
        try Data().write(to: nested.appendingPathComponent("empty"))
        try Data([42]).write(to: source.appendingPathComponent(".hidden"))

        let coreOutput = root.appendingPathComponent("core.zip")
        try createZipArchive(fromDirectory: source, to: coreOutput, log: { writerLog.record($0) })
        let coreArchive = try ZipArchive(data: Data(contentsOf: coreOutput), log: { readerLog.record($0) })
        precondition(Set(coreArchive.entries.map(\.path)) == ["frame01.png", "nested/", "nested/empty"])
        for entry in coreArchive.entries {
            precondition(entry.compressionMethod == 0)
            let extracted = try coreArchive.extract(entry)
            precondition(extracted == (entry.path == "frame01.png" ? payload : Data()))
        }

        // Existing writer/reader APIs still work without adding arguments at
        // any Gallery, Styles, Wallpaper or icon-import call site.
        let legacyOutput = root.appendingPathComponent("adapter.zip")
        try createZipArchive(fromDirectory: source, to: legacyOutput)
        let adaptedArchive = try ZipArchive(data: Data(contentsOf: legacyOutput))
        precondition(Set(adaptedArchive.entries.map(\.path)) == Set(coreArchive.entries.map(\.path)))
        for entry in adaptedArchive.entries {
            let original = coreArchive[entry.path]!
            precondition(entry.compressionMethod == original.compressionMethod)
            precondition(entry.compressedSize == original.compressedSize)
            precondition(entry.uncompressedSize == original.uncompressedSize)
            precondition(entry.crc32 == original.crc32)
            precondition(entry.isDirectory == original.isDirectory)
            let adaptedData = try adaptedArchive.extract(entry)
            let coreData = try coreArchive.extract(original)
            precondition(adaptedData == coreData)
        }

        let unavailableOutput = root.appendingPathComponent("missing/output.zip")
        do {
            try createZipArchive(fromDirectory: source, to: unavailableOutput, log: { writerLog.record($0) })
            preconditionFailure("An output inside a missing directory was accepted")
        } catch ZipError.corruptArchive(let message) {
            precondition(message == "(zip) cannot create output file")
        }
        precondition(writerLog.snapshot == ["(zip) cannot create output file"])
        precondition(readerLog.snapshot == ["(zip) too small"])
        precondition(globallogger.messageCount == 0)

        do {
            _ = try ZipArchive(data: Data())
            preconditionFailure("Adapter accepted empty data")
        } catch ZipError.corruptArchive(let message) {
            precondition(message == "(zip) too small")
        }
        let firstMessages = await globallogger.waitForMessages(1)
        precondition(firstMessages == ["(zip) too small"])

        do {
            try createZipArchive(fromDirectory: source, to: unavailableOutput)
            preconditionFailure("Adapter accepted an unavailable output")
        } catch ZipError.corruptArchive(let message) {
            precondition(message == "(zip) cannot create output file")
        }
        let allMessages = await globallogger.waitForMessages(2)
        precondition(allMessages == ["(zip) too small", "(zip) cannot create output file"])
        precondition(EagleAppDiagnostics.shared.history.text == allMessages.joined(separator: "\n") + "\n")
        print("PASS: archive roundtrip, unchanged APIs, isolated sinks and manager-free owned history/delivery")
    }
}
