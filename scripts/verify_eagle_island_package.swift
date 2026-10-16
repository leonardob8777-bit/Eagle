import Foundation
import CryptoKit

nonisolated final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return values }
}

nonisolated final class TestFiles: FileManager {
    let root: URL
    let scenario: String
    let events: Events
    init(root: URL, scenario: String, events: Events) {
        self.root = root; self.scenario = scenario; self.events = events; super.init()
    }
    override func url(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        precondition(directory == .cachesDirectory && domain == .userDomainMask && url == nil && shouldCreate)
        events.append("root")
        if scenario == "root-fails" { throw CocoaError(.fileReadNoPermission) }
        return root
    }
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        let stage = url.lastPathComponent.hasPrefix(".island-")
        events.append(stage ? "mkdir.stage" : "mkdir.root")
        if scenario == "mkdir-fails" || (stage && scenario == "stage-fails") { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    override func removeItem(at url: URL) throws {
        events.append(url.lastPathComponent.hasPrefix(".island-") ? "remove.stage" : "remove.\(url.lastPathComponent)")
        try super.removeItem(at: url)
    }
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        events.append("move.stage")
        if scenario == "move-fails" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

nonisolated struct Result: Equatable {
    let value: String
    let events: [String]
    let files: [String: String]
}

@main struct Checks {
    nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func fileURLs(_ root: URL) -> [URL] {
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])!.allObjects.compactMap { $0 as? URL }
    }
    nonisolated static func exercise(root: URL, fixture: URL, scenario: String, supplied: Bool, owned: Bool) async throws -> Result {
        let fm = FileManager.default
        let events = Events()
        let cache = root.appendingPathComponent("EagleGallery/Island", isDirectory: true)
        let destination = cache.appendingPathComponent("singularity-live-v1", isDirectory: true)
        let saved = cache.appendingPathComponent("singularity-live-v1.json")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let fixtureManifest = try Data(contentsOf: fixture.appendingPathComponent("manifest.json"))
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("theme.json"))) as! [String: Any]
        if scenario == "bad-hash" { object["sha256"] = String(repeating: "0", count: 64) }
        if scenario == "bad-size" { object["byteCount"] = (object["byteCount"] as! Int) + 1 }
        if scenario == "unsupported" { object["fps"] = 7 }
        if scenario == "wrong-id" { object["id"] = "blue-flame" }
        let theme = try JSONDecoder().decode(EagleIslandGalleryTheme.self, from: JSONSerialization.data(withJSONObject: object))
        let encoded = try JSONEncoder().encode(theme.manifest)
        var responseData = encoded
        if scenario == "malformed" { responseData = Data("bad JSON".utf8) }
        if scenario == "manifest-limit" { responseData.append(Data(repeating: 32, count: 32 * 1024 - responseData.count)) }
        if scenario == "manifest-oversize" { responseData.append(Data(repeating: 32, count: 32 * 1024 + 1 - responseData.count)) }
        if ["offline", "http-manifest", "nonhttp-manifest", "manifest-oversize"].contains(scenario) { try fixtureManifest.write(to: saved) }
        if scenario == "bad-cache" { try Data("bad".utf8).write(to: saved) }
        if scenario == "save-fails" { try fm.createDirectory(at: saved, withIntermediateDirectories: false) }
        if ["cache-hit", "cache-corrupt", "cache-missing", "cache-empty", "cache-huge", "replace", "move-fails"].contains(scenario) {
            try fm.copyItem(at: fixture.appendingPathComponent("frames"), to: destination)
            let first = destination.appendingPathComponent("frame01.png")
            switch scenario {
            case "cache-hit": break
            case "cache-missing": try fm.removeItem(at: first)
            case "cache-empty": try Data().write(to: first)
            case "cache-huge": try Data(repeating: 0, count: 2 * 1024 * 1024 + 1).write(to: first)
            default: try Data("old".utf8).write(to: first)
            }
        }
        let oldDestination = try? Data(contentsOf: destination.appendingPathComponent("frame01.png"))
        let files: @Sendable () -> FileManager = { TestFiles(root: root, scenario: scenario, events: events) }
        let manifestResponse = responseData
        let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            events.append("fetch")
            precondition(request.timeoutInterval == 20 && request.cachePolicy == .useProtocolCachePolicy)
            precondition(request.url!.lastPathComponent == "island-live-v1.json")
            if ["offline", "no-cache", "bad-cache"].contains(scenario) { throw URLError(.notConnectedToInternet) }
            if scenario == "cancel-manifest" { throw CancellationError() }
            if scenario == "nonhttp-manifest" { return (manifestResponse, URLResponse(url: request.url!, mimeType: nil, expectedContentLength: manifestResponse.count, textEncodingName: nil)) }
            return (manifestResponse, HTTPURLResponse(url: request.url!, statusCode: scenario == "http-manifest" ? 500 : 200, httpVersion: nil, headerFields: nil)!)
        }
        let download: @Sendable (URLRequest) async throws -> (URL, URLResponse) = { request in
            events.append("download")
            precondition(request.timeoutInterval == 90 && request.cachePolicy == .reloadIgnoringLocalCacheData)
            precondition(request.url == theme.manifest.packageURL)
            if scenario == "download-fails" { throw URLError(.notConnectedToInternet) }
            let file = root.appendingPathComponent("download.zip")
            try FileManager.default.copyItem(at: fixture.appendingPathComponent("package.zip"), to: file)
            if scenario == "cancel-download" { withUnsafeCurrentTask { $0?.cancel() } }
            if scenario == "nonhttp-download" { return (file, URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)) }
            return (file, HTTPURLResponse(url: request.url!, statusCode: scenario == "http-download" ? 404 : 200, httpVersion: nil, headerFields: nil)!)
        }
        let value: String
        do {
            let url: URL
            if owned {
                url = try await EagleIslandGalleryPackage.prepare(theme: supplied ? theme : nil, fileManager: files,
                                                                  fetch: fetch, downloadPackage: download, log: { _ in })
            } else {
                url = try await PublicPackage.prepare(theme: supplied ? theme : nil, fileManager: files,
                                                     fetch: fetch, downloadPackage: download, log: { _ in })
            }
            value = "ok:\(url.lastPathComponent)"
            precondition(url == destination)
        } catch {
            let error = error as NSError
            value = "error:\(error.domain):\(error.code)"
        }
        var snapshot: [String: String] = [:]
        for file in fileURLs(root) {
            let relative = String(file.path.dropFirst(root.path.count + 1))
            if (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { snapshot[relative] = "directory" }
            else {
                let data = try Data(contentsOf: file)
                if file == saved, let json = try? JSONSerialization.jsonObject(with: data),
                   let normalized = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) {
                    snapshot[relative] = digest(normalized)
                } else { snapshot[relative] = digest(data) }
            }
        }
        precondition(!snapshot.keys.contains { $0.contains(".island-") || $0 == "download.zip" }, "Temporary files leaked")
        if scenario == "cache-hit" {
            precondition(value.hasPrefix("ok:") && !events.snapshot.contains("download"))
            precondition(!fm.fileExists(atPath: saved.path), "Fast path must not newly save manifest")
        }
        if fixture.lastPathComponent == "valid" && scenario == "normal" {
            precondition(value.hasPrefix("ok:"))
            precondition((try? Data(contentsOf: destination.appendingPathComponent("frame17.png"))) != nil)
            precondition(fm.fileExists(atPath: saved.path))
        }
        if scenario == "bad-hash" || scenario == "http-download" || scenario == "bad-size" {
            precondition(value.hasPrefix("error:") && !events.snapshot.contains("mkdir.stage"))
            precondition((try? Data(contentsOf: destination.appendingPathComponent("frame01.png"))) == oldDestination)
        }
        if scenario == "cancel-download" { precondition(value.hasPrefix("error:") && !events.snapshot.contains("mkdir.stage")) }
        if scenario == "save-fails" {
            precondition(value.hasPrefix("error:") && fm.fileExists(atPath: destination.appendingPathComponent("frame17.png").path))
        }
        return Result(value: value, events: events.snapshot, files: snapshot)
    }

    static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let runRoot = FileManager.default.temporaryDirectory.appendingPathComponent("eagle-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runRoot) }
        let variants = ["valid", "deflated", "missing", "extra", "path", "directory", "empty", "huge", "badpng", "dimensions", "framehash", "badzip"]
        let scenarios = ["normal", "cache-hit", "cache-corrupt", "cache-missing", "cache-empty", "cache-huge", "replace",
                         "root-fails", "mkdir-fails", "stage-fails", "move-fails", "save-fails", "unsupported", "bad-hash", "bad-size",
                         "download-fails", "http-download", "nonhttp-download", "cancel-download"]
        var cases = 0
        func check(_ variant: String, _ scenario: String, _ supplied: Bool) async throws {
            let caseRoot = runRoot.appendingPathComponent("case-\(cases)")
            let a = try await exercise(root: caseRoot.appendingPathComponent("public"), fixture: fixtures.appendingPathComponent(variant), scenario: scenario, supplied: supplied, owned: false)
            let b = try await exercise(root: caseRoot.appendingPathComponent("owned"), fixture: fixtures.appendingPathComponent(variant), scenario: scenario, supplied: supplied, owned: true)
            precondition(a == b, "Parity: \(variant)/\(scenario)/\(supplied)\n\(a)\n\(b)")
            try FileManager.default.removeItem(at: caseRoot)
            cases += 1
        }
        for supplied in [false, true] {
            for scenario in scenarios { try await check("valid", scenario, supplied) }
            for variant in variants.dropFirst() { try await check(variant, "normal", supplied) }
        }
        for scenario in ["offline", "no-cache", "bad-cache", "http-manifest", "nonhttp-manifest", "manifest-limit", "manifest-oversize", "malformed", "wrong-id", "cancel-manifest"] {
            try await check("valid", scenario, false)
        }
        print("PASS: \(cases) public/owned package scenarios with actual UIKit, CryptoKit, ZIP and temporary filesystem")
        print("PASS: manifest/network/cache paths, 17-frame validation, stored/deflated archives, corrupt inputs, cleanup, worker cancellation and failure ordering; no live network or native applying")
    }
}
