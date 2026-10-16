import Foundation

nonisolated private enum Event: Equatable, Sendable {
    case prepare
    case exists(String)
    case remove(URL)
    case move(URL, URL)
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
    let destination: URL
    let staging: URL
    let destinationExists: Bool
    let removalFailure: NSError?
    let moveFailure: NSError?
    let cleanupFailure: NSError?
    let realIO: Bool
    let trace: Trace

    init(destination: URL, staging: URL, exists: Bool, removalFailure: NSError? = nil,
         moveFailure: NSError? = nil, cleanupFailure: NSError? = nil,
         realIO: Bool = false, trace: Trace) {
        self.destination = destination
        self.staging = staging
        self.destinationExists = exists
        self.removalFailure = removalFailure
        self.moveFailure = moveFailure
        self.cleanupFailure = cleanupFailure
        self.realIO = realIO
        self.trace = trace
        super.init()
    }

    override func fileExists(atPath path: String) -> Bool {
        MainActor.preconditionIsolated()
        precondition(path == destination.path)
        trace.record(.exists(path))
        return realIO ? super.fileExists(atPath: path) : destinationExists
    }

    override func removeItem(at url: URL) throws {
        MainActor.preconditionIsolated()
        precondition(url == destination || url == staging, "Unexpected deletion target")
        trace.record(.remove(url))
        if url == destination, let removalFailure { throw removalFailure }
        if url == staging, let cleanupFailure { throw cleanupFailure }
        if realIO { try super.removeItem(at: url) }
    }

    override func moveItem(at source: URL, to target: URL) throws {
        MainActor.preconditionIsolated()
        precondition(source == staging && target == destination)
        trace.record(.move(source, target))
        if let moveFailure { throw moveFailure }
        if realIO { try super.moveItem(at: source, to: target) }
    }
}

private func commit(reference: Bool, staging: URL, destination: URL,
                    fileManager: FileManager, prepareFrames: @MainActor () throws -> Void) throws {
    if reference {
        try publicDockCacheCommit(staging: staging, to: destination,
                                  fileManager: fileManager, prepareFrames: prepareFrames)
    } else {
        try EagleDockGalleryCacheCommit.commit(staging: staging, to: destination,
                                              fileManager: fileManager, prepareFrames: prepareFrames)
    }
}

private func verifyInjected(exists: Bool, preparationFailure: NSError? = nil,
                            removalFailure: NSError? = nil, moveFailure: NSError? = nil,
                            cleanupFailure: NSError? = nil,
                            destination: URL, staging: URL) throws {
    let expectedFailure = preparationFailure ?? (exists ? removalFailure : nil) ?? moveFailure
    var expected = [Event.prepare]
    if preparationFailure == nil {
        expected.append(.exists(destination.path))
        if exists { expected.append(.remove(destination)) }
        if !exists || removalFailure == nil { expected.append(.move(staging, destination)) }
    }
    if expectedFailure != nil { expected.append(.remove(staging)) }
    for reference in [true, false] {
        let trace = Trace()
        let fm = RecordingFileManager(destination: destination, staging: staging, exists: exists,
                                      removalFailure: removalFailure, moveFailure: moveFailure,
                                      cleanupFailure: cleanupFailure, trace: trace)
        do {
            try commit(reference: reference, staging: staging, destination: destination, fileManager: fm) {
                MainActor.preconditionIsolated()
                trace.record(.prepare)
                if let preparationFailure { throw preparationFailure }
            }
            precondition(expectedFailure == nil, "Operation error swallowed")
        } catch {
            guard let expectedFailure else { throw error }
            let received = error as NSError
            precondition(received === expectedFailure, "Original error replaced by cleanup error")
            precondition(received.domain == expectedFailure.domain && received.code == expectedFailure.code)
            precondition(NSDictionary(dictionary: received.userInfo).isEqual(to: expectedFailure.userInfo))
        }
        precondition(trace.snapshot == expected, "Callback/replacement/cleanup order or count changed")
    }
}

private enum Scenario: String, CaseIterable {
    case newCache, replacement, invalidFrames, failedMoveAfterRemoval, destinationIsFile, missingStaging
}

