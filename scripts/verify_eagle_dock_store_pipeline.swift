import Foundation
import UIKit
import CryptoKit
import Combine

@MainActor
protocol FixtureStore: AnyObject {
    var themes: [EagleDockGalleryTheme] { get }
    var downloadingID: String? { get }
    var loading: Bool { get }
    var errorMessage: String? { get }
    var stateChanges: AnyPublisher<String?, Never> { get }
    var loadingChanges: AnyPublisher<Bool, Never> { get }
    var themeChanges: AnyPublisher<[EagleDockGalleryTheme], Never> { get }
    var errorChanges: AnyPublisher<String?, Never> { get }
    func load(force: Bool) async
    func prepare(_ theme: EagleDockGalleryTheme) async throws -> URL
}

nonisolated private enum Scenario: String, CaseIterable, Sendable {
    case staticPackage, livePackage, liveLateDecodeFailure, cacheHit, replaceInvalidCache, destinationIsFile
    case httpFailure, nonHTTPResponse, byteCountFailure, hashFailure, downloadFailure, cancellationError
    case invalidArchive, missingFrame, crcFailure, invalidImage, wrongDimensions
    case cacheLookupFailure, cacheCreationFailure, stagingCreationFailure
    case destinationRemovalFailure, destinationMoveFailure, cleanupFailure

    var filename: String {
        switch self {
        case .livePackage: return "live.zip"
        case .liveLateDecodeFailure: return "livePartial.zip"
        case .invalidArchive: return "invalid.zip"
        case .missingFrame: return "missing.zip"
        case .crcFailure: return "badCRC.zip"
        case .invalidImage, .cleanupFailure: return "invalidImage.zip"
        case .wrongDimensions: return "wrongWidth.zip"
        default: return "static.zip"
        }
    }

    var hasOldCache: Bool {
        switch self {
        case .cacheHit, .replaceInvalidCache, .destinationIsFile, .liveLateDecodeFailure,
             .destinationRemovalFailure, .destinationMoveFailure, .cleanupFailure: return true
        default: return false
        }
    }

    var succeeds: Bool {
        switch self {
        case .staticPackage, .livePackage, .cacheHit, .replaceInvalidCache, .destinationIsFile: return true
        default: return false
        }
    }

    var reachesStaging: Bool {
        switch self {
        case .staticPackage, .livePackage, .liveLateDecodeFailure, .replaceInvalidCache, .destinationIsFile,
             .crcFailure, .invalidImage, .wrongDimensions, .stagingCreationFailure,
             .destinationRemovalFailure, .destinationMoveFailure, .cleanupFailure: return true
        default: return false
        }
    }
}

nonisolated private final class Trace: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

@MainActor
enum FixtureLocalization {
    static let english = "The online collection could not be loaded."
    static let spanish = "No se pudo cargar la colección en línea."
    static var language = "en"
    private static var trace = Trace()

    fileprivate static func configure(language: String, trace: Trace) {
        self.language = language
        self.trace = trace
    }

    static func text(en: String, es: String) -> String {
        MainActor.preconditionIsolated()
        precondition(en == english && es == spanish, "Public catalog failure wording changed")
        trace.record("message.\(language)")
        return language == "es" ? es : en
    }
}

@MainActor
private enum CatalogFixtureContext {
    private static var replies: [(ids: [String], fails: Bool)] = []
    private static var trace = Trace()
    private static var holdNextFetch = false
    private static var heldFetch: CheckedContinuation<Void, Never>?
    private static var startWaiter: CheckedContinuation<Void, Never>?

    static func configure(replies: [(ids: [String], fails: Bool)], trace: Trace, holdNextFetch: Bool = false) {
        precondition(heldFetch == nil && startWaiter == nil)
        self.replies = replies
        self.trace = trace
        self.holdNextFetch = holdNextFetch
    }

