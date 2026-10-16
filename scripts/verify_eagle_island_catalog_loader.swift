import Foundation

nonisolated final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; stored.append(value) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}

nonisolated final class TestFiles: FileManager, @unchecked Sendable {
    let root: URL
    let failure: Int
    let events: Events
    init(root: URL, failure: Int, events: Events) {
        self.root = root; self.failure = failure; self.events = events; super.init()
    }
    override func url(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        precondition(directory == .cachesDirectory && domain == .userDomainMask && url == nil && shouldCreate)
        events.append("root")
        if failure == 1 { throw CocoaError(.fileReadNoPermission) }
        return root
    }
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        precondition(url == root.appendingPathComponent("EagleGallery/Island", isDirectory: true))
        precondition(createIntermediates && attributes == nil)
        events.append("mkdir")
        if failure == 2 { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

nonisolated struct Result: Equatable {
    let value: String
    let events: [String]
    let saved: Data?
    let directory: Bool
}

@main struct Checks {
    nonisolated static func exercise(root: URL, owned: Bool, force: Bool, failure: Int, network: Int,
                                    cache: Int, a: Data, b: Data) async throws -> Result {
        let fm = FileManager.default
        let events = Events()
        let folder = root.appendingPathComponent("EagleGallery/Island", isDirectory: true)
        let saved = folder.appendingPathComponent("island-gallery-v1.json")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var exact = a
        exact.append(Data(repeating: 32, count: 2 * 1024 * 1024 - a.count))
        var oversize = exact; oversize.append(32)
        let invalid = Data("{bad".utf8)
        let unsupported = Data("{\"schemaVersion\":2,\"themes\":[]}".utf8)
        switch cache {
        case 1: try a.write(to: saved)
        case 2: try b.write(to: saved)
        case 3: try exact.write(to: saved)
        case 4: try oversize.write(to: saved)
        case 5: try invalid.write(to: saved)
        case 6: try unsupported.write(to: saved)
        case 7: try fm.createDirectory(at: saved, withIntermediateDirectories: false)
        default: break
        }
        let oldSaved = try? Data(contentsOf: saved)
        let files = TestFiles(root: root, failure: failure, events: events)
        let exactData = exact, oversizedData = oversize
        let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            events.append("fetch")
            precondition(request.url?.absoluteString == "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/island-gallery-v1.json")
            precondition(request.timeoutInterval == 25 && request.httpMethod == "GET")
            precondition(request.cachePolicy == (force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy))
            precondition(request.httpBody == nil)
            if network == 9 { throw URLError(.notConnectedToInternet) }
            if network == 10 { throw CancellationError() }
            let data: Data
            switch network {
            case 1: data = b
            case 2: data = exactData
            case 3: data = oversizedData
            case 4: data = invalid
            case 5: data = unsupported
            default: data = a
            }
            if network == 6 {
                return (data, URLResponse(url: request.url!, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: nil))
            }
            let status = network == 7 ? 404 : network == 8 ? 500 : 200
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let value: String
        do {
            let themes: [EagleIslandGalleryTheme]
            if owned {
                themes = try await EagleIslandGalleryCatalogLoader.loadCatalog(force: force, fileManager: files, fetch: fetch)
            } else {
                themes = try await PublicLoader.loadCatalog(force: force, fileManager: files, fetch: fetch)
            }
            value = "ok:" + themes.map { "\($0.id)|\($0.title)|\($0.manifest.sha256)" }.joined(separator: ",")
        } catch {
            let error = error as NSError
            value = "error:\(error.domain):\(error.code)"
        }
        let after = try? Data(contentsOf: saved)
        var isDirectory: ObjCBool = false
        _ = fm.fileExists(atPath: saved.path, isDirectory: &isDirectory)
        if failure > 0 {
            precondition(events.values == (failure == 1 ? ["root"] : ["root", "mkdir"]))
            precondition(value.hasPrefix("error:") && after == oldSaved)
        } else {
            precondition(events.values == ["root", "mkdir", "fetch"])
            if network <= 2 && cache != 7 {
                precondition(value.hasPrefix("ok:"))
                precondition(after == (network == 0 ? a : network == 1 ? b : exactData))
            } else {
                precondition(after == oldSaved)
                if (1...3).contains(cache) {
                    precondition(value.hasPrefix("ok:"))
                } else { precondition(value.hasPrefix("error:")) }
            }
        }
        return Result(value: value, events: events.values, saved: after, directory: isDirectory.boolValue)
    }

    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let a = try Data(contentsOf: root.appendingPathComponent("a.json"))
        let b = try Data(contentsOf: root.appendingPathComponent("b.json"))
        var count = 0
        for force in [false, true] {
            for failure in 0...2 {
                for cache in 0...7 {
                    for network in 0...10 {
                        let caseRoot = root.appendingPathComponent("case-\(count)", isDirectory: true)
                        let old = try await exercise(root: caseRoot.appendingPathComponent("public"), owned: false,
                                                     force: force, failure: failure, network: network, cache: cache, a: a, b: b)
                        let new = try await exercise(root: caseRoot.appendingPathComponent("owned"), owned: true,
                                                     force: force, failure: failure, network: network, cache: cache, a: a, b: b)
                        precondition(old == new, "Parity failure \(force)/\(failure)/\(cache)/\(network)")
                        // Only this temporary fixture's known case directory is removed.
                        try FileManager.default.removeItem(at: caseRoot)
                        count += 1
                    }
                }
            }
        }
        print("PASS: \(count) public/owned catalog cases with real temporary disk and injected transport")
        print("PASS: exact request/force policy, setup errors before fetch, HTTP/body/size validation, atomic save and disk fallback, injected cancellation and unchanged cache on failure")
        print("PASS: result/error domain+code, ordered setup/fetch events and final cache bytes agree; no live network/native/app execution")
    }
}
