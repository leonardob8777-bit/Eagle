import Foundation

private func theme(_ id: String, live: Bool = false, supported: Bool = true) -> [String: Any] {
    ["id": id, "version": 3, "title": id, "titleES": "Título \(id)",
     "subtitle": "Subtitle", "subtitleES": "Descripción", "accent": "#123456",
     "previewURL": "https://example.invalid/preview.png", "packageURL": "https://example.invalid/package.zip",
     "sha256": "arbitrary", "byteCount": 1024, "frameCount": live ? 17 : 1,
     "fps": live ? 6 : 1, "width": supported ? 1146 : 0, "height": 318]
}

private func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
}

private func catalog(_ themes: [Any], schema: Int = 1) throws -> Data {
    try json(["schemaVersion": schema, "themes": themes])
}

private func response(_ status: Int?) -> URLResponse {
    let url = URL(string: "https://example.invalid/response")!
    if let status { return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["X-Test": "same"])! }
    return URLResponse(url: url, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)
}

private func failure(_ error: Error) -> String {
    let ns = error as NSError
    var details = "\(ns.domain):\(ns.code)"
    let context: DecodingError.Context?
    switch error {
    case DecodingError.keyNotFound(let key, let value): details += ":missing:\(key.stringValue)"; context = value
    case DecodingError.typeMismatch(let type, let value): details += ":type:\(type)"; context = value
    case DecodingError.valueNotFound(let type, let value): details += ":null:\(type)"; context = value
    case DecodingError.dataCorrupted(let value): details += ":corrupt"; context = value
    default: context = nil
    }
    if let context {
        details += ":\(context.codingPath.map { $0.stringValue }):\(context.debugDescription)"
    }
    return details.replacingOccurrences(of: "PublicDockGalleryCatalog", with: "Catalog")
        .replacingOccurrences(of: "EagleDockGalleryCatalog", with: "Catalog")
}

private enum Outcome: Equatable {
    case themes([EagleDockGalleryTheme])
    case error(String)
}

private final class Spy {
    var requests: [URLRequest] = []
    var events: [String] = []
    var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    var completed = false

    func record(_ request: URLRequest) {
        MainActor.preconditionIsolated()
        requests.append(request)
        events.append("fetch")
    }
}

private func validateRequest(_ request: URLRequest, force: Bool) {
    precondition(request.url?.absoluteString == "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/dock-v1.json?catalog=21")
    precondition(request.timeoutInterval == 25)
    precondition(request.cachePolicy == (force ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad))
    precondition(request.httpMethod == "GET" && request.allHTTPHeaderFields == nil)
    precondition(request.httpBody == nil && request.httpBodyStream == nil)
    precondition(request.mainDocumentURL == nil && request.networkServiceType == .default)
    precondition(request.allowsCellularAccess && request.allowsExpensiveNetworkAccess && request.allowsConstrainedNetworkAccess)
    precondition(request.httpShouldHandleCookies)
}

private func run(reference: Bool, force: Bool?, fetch: @escaping EagleDockGalleryCatalogLoader.Fetch) async -> Outcome {
    do {
        let selected: [EagleDockGalleryTheme]
        if reference { selected = try await publicDockCatalogLoad(force: force ?? false, fetch: fetch) }
        else {
            let loader = EagleDockGalleryCatalogLoader(fetch: fetch)
            if let force { selected = try await loader.load(force: force) }
            else { selected = try await loader.load() }
        }
        return .themes(selected)
    } catch { return .error(failure(error)) }
}

@main
private enum CatalogLoaderContract {
    static func main() async throws {
        let valid = try catalog([theme("still"), theme("unsupported", supported: false), theme("live", live: true), theme("still")])
        let empty = try catalog([])
        let unsupported = try catalog([theme("none", supported: false)])
        let schema = try catalog([theme("still")], schema: 2)
        let malformed = Data("{no".utf8)
        let malformedTheme = try catalog([["id": "incomplete"]], schema: 2)
        let limit = 512 * 1024
        let boundary = valid + Data(repeating: 0x20, count: limit - valid.count)
        let overLimit = boundary + Data([0x20])
        var cases = 0
        for force: Bool? in [nil, false, true] {
            for data in [valid, empty, unsupported, schema, malformed, malformedTheme, boundary, overLimit] {
                for status: Int? in [nil, 199, 200, 204, 299, 300, 500] {
                    let oldSpy = Spy(), newSpy = Spy()
                    let old = await run(reference: true, force: force) { request in
                        oldSpy.record(request); return (data, response(status))
                    }
                    let actual = await run(reference: false, force: force) { request in
                        newSpy.record(request); return (data, response(status))
                    }
                    precondition(old == actual, "Async catalog mismatch: force=\(String(describing: force)), status=\(String(describing: status))")
                    precondition(oldSpy.requests.count == 1 && newSpy.requests == oldSpy.requests)
                    validateRequest(newSpy.requests[0], force: force ?? false)
                    if status == nil || !(200..<300).contains(status!) || data.count > limit {
                        precondition(actual == .error(failure(URLError(.badServerResponse))), "Response validation must precede decoding")
                    }
                    if data == valid && status == 200, case .themes(let themes) = actual {
                        precondition(themes.map(\.id) == ["still", "live", "still"])
                    }
                    cases += 1
                }
            }
        }

        for error: Error in [URLError(.notConnectedToInternet), URLError(.cancelled), CancellationError(), NSError(domain: "TransportSentinel", code: 778, userInfo: ["payload": "retained"])] {
            for reference in [false, true] {
                let spy = Spy()
                let fetch: EagleDockGalleryCatalogLoader.Fetch = { request in spy.record(request); throw error }
                do {
                    if reference { _ = try await publicDockCatalogLoad(fetch: fetch) }
                    else { _ = try await EagleDockGalleryCatalogLoader(fetch: fetch).load() }
                    preconditionFailure("Transport error swallowed")
                } catch let caught {
                    precondition(failure(caught) == failure(error))
                    let original = error as NSError
                    if original.domain == "TransportSentinel" {
                        precondition(caught as NSError === original, "Transport error was replaced")
                    }
                }
                precondition(spy.requests.count == 1)
                cases += 1
            }
        }

        for reference in [false, true] {
            for cancelMode in 0...2 {
                let spy = Spy()
                let task = Task { @MainActor in
                    let outcome = await run(reference: reference, force: true) { request in
                        spy.record(request)
                        return try await withCheckedThrowingContinuation { spy.continuation = $0 }
                    }
                    spy.completed = true; spy.events.append("completed")
                    return outcome
                }
                for _ in 0..<1000 {
                    if spy.continuation != nil { break }
                    await Task.yield()
                }
                precondition(spy.continuation != nil && !spy.completed && spy.events == ["fetch"])
                precondition(spy.requests.count == 1)
                validateRequest(spy.requests[0], force: true)
                if cancelMode == 1 {
                    task.cancel()
                    spy.continuation!.resume(throwing: CancellationError())
                } else {
                    if cancelMode == 2 { task.cancel() }
                    spy.continuation!.resume(returning: (valid, response(200)))
                }
                spy.continuation = nil
                let result = await task.value
                precondition(spy.completed && spy.events == ["fetch", "completed"] && spy.requests.count == 1)
                if cancelMode == 1 { precondition(result == .error(failure(CancellationError()))) }
                else if case .themes(let selected) = result { precondition(selected.map(\.id) == ["still", "live", "still"]) }
                else { preconditionFailure("Suspended successful response rejected") }
                cases += 1
            }
        }
        print("PASS: \(cases) async loader cases; exact request, public result/error parity, one fetch, MainActor, suspension and cancellation")
    }
}