    static func waitUntilHeld() async {
        if heldFetch != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    static func release() {
        guard let heldFetch else { preconditionFailure("Catalog fetch was not suspended") }
        self.heldFetch = nil
        heldFetch.resume()
    }

    static func fetch(_ request: URLRequest, store: any FixtureStore) async throws -> (Data, URLResponse) {
        MainActor.preconditionIsolated()
        precondition(request.url?.absoluteString == "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/dock-v1.json?catalog=21")
        precondition(request.timeoutInterval == 25 && request.httpMethod == "GET" && request.httpBody == nil)
        precondition(store.loading && store.downloadingID == nil && store.errorMessage == nil)
        let forced = request.cachePolicy == .reloadIgnoringLocalCacheData
        precondition(forced || request.cachePolicy == .returnCacheDataElseLoad)
        trace.record(forced ? "fetch.catalog.force" : "fetch.catalog.cached")
        precondition(!replies.isEmpty, "Unexpected extra catalog request")
        let reply = replies.removeFirst()
        if holdNextFetch {
            holdNextFetch = false
            await withCheckedContinuation { continuation in
                heldFetch = continuation
                startWaiter?.resume()
                startWaiter = nil
            }
        } else {
            await Task.yield()
        }
        precondition(store.loading && store.downloadingID == nil)
        if reply.fails { throw NSError(domain: "CatalogFixtureFailure", code: 992) }
        let themes = reply.ids.map { id -> [String: Any] in
            [
                "id": id, "version": 1, "title": id, "titleES": id,
                "subtitle": "Fixture", "subtitleES": "Fixture", "accent": "#20C0F0",
                "previewURL": "https://example.invalid/preview.png",
                "packageURL": "https://example.invalid/package.zip", "sha256": String(repeating: "0", count: 64),
                "byteCount": 1, "frameCount": 1, "fps": 1, "width": 1146, "height": 318,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "themes": themes], options: .sortedKeys)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}

nonisolated private final class FixtureFileManager: FileManager, @unchecked Sendable {
    let root: URL
    let scenario: Scenario
    let sentinel: NSError
    let trace: Trace

    init(root: URL, scenario: Scenario, sentinel: NSError, trace: Trace) {
        self.root = root
        self.scenario = scenario
        self.sentinel = sentinel
        self.trace = trace
        super.init()
    }

    private func check(_ url: URL) {
        precondition(url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
                     "Filesystem operation escaped its case directory")
    }

    private func label(_ url: URL) -> String {
        if url.lastPathComponent == "fixture-v1" { return "destination" }
        if url.lastPathComponent.hasPrefix(".fixture-") { return "staging" }
        if url.lastPathComponent == "Dock" { return "cache" }
        preconditionFailure("Unexpected package path")
    }

    override func url(for directory: FileManager.SearchPathDirectory,
                      in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        MainActor.preconditionIsolated()
        precondition(directory == .cachesDirectory && domain == .userDomainMask && url == nil && shouldCreate)
        trace.record("cacheURL")
        if scenario == .cacheLookupFailure { throw sentinel }
        return root
    }

    override func createDirectory(at url: URL, withIntermediateDirectories intermediate: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        MainActor.preconditionIsolated()
        check(url)
        precondition(intermediate && attributes == nil)
        let target = label(url)
        trace.record("mkdir.\(target)")
        if (target == "cache" && scenario == .cacheCreationFailure) ||
            (target == "staging" && scenario == .stagingCreationFailure) { throw sentinel }
        try super.createDirectory(at: url, withIntermediateDirectories: intermediate, attributes: attributes)
    }

    override func fileExists(atPath path: String) -> Bool {
        MainActor.preconditionIsolated()
        let url = URL(fileURLWithPath: path)
        check(url)
        trace.record("exists.\(label(url))")
        return super.fileExists(atPath: path)
    }

    override func removeItem(at url: URL) throws {
        MainActor.preconditionIsolated()
        check(url)
        let target = label(url)
        trace.record("remove.\(target)")
        if target == "staging" && scenario == .liveLateDecodeFailure {
            let paths = try super.contentsOfDirectory(atPath: url.path)
            let expected = Set((1...16).map { String(format: "frame%02d.png", $0) })
            precondition(Set(paths) == expected, "Late failure did not reach a populated staging directory")
        }
        if (target == "destination" && scenario == .destinationRemovalFailure) ||
            (target == "staging" && scenario == .cleanupFailure) { throw sentinel }
        try super.removeItem(at: url)
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        MainActor.preconditionIsolated()
        check(source)
        check(destination)
        precondition(label(source) == "staging" && label(destination) == "destination")
        trace.record("move.staging.destination")
        if scenario == .destinationMoveFailure { throw sentinel }
        try super.moveItem(at: source, to: destination)
    }
}

@MainActor
enum FixtureContext {
    private static var manager: FixtureFileManager?
    private static var scenario = Scenario.staticPackage
    private static var package = Data()
    private static var theme: EagleDockGalleryTheme?
    private static var sentinel = NSError(domain: "FixtureNotConfigured", code: 1)
    private static var trace = Trace()
    static var store: (any FixtureStore)?

    static var fileManager: FileManager {
        guard let manager else { preconditionFailure("Fixture manager not configured") }
        return manager
    }

    fileprivate static func configure(root: URL, scenario: Scenario, package: Data,
                                      theme: EagleDockGalleryTheme, sentinel: NSError, trace: Trace) {
        self.scenario = scenario
        self.package = package
        self.theme = theme
        self.sentinel = sentinel
        self.trace = trace
        self.store = nil
        manager = FixtureFileManager(root: root, scenario: scenario, sentinel: sentinel, trace: trace)
    }

    static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        MainActor.preconditionIsolated()
        if request.url?.host == "raw.githubusercontent.com" {
            guard let store else { preconditionFailure("Catalog Store fixture not configured") }
            return try await CatalogFixtureContext.fetch(request, store: store)
        }
        guard let theme, let store else { preconditionFailure("Transport fixture not configured") }
        precondition(request.url == theme.packageURL && request.url?.host == "example.invalid")
        precondition(request.timeoutInterval == 90 && request.cachePolicy == .reloadIgnoringLocalCacheData)
        precondition(request.httpMethod == "GET" && request.httpBody == nil)
        precondition(store.downloadingID == theme.id && !store.loading)
        trace.record("fetch.package")
        // Exercise real suspension while the original downloadingID/defer remains active.
        await Task.yield()
        precondition(store.downloadingID == theme.id)
        if scenario == .downloadFailure { throw sentinel }
        if scenario == .cancellationError { throw CancellationError() }
        let response: URLResponse
        if scenario == .nonHTTPResponse {
            response = URLResponse(url: theme.packageURL, mimeType: nil,
                                   expectedContentLength: package.count, textEncodingName: nil)
        } else {
            response = HTTPURLResponse(url: theme.packageURL,
                                       statusCode: scenario == .httpFailure ? 503 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        }
        return (package, response)
    }
}

private func fixtureTheme(scenario: Scenario, data: Data) -> EagleDockGalleryTheme {
    let frames = (scenario == .livePackage || scenario == .liveLateDecodeFailure) ? 17 : 1
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return EagleDockGalleryTheme(
        id: "fixture", version: 1, title: "Fixture", titleES: "Fixture",
        subtitle: "Fixture", subtitleES: "Fixture", accent: "#20C0F0",
        previewURL: URL(string: "https://example.invalid/preview.png")!, animatedPreviewURL: nil,
        packageURL: URL(string: "https://example.invalid/package.zip")!,
        sha256: scenario == .hashFailure ? String(repeating: "0", count: 64) : hash,
        byteCount: data.count + (scenario == .byteCountFailure ? 1 : 0),
        frameCount: frames, fps: frames == 17 ? 6 : 1, width: 1146, height: 318
    )
}

private struct Snapshot: Equatable {
    let events: [String]
    let stateChanges: [String]
    let frameBytes: [Data]?
    let destinationFile: Data?
    let stagingCount: Int
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
}

private func verify(root: URL, scenario: Scenario, reference: Bool,
                    png: Data, live: [Data], invalid: Data) async throws -> Snapshot {
    let fs = FileManager.default
    let directory = root.appendingPathComponent("case-\(scenario.rawValue)-\(reference)", isDirectory: true)
    precondition(directory.deletingLastPathComponent() == root)
    try fs.createDirectory(at: directory, withIntermediateDirectories: false)
    let cache = directory.appendingPathComponent("EagleGallery/Dock", isDirectory: true)
    let destination = cache.appendingPathComponent("fixture-v1", isDirectory: true)
    let package = try Data(contentsOf: root.appendingPathComponent(scenario.filename))
    let theme = fixtureTheme(scenario: scenario, data: package)
    let trace = Trace()
    let sentinel = NSError(domain: "GalleryPipelineSentinel", code: 991,
                           userInfo: ["case": scenario.rawValue])
    if scenario.hasOldCache {
        try fs.createDirectory(at: cache, withIntermediateDirectories: true)
        if scenario == .destinationIsFile {
            try invalid.write(to: destination)
        } else {
            try fs.createDirectory(at: destination, withIntermediateDirectories: false)
            for index in 1...theme.frameCount {
                try (scenario == .cacheHit ? png : invalid).write(
                    to: destination.appendingPathComponent(String(format: "frame%02d.png", index))
                )
            }
        }
    }
    FixtureContext.configure(root: directory, scenario: scenario, package: package,
                             theme: theme, sentinel: sentinel, trace: trace)
    let store: any FixtureStore = reference ? PublicDockGalleryStore() : ProductionDockGalleryStore.fixture()
    FixtureContext.store = store
    precondition(store.downloadingID == nil && !store.loading && trace.snapshot.isEmpty,
                 "Store initialization performed I/O")
    // This observer belongs only to the disposable package-file test binary.
    // Production adds no publisher subscription or Prepare/access observer.
    let stateTrace = Trace()
    let subscription = store.stateChanges.sink { value in
        MainActor.preconditionIsolated()
        stateTrace.record(value ?? "idle")
    }
    defer { subscription.cancel() }
    precondition(stateTrace.snapshot == ["idle"])
    var received: NSError?
    do {
        let result = try await store.prepare(theme)
        precondition(scenario.succeeds && result == destination && result.hasDirectoryPath)
    } catch {
        precondition(!scenario.succeeds, "Unexpected preparation failure")
        received = error as NSError
        switch scenario {
        case .downloadFailure, .cacheLookupFailure, .cacheCreationFailure, .stagingCreationFailure,
             .destinationRemovalFailure, .destinationMoveFailure:
            precondition(received === sentinel, "Original operation error identity changed")
        case .httpFailure, .nonHTTPResponse, .byteCountFailure:
            precondition((error as? URLError)?.code == .badServerResponse)
        case .hashFailure:
            precondition((error as? URLError)?.code == .secureConnectionFailed)
        case .missingFrame, .invalidImage, .wrongDimensions, .cleanupFailure, .liveLateDecodeFailure:
            precondition((error as? URLError)?.code == .cannotDecodeContentData,
                         "Cleanup replaced the original decode error")
        case .cancellationError:
            precondition(error is CancellationError)
        case .invalidArchive, .crcFailure:
            precondition(error is ZipError)
        default:
            preconditionFailure("Success scenario threw")
        }
    }
    precondition(store.downloadingID == nil && !store.loading, "Defer did not reset screen state")
    let firstEvents = trace.snapshot
    let avoidsFetch = scenario == .cacheHit || scenario == .cacheLookupFailure || scenario == .cacheCreationFailure
    precondition(stateTrace.snapshot == (avoidsFetch ? ["idle"] : ["idle", theme.id, "idle"]),
                 "Download-state publication order/count changed")
    precondition(firstEvents.filter { $0 == "fetch.package" }.count == (avoidsFetch ? 0 : 1))
    precondition(firstEvents.contains("mkdir.staging") == scenario.reachesStaging)
    precondition(firstEvents.first == "cacheURL")
    if scenario == .stagingCreationFailure {
        precondition(!firstEvents.contains("remove.staging"), "Cleanup incorrectly includes staging creation")
    }
    if [.crcFailure, .invalidImage, .wrongDimensions, .cleanupFailure, .liveLateDecodeFailure,
        .destinationRemovalFailure, .destinationMoveFailure].contains(scenario) {
        precondition(firstEvents.filter { $0 == "remove.staging" }.count == 1)
    }
    let staging = fs.fileExists(atPath: cache.path)
        ? try fs.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".fixture-") }
        : []
    precondition(staging.count == (scenario == .cleanupFailure ? 1 : 0))
    var frameBytes: [Data]?
    var destinationFile: Data?
    var isDirectory: ObjCBool = false
    if fs.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
        if isDirectory.boolValue {
            frameBytes = try (1...theme.frameCount).map {
                try Data(contentsOf: destination.appendingPathComponent(String(format: "frame%02d.png", $0)))
            }
        } else {
            destinationFile = try Data(contentsOf: destination)
        }
    }
    if scenario.succeeds {
        let expected = scenario == .livePackage ? live : [png]
        precondition(frameBytes == expected && destinationFile == nil, "Frame bytes or order changed")
        let before = trace.snapshot
        let stateBefore = stateTrace.snapshot
        let second = try await store.prepare(theme)
        precondition(second == destination && store.downloadingID == nil)
        precondition(Array(trace.snapshot.dropFirst(before.count)) == ["cacheURL", "mkdir.cache"],
                     "Valid cache was downloaded, staged or replaced again")
        precondition(stateTrace.snapshot == stateBefore, "Cache hit unnecessarily published download state")
    } else if scenario == .destinationRemovalFailure || scenario == .cleanupFailure || scenario == .liveLateDecodeFailure {
        precondition(frameBytes == Array(repeating: invalid, count: theme.frameCount), "Failure changed retained old cache")
    } else {
        precondition(frameBytes == nil && destinationFile == nil, "Failed flow produced a destination")
    }
    FixtureContext.store = nil
    return Snapshot(events: trace.snapshot, stateChanges: stateTrace.snapshot,
                    frameBytes: frameBytes, destinationFile: destinationFile,
                    stagingCount: staging.count, errorDomain: received?.domain, errorCode: received?.code,
                    errorDescription: (scenario == .invalidArchive || scenario == .crcFailure) ? received?.localizedDescription : nil)
}

