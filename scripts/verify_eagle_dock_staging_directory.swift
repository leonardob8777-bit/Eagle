import Foundation

nonisolated private enum Event: Equatable, Sendable {
    case identifier
    case create(URL)
}

nonisolated private final class Trace: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Event] = []

    func record(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var snapshot: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

nonisolated private final class RecordingFileManager: FileManager, @unchecked Sendable {
    let expected: URL?
    let realParent: URL?
    let failure: NSError?
    let trace: Trace

    init(expected: URL?, realParent: URL? = nil, failure: NSError? = nil, trace: Trace) {
        self.expected = expected
        self.realParent = realParent
        self.failure = failure
        self.trace = trace
        super.init()
    }

    override func createDirectory(
        at url: URL, withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        MainActor.preconditionIsolated()
        precondition(createIntermediates && attributes == nil && url.hasDirectoryPath)
        if let expected { precondition(url == expected, "Staging URL changed") }
        if let realParent {
            precondition(url.deletingLastPathComponent() == realParent)
            precondition(url.lastPathComponent.hasPrefix(".fixture-"))
        }
        trace.record(.create(url))
        if let failure { throw failure }
        if realParent != nil {
            // Only normal IDs and the exact parent below Python's TemporaryDirectory.
            try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
        }
    }
}

private let fixed = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!

private func expected(beside destination: URL, id: String) -> URL {
    destination.deletingLastPathComponent()
        .appendingPathComponent(".\(id)-01234567-89AB-CDEF-0123-456789ABCDEF", isDirectory: true)
}

private func verify(destination: URL, id: String, failure: NSError? = nil) throws {
    let target = expected(beside: destination, id: id)
    for reference in [true, false] {
        let trace = Trace()
        let fm = RecordingFileManager(expected: target, failure: failure, trace: trace)
        let make: EagleDockGalleryStagingDirectory.MakeIdentifier = {
            MainActor.preconditionIsolated()
            trace.record(.identifier)
            return fixed
        }
        do {
            let result = try reference
                ? publicDockStagingDirectory(beside: destination, themeID: id, fileManager: fm, makeIdentifier: make)
                : EagleDockGalleryStagingDirectory.create(beside: destination, themeID: id, fileManager: fm, makeIdentifier: make)
            precondition(failure == nil, "Creation error was swallowed")
            precondition(result == target && result.hasDirectoryPath, "Raw ID/UUID or directory URL semantics changed")
        } catch {
            guard let failure else { throw error }
            let received = error as NSError
            precondition(received === failure, "Creation error identity was replaced")
            precondition(received.domain == failure.domain && received.code == failure.code)
            precondition(NSDictionary(dictionary: received.userInfo).isEqual(to: failure.userInfo))
        }
        precondition(trace.snapshot == [.identifier, .create(target)], "Identifier count/order, retry or cleanup changed")
    }
}

private func verifyReal(root: URL) throws {
    let parent = root.appendingPathComponent("fixed", isDirectory: true)
    let destination = parent.appendingPathComponent("fixture-v3", isDirectory: true)
    let target = expected(beside: destination, id: "fixture")
    let trace = Trace()
    let fm = RecordingFileManager(expected: target, realParent: parent, trace: trace)
    let marker = target.appendingPathComponent("retained.txt")
    let payload = Data("retained".utf8)
    for index in 0..<2 {
        let result = try EagleDockGalleryStagingDirectory.create(
            beside: destination, themeID: "fixture", fileManager: fm,
            makeIdentifier: { MainActor.preconditionIsolated(); trace.record(.identifier); return fixed }
        )
        precondition(result == target)
        var isDirectory: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: result.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        if index == 0 { try payload.write(to: marker) }
        let retained = try Data(contentsOf: marker)
        precondition(retained == payload, "Fixed-identifier collision changed existing contents")
    }
    precondition(trace.snapshot == [.identifier, .create(target), .identifier, .create(target)])

    let generatedParent = root.appendingPathComponent("generated", isDirectory: true)
    let generatedDestination = generatedParent.appendingPathComponent("fixture-v3", isDirectory: true)
    let generatedTrace = Trace()
    let generatedFM = RecordingFileManager(expected: nil, realParent: generatedParent, trace: generatedTrace)
    var generated: [URL] = []
    for _ in 0..<2 {
        let result = try EagleDockGalleryStagingDirectory.create(
            beside: generatedDestination, themeID: "fixture", fileManager: generatedFM
        )
        let suffix = String(result.lastPathComponent.dropFirst(".fixture-".count))
        precondition(UUID(uuidString: suffix)?.uuidString == suffix, "Default UUID string changed")
        precondition(result.hasDirectoryPath && result.deletingLastPathComponent() == generatedParent)
        precondition(FileManager.default.fileExists(atPath: result.path))
        generated.append(result)
    }
    precondition(generated[0] != generated[1], "Default identifier was reused")
    precondition(generatedTrace.snapshot == generated.map(Event.create))
}

@main
private enum EagleDockStagingDirectoryContract {
    static func main() throws {
        MainActor.preconditionIsolated()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(root.lastPathComponent.hasPrefix("eagle-dock-staging-directory-"))
        let destination = URL(fileURLWithPath: "/synthetic/eagle cache/fixture-v3", isDirectory: true)
        var cases = 0
        // All unusual IDs and destinations use intercepted create calls only.
        for id in ["fixture", "", "space #?%", "café-🌙", "nested/name", "../relative"] {
            try verify(destination: destination, id: id)
            cases += 1
        }
        for destination in [URL(fileURLWithPath: "/", isDirectory: true),
                            URL(fileURLWithPath: "/synthetic/file", isDirectory: false)] {
            try verify(destination: destination, id: "fixture")
            cases += 1
        }
        let sentinel = NSError(domain: "StagingCreateSentinel", code: 774, userInfo: ["payload": "retained"])
        try verify(destination: destination, id: "fixture", failure: sentinel)
        cases += 1
        try verifyReal(root: root)
        print("PASS: \(cases) public staging parity cases, exact UUID/URL/arguments/order, MainActor, unchanged error identity, temporary-only fixed collisions and fresh default UUIDs")
    }
}
