import Foundation

nonisolated private enum Event: Equatable, Sendable {
    case lookup(Int)
    case resolve(Int)
    case create(Int)
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

// Immutable configuration plus the locked trace satisfy FileManager's contract.
nonisolated private final class RecordingFileManager: FileManager, @unchecked Sendable {
    let managerID: Int
    let base: URL
    let trace: Trace
    let failure: NSError?
    let realCreation: Bool

    init(_ managerID: Int, base: URL, trace: Trace, failure: NSError?, realCreation: Bool) {
        self.managerID = managerID
        self.base = base
        self.trace = trace
        self.failure = failure
        self.realCreation = realCreation
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?, create shouldCreate: Bool
    ) throws -> URL {
        MainActor.preconditionIsolated()
        precondition(managerID == 1 && directory == .cachesDirectory && domain == .userDomainMask)
        precondition(url == nil && shouldCreate)
        trace.record(.resolve(managerID))
        if let failure { throw failure }
        return base
    }

    override func createDirectory(
        at url: URL, withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        MainActor.preconditionIsolated()
        precondition(managerID == 2 && createIntermediates && attributes == nil)
        precondition(url == base.appendingPathComponent("EagleGallery/Dock", isDirectory: true))
        precondition(url.hasDirectoryPath)
        trace.record(.create(managerID))
        if let failure { throw failure }
        if realCreation {
            // Only the exact requested Dock root under the supplied temporary base.
            try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
        }
    }
}

@MainActor
private final class Provider {
    let trace = Trace()
    let resolver: RecordingFileManager
    let creator: RecordingFileManager
    private(set) var calls = 0

    init(base: URL, resolveError: NSError? = nil, createError: NSError? = nil, realCreation: Bool = false) {
        resolver = RecordingFileManager(1, base: base, trace: trace, failure: resolveError, realCreation: false)
        creator = RecordingFileManager(2, base: base, trace: trace, failure: createError, realCreation: realCreation)
    }

    func manager() -> FileManager {
        MainActor.preconditionIsolated()
        calls += 1
        trace.record(.lookup(calls))
        return calls % 2 == 1 ? resolver : creator
    }
}

private func theme(_ id: String, version: Int) -> EagleDockGalleryTheme {
    EagleDockGalleryTheme(
        id: id, version: version, title: "Fixture", titleES: "Ejemplo",
        subtitle: "Cache", subtitleES: "Caché", accent: "#123456",
        previewURL: URL(string: "https://example.invalid/preview")!, animatedPreviewURL: nil,
        packageURL: URL(string: "https://example.invalid/package")!, sha256: "unused",
        byteCount: 0, frameCount: 0, fps: 0, width: 0, height: 0
    )
}

private func directory(reference: Bool, theme: EagleDockGalleryTheme, provider: Provider) throws -> URL {
    if reference {
        return try publicDockCacheDirectory(for: theme, fileManager: { provider.manager() })
    }
    let service = EagleDockGalleryCacheDirectory(fileManager: { provider.manager() })
    precondition(provider.calls == 0 && provider.trace.snapshot.isEmpty, "Initialization performed I/O")
    return try service.directory(for: theme)
}

private func verify(
    _ fixture: EagleDockGalleryTheme, base: URL,
    resolveError: NSError? = nil, createError: NSError? = nil
) throws {
    var previousURL: URL?
    for reference in [true, false] {
        let provider = Provider(base: base, resolveError: resolveError, createError: createError)
        let expectedError = resolveError ?? createError
        do {
            let result = try directory(reference: reference, theme: fixture, provider: provider)
            precondition(expectedError == nil, "Filesystem error was swallowed")
            let expected = base.appendingPathComponent("EagleGallery/Dock", isDirectory: true)
                .appendingPathComponent("\(fixture.id)-v\(fixture.version)", isDirectory: true)
            precondition(result == expected && result.hasDirectoryPath, "Raw id/version or URL directory semantics changed")
            if let previousURL { precondition(result == previousURL, "Public URL parity changed") }
            previousURL = result
        } catch {
            guard let expectedError else { throw error }
            let received = error as NSError
            precondition(received === expectedError, "Filesystem error identity was replaced")
            precondition(received.domain == expectedError.domain && received.code == expectedError.code)
            precondition(NSDictionary(dictionary: received.userInfo).isEqual(to: expectedError.userInfo))
        }
        let expectedEvents: [Event] = resolveError == nil
            ? [.lookup(1), .resolve(1), .lookup(2), .create(2)]
            : [.lookup(1), .resolve(1)]
        precondition(provider.trace.snapshot == expectedEvents, "Operation order or separate manager lookup changed")
        precondition(provider.calls == (resolveError == nil ? 2 : 1))
    }
}

private func verifyRealDirectories(base: URL, reference: Bool) throws {
    let provider = Provider(base: base, realCreation: true)
    let service = EagleDockGalleryCacheDirectory(fileManager: { provider.manager() })
    precondition(provider.calls == 0 && provider.trace.snapshot.isEmpty)
    let dock = base.appendingPathComponent("EagleGallery/Dock", isDirectory: true)
    let marker = dock.appendingPathComponent("retained.txt")
    let payload = Data("retained".utf8)
    for (index, version) in [3, 3, 4].enumerated() {
        let fixture = theme("fixture", version: version)
        let result = try reference
            ? publicDockCacheDirectory(for: fixture, fileManager: { provider.manager() })
            : service.directory(for: fixture)
        precondition(result == dock.appendingPathComponent("fixture-v\(version)", isDirectory: true))
        var isDirectory: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: dock.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        precondition(!FileManager.default.fileExists(atPath: result.path), "Theme child directory was created eagerly")
        if index == 0 { try payload.write(to: marker) }
        let retained = try Data(contentsOf: marker)
        precondition(retained == payload, "Repeated creation changed existing contents")
    }
    precondition(provider.calls == 6)
    precondition(provider.trace.snapshot == [
        .lookup(1), .resolve(1), .lookup(2), .create(2),
        .lookup(3), .resolve(1), .lookup(4), .create(2),
        .lookup(5), .resolve(1), .lookup(6), .create(2),
    ])
}

@main
private enum EagleDockCacheDirectoryContract {
    static func main() throws {
        MainActor.preconditionIsolated()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(root.lastPathComponent.hasPrefix("eagle-dock-cache-directory-"))
        _ = EagleDockGalleryCacheDirectory() // Default initializer has no effects.
        let fakeBase = root.appendingPathComponent("fake-only", isDirectory: true)
        var cases = 0
        // Odd identifiers are URL-only cases: the managers never create files.
        for id in ["fixture", "", "space #?%", "café-🌙", "nested/name", "../relative"] {
            for version in [-1, 0, 3] {
                try verify(theme(id, version: version), base: fakeBase)
                cases += 1
            }
        }
        let resolve = NSError(domain: "CacheResolveSentinel", code: 771, userInfo: ["payload": "resolve"])
        let create = NSError(domain: "CacheCreateSentinel", code: 772, userInfo: ["payload": "create"])
        for (first, second) in [(resolve, nil), (nil, create), (resolve, create)] as [(NSError?, NSError?)] {
            try verify(theme("fixture", version: 3), base: fakeBase, resolveError: first, createError: second)
            cases += 1
        }
        for reference in [true, false] {
            try verifyRealDirectories(base: root.appendingPathComponent(reference ? "public" : "core", isDirectory: true), reference: reference)
        }
        print("PASS: \(cases) public cache-location parity cases, exact arguments/order/two lookups, error identity/precedence, MainActor and repeated temporary-only mkdir")
    }
}