nonisolated private enum CatalogScenario: String, CaseIterable, Sendable {
    case initialLoad, cachedSkip, forcedReload, inflightSkip, retainedThemesFailure
    case recovery, englishFailure, spanishFailure, lateLocaleFailure
}

private struct CatalogSnapshot: Equatable {
    let operations: [String]
    let publications: [String]
    let themes: [EagleDockGalleryTheme]
    let errorMessage: String?
}

private func successPublications(_ ids: [String]) -> [String] {
    ["loading.on", "error.nil", "themes.\(ids.joined(separator: ","))", "loading.off"]
}

private func failurePublications(_ message: String) -> [String] {
    ["loading.on", "error.nil", "error.\(message)", "loading.off"]
}

private func verifyCatalog(scenario: CatalogScenario, reference: Bool) async -> CatalogSnapshot {
    let trace = Trace()
    let spanish = scenario == .spanishFailure || scenario == .lateLocaleFailure
    FixtureLocalization.configure(language: scenario == .spanishFailure ? "es" : "en", trace: trace)
    let replies: [(ids: [String], fails: Bool)]
    switch scenario {
    case .forcedReload: replies = [(["alpha"], false), (["beta", "gamma"], false)]
    case .retainedThemesFailure: replies = [(["alpha"], false), ([], true)]
    case .recovery: replies = [([], true), (["beta"], false)]
    case .englishFailure, .spanishFailure, .lateLocaleFailure: replies = [([], true)]
    default: replies = [(["alpha"], false)]
    }
    CatalogFixtureContext.configure(replies: replies, trace: trace, holdNextFetch: scenario == .inflightSkip)
    // This factory injects fixture services into the unmodified owned Store.
    // Initialization must not evaluate either the language closure or transport.
    let store: any FixtureStore = reference ? PublicDockGalleryStore() : ProductionDockGalleryStore.fixture()
    precondition(store.themes.isEmpty && !store.loading && store.errorMessage == nil && store.downloadingID == nil)
    precondition(trace.snapshot.isEmpty, "Store initialization eagerly evaluated localization or I/O")
    FixtureContext.store = store
    let stateTrace = Trace()
    let subscriptions = [
        store.loadingChanges.sink {
            MainActor.preconditionIsolated()
            stateTrace.record($0 ? "loading.on" : "loading.off")
        },
        store.themeChanges.sink {
            MainActor.preconditionIsolated()
            stateTrace.record("themes.\($0.map(\.id).joined(separator: ","))")
        },
        store.errorChanges.sink {
            MainActor.preconditionIsolated()
            stateTrace.record("error.\($0 ?? "nil")")
        },
    ]
    defer { subscriptions.forEach { $0.cancel() } }
    let initial = ["loading.off", "themes.", "error.nil"]
    precondition(stateTrace.snapshot == initial)
    let message = spanish ? FixtureLocalization.spanish : FixtureLocalization.english
    var expectedPublications = initial
    var expectedOperations: [String] = []
    var expectedThemes: [String] = []
    var expectedError: String?
    switch scenario {
    case .initialLoad, .cachedSkip:
        await store.load(force: false)
        expectedPublications += successPublications(["alpha"])
        expectedOperations = ["fetch.catalog.cached"]
        expectedThemes = ["alpha"]
        if scenario == .cachedSkip {
            await store.load(force: false)
            precondition(stateTrace.snapshot == expectedPublications && trace.snapshot == expectedOperations,
                         "Cached catalog skip published state or performed transport")
        }
    case .forcedReload:
        await store.load(force: false)
        await store.load(force: true)
        expectedPublications += successPublications(["alpha"]) + successPublications(["beta", "gamma"])
        expectedOperations = ["fetch.catalog.cached", "fetch.catalog.force"]
        expectedThemes = ["beta", "gamma"]
    case .inflightSkip:
        let pending = Task { @MainActor in await store.load(force: false) }
        await CatalogFixtureContext.waitUntilHeld()
        let loadingEvents = initial + ["loading.on", "error.nil"]
        precondition(store.loading && stateTrace.snapshot == loadingEvents)
        await store.load(force: false)
        await store.load(force: true)
        precondition(stateTrace.snapshot == loadingEvents && trace.snapshot == ["fetch.catalog.cached"],
                     "Concurrent cached/forced load was not skipped during the original suspended fetch")
        CatalogFixtureContext.release()
        await pending.value
        expectedPublications += successPublications(["alpha"])
        expectedOperations = ["fetch.catalog.cached"]
        expectedThemes = ["alpha"]
    case .retainedThemesFailure:
        await store.load(force: false)
        await store.load(force: true)
        expectedPublications += successPublications(["alpha"]) + failurePublications(message)
        expectedOperations = ["fetch.catalog.cached", "fetch.catalog.force", "message.en"]
        expectedThemes = ["alpha"]
        expectedError = message
        await store.load(force: false)
        precondition(stateTrace.snapshot == expectedPublications && trace.snapshot == expectedOperations,
                     "Cached catalog skip erased an existing error or reloaded retained themes")
    case .recovery:
        await store.load(force: false)
        await store.load(force: false)
        expectedPublications += failurePublications(message) + successPublications(["beta"])
        expectedOperations = ["fetch.catalog.cached", "message.en", "fetch.catalog.cached"]
        expectedThemes = ["beta"]
    case .englishFailure, .spanishFailure, .lateLocaleFailure:
        if scenario == .lateLocaleFailure { FixtureLocalization.language = "es" }
        await store.load(force: false)
        expectedPublications += failurePublications(message)
        expectedOperations = ["fetch.catalog.cached", spanish ? "message.es" : "message.en"]
        expectedError = message
    }
    precondition(stateTrace.snapshot == expectedPublications, "Catalog publication order/count differs for \(scenario.rawValue)")
    precondition(trace.snapshot == expectedOperations, "Catalog transport/localization order differs for \(scenario.rawValue)")
    precondition(store.themes.map(\.id) == expectedThemes && store.errorMessage == expectedError)
    precondition(!store.loading && store.downloadingID == nil, "Catalog completion changed download state or failed to reset loading")
    FixtureContext.store = nil
    return CatalogSnapshot(operations: trace.snapshot, publications: stateTrace.snapshot,
                           themes: store.themes, errorMessage: store.errorMessage)
}