private func verifyReal(root: URL) throws {
    let fs = FileManager.default
    let oldBytes = Data("old cache contents".utf8)
    let newBytes = Data([0, 255, 3, 8])
    let frame = "frame01.png"
    let operationFailure = NSError(domain: "CacheCommitSentinel", code: 875, userInfo: ["source": "frames"])
    for scenario in Scenario.allCases {
        var referenceEvents: [Event]?
        var referenceError: NSError?
        for reference in [true, false] {
            let parent = root.appendingPathComponent("\(scenario.rawValue)-\(reference)", isDirectory: true)
            let destination = parent.appendingPathComponent("fixture-v1", isDirectory: true)
            let staging = parent.appendingPathComponent(".fixture-staging", isDirectory: true)
            // These are explicit children of Python's newly created TemporaryDirectory.
            precondition(parent.deletingLastPathComponent() == root)
            try fs.createDirectory(at: parent, withIntermediateDirectories: true)
            if scenario != .missingStaging {
                try fs.createDirectory(at: staging, withIntermediateDirectories: false)
            }
            if scenario == .replacement || scenario == .invalidFrames || scenario == .failedMoveAfterRemoval {
                try fs.createDirectory(at: destination, withIntermediateDirectories: false)
                try oldBytes.write(to: destination.appendingPathComponent(frame))
            } else if scenario == .destinationIsFile {
                try oldBytes.write(to: destination)
            }
            let trace = Trace()
            let fm = RecordingFileManager(destination: destination, staging: staging, exists: false,
                                          moveFailure: scenario == .failedMoveAfterRemoval ? operationFailure : nil,
                                          realIO: true, trace: trace)
            var received: NSError?
            do {
                try commit(reference: reference, staging: staging, destination: destination, fileManager: fm) {
                    MainActor.preconditionIsolated()
                    trace.record(.prepare)
                    if scenario != .missingStaging { try newBytes.write(to: staging.appendingPathComponent(frame), options: .atomic) }
                    if scenario == .invalidFrames { throw operationFailure }
                }
            } catch {
                received = error as NSError
            }
            precondition(!fs.fileExists(atPath: staging.path), "Temporary staging remained")
            switch scenario {
            case .newCache, .replacement, .destinationIsFile:
                precondition(received == nil)
                let output = try Data(contentsOf: destination.appendingPathComponent(frame))
                precondition(output == newBytes, "New cache payload changed")
            case .invalidFrames:
                precondition(received === operationFailure)
                let retained = try Data(contentsOf: destination.appendingPathComponent(frame))
                precondition(retained == oldBytes, "Preparation failure changed old cache")
            case .failedMoveAfterRemoval:
                precondition(received === operationFailure)
                // Preserve the public limitation: deletion precedes move, with no rollback.
                precondition(!fs.fileExists(atPath: destination.path), "Unexpected rollback or reordering")
            case .missingStaging:
                precondition(received?.domain == NSCocoaErrorDomain && received?.code == NSFileNoSuchFileError)
                precondition(!fs.fileExists(atPath: destination.path))
            }
            let normalized = trace.snapshot.map { event -> Event in
                switch event {
                case .prepare: return .prepare
                case .exists: return .exists("destination")
                case .remove(let url): return .remove(URL(fileURLWithPath: url == destination ? "/synthetic/destination" : "/synthetic/staging"))
                case .move: return .move(URL(fileURLWithPath: "/synthetic/staging"), URL(fileURLWithPath: "/synthetic/destination"))
                }
            }
            if reference {
                referenceEvents = normalized
                referenceError = received
            } else {
                precondition(normalized == referenceEvents, "Real operation trace differs from public")
                precondition(received?.domain == referenceError?.domain && received?.code == referenceError?.code)
                // File paths differ between fixtures, so compare code/domain rather than userInfo here.
            }
        }
    }
}

@main
private enum EagleDockCacheCommitContract {
    static func main() throws {
        MainActor.preconditionIsolated()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(root.lastPathComponent.hasPrefix("eagle-dock-cache-commit-"))
        let destination = URL(fileURLWithPath: "/synthetic/eagle cache/fixture-v1", isDirectory: true)
        let staging = URL(fileURLWithPath: "/synthetic/eagle cache/.fixture-staging", isDirectory: true)
        let preparation = NSError(domain: "PreparationSentinel", code: 801, userInfo: ["detail": "original"])
        let removal = NSError(domain: "RemovalSentinel", code: 802)
        let move = NSError(domain: "MoveSentinel", code: 803)
        let cleanup = NSError(domain: "CleanupSentinel", code: 804)
        var cases = 0
        for exists in [false, true] {
            try verifyInjected(exists: exists, destination: destination, staging: staging)
            cases += 1
            for cleanupFailure: NSError? in [nil, cleanup] {
                try verifyInjected(exists: exists, preparationFailure: preparation,
                                   cleanupFailure: cleanupFailure, destination: destination, staging: staging)
                try verifyInjected(exists: exists, moveFailure: move,
                                   cleanupFailure: cleanupFailure, destination: destination, staging: staging)
                cases += 2
            }
        }
        for cleanupFailure: NSError? in [nil, cleanup] {
            try verifyInjected(exists: true, removalFailure: removal, moveFailure: move,
                               cleanupFailure: cleanupFailure, destination: destination, staging: staging)
            cases += 1
        }
        // Unusual URLs are intercepted and never touch the filesystem.
        for urls in [
            (URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/synthetic/staging")),
            (URL(fileURLWithPath: "/synthetic/café #?%"), URL(fileURLWithPath: "/synthetic/🌙")),
            (destination, destination),
        ] {
            try verifyInjected(exists: true, destination: urls.0, staging: urls.1)
            cases += 1
        }
        try verifyReal(root: root)
        print("PASS: \(cases) injected public parity cases, exact synchronous MainActor order/error identity, and 6 temporary-only filesystem scenarios for both implementations")
    }
}