@main
private enum EagleDockStorePipelineContract {
    static func main() async throws {
        MainActor.preconditionIsolated()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        precondition(root.lastPathComponent.hasPrefix("eagle-dock-store-pipeline-"))
        let png = try Data(contentsOf: root.appendingPathComponent("valid.png"))
        let invalid = try Data(contentsOf: root.appendingPathComponent("invalid.bin"))
        let live = try (1...17).map {
            try Data(contentsOf: root.appendingPathComponent(String(format: "live-frame%02d.png", $0)))
        }
        precondition(Set(live).count == 17, "Live frames are not distinguishable")
        let image = UIImage(data: png)!
        precondition(image.cgImage?.width == 1146 && image.cgImage?.height == 318)
        var cases = 0
        for scenario in Scenario.allCases {
            let original = try await verify(root: root, scenario: scenario, reference: true, png: png, live: live, invalid: invalid)
            let actual = try await verify(root: root, scenario: scenario, reference: false, png: png, live: live, invalid: invalid)
            precondition(original == actual, "Public/Core integrated flow differs for \(scenario.rawValue)")
            cases += 1
        }
        print("PASS: \(cases) integrated public/production Store scenarios with real UIKit/ZIP/cache files, exact results/operation traces/errors/state reset and second-use cache hits; no network or native engine")
        var catalogCases = 0
        for scenario in CatalogScenario.allCases {
            let original = await verifyCatalog(scenario: scenario, reference: true)
            let actual = await verifyCatalog(scenario: scenario, reference: false)
            precondition(original == actual, "Public/owned Store catalog flow differs for \(scenario.rawValue)")
            catalogCases += 1
        }
        print("PASS: \(catalogCases) public/unmodified owned Store catalog scenarios: cached/forced/in-flight guards, retained themes, recovery, exact published state order, lazy localization and both original locale messages; no network")
    }
}
