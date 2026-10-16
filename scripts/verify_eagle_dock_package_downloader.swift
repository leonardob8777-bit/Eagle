import Foundation
import CryptoKit

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func theme(count: Int, hash: String, url: URL, supported: Bool = true) -> EagleDockGalleryTheme {
    EagleDockGalleryTheme(
        id: "fixture", version: 3, title: "Fixture", titleES: "Ejemplo",
        subtitle: "Package", subtitleES: "Paquete", accent: "#123456",
        previewURL: URL(string: "https://example.invalid/preview.png")!, animatedPreviewURL: nil,
        packageURL: url, sha256: hash, byteCount: count,
        frameCount: supported ? 1 : 0, fps: 1, width: supported ? 1146 : 0, height: 318
    )
}

private func response(_ status: Int?) -> URLResponse {
    let url = URL(string: "https://example.invalid/response")!
    if let status {
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["X-Test": "same"])!
    }
    return URLResponse(url: url, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)
}

private func failure(_ error: Error) -> String {
    let ns = error as NSError
    return "\(ns.domain):\(ns.code)"
}

private enum Outcome: Equatable {
    case data(Data)
    case error(String)
}

@MainActor
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

private func validateRequest(_ request: URLRequest, theme: EagleDockGalleryTheme) {
    var expected = URLRequest(url: theme.packageURL)
    expected.timeoutInterval = 90
    expected.cachePolicy = .reloadIgnoringLocalCacheData
    precondition(request == expected, "The package URL or request defaults changed")
    precondition(request.url == theme.packageURL && request.timeoutInterval == 90)
    precondition(request.cachePolicy == .reloadIgnoringLocalCacheData)
    precondition(request.httpMethod == "GET" && request.allHTTPHeaderFields == nil)
    precondition(request.httpBody == nil && request.httpBodyStream == nil)
    precondition(request.mainDocumentURL == nil && request.networkServiceType == .default)
    precondition(request.allowsCellularAccess && request.allowsExpensiveNetworkAccess && request.allowsConstrainedNetworkAccess)
    precondition(request.httpShouldHandleCookies)
}

private func download(reference: Bool, theme: EagleDockGalleryTheme, fetch: @escaping EagleDockGalleryPackageDownloader.Fetch) async throws -> Data {
    if reference { return try await publicDockPackageDownload(theme, fetch: fetch) }
    return try await EagleDockGalleryPackageDownloader(fetch: fetch).download(theme)
}

private func run(reference: Bool, theme: EagleDockGalleryTheme, fetch: @escaping EagleDockGalleryPackageDownloader.Fetch) async -> Outcome {
    do { return .data(try await download(reference: reference, theme: theme, fetch: fetch)) }
    catch { return .error(failure(error)) }
}

private func verify(
    _ data: Data, status: Int?, count: Int? = nil, hash: String? = nil,
    error: URLError.Code? = nil, supported: Bool = true,
    url: URL = URL(string: "https://example.invalid/dock.zip?version=3#package")!
) async -> Int {
    let fixture = theme(count: count ?? data.count, hash: hash ?? digest(data), url: url, supported: supported)
    let oldSpy = Spy(), newSpy = Spy()
    let old = await run(reference: true, theme: fixture) { request in
        oldSpy.record(request); return (data, response(status))
    }
    let actual = await run(reference: false, theme: fixture) { request in
        newSpy.record(request); return (data, response(status))
    }
    let expected: Outcome = error.map { .error(failure(URLError($0))) } ?? .data(data)
    precondition(old == actual && actual == expected, "Public async result/error parity changed")
    precondition(oldSpy.requests.count == 1 && newSpy.requests == oldSpy.requests)
    precondition(oldSpy.events == ["fetch"] && newSpy.events == ["fetch"])
    validateRequest(newSpy.requests[0], theme: fixture)
    return 1
}

@main
private enum PackageDownloaderContract {
    static func main() async throws {
        MainActor.preconditionIsolated()
        let empty = Data(), abc = Data("abc".utf8)
        let binary = Data((0...255).map { UInt8($0) })
        let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        precondition(digest(empty) == emptyHash && digest(abc) == abcHash)
        var cases = 0
        cases += await verify(binary, status: 200)
        cases += await verify(abc, status: 299, hash: abcHash.uppercased(), url: URL(string: "http://example.invalid/other-package?x=1&x=2")!)
        cases += await verify(empty, status: 204, hash: emptyHash)
        cases += await verify(abc, status: 206, supported: false)
        cases += await verify(abc, status: nil, count: 4, hash: "bad", error: .badServerResponse)
        cases += await verify(abc, status: 199, error: .badServerResponse)
        cases += await verify(abc, status: 300, error: .badServerResponse)
        cases += await verify(abc, status: 500, hash: "bad", error: .badServerResponse)
        cases += await verify(abc, status: 200, count: 4, hash: "bad", error: .badServerResponse)
        cases += await verify(abc, status: 200, count: -1, error: .badServerResponse)
        cases += await verify(abc, status: 200, hash: "bad", error: .secureConnectionFailed)
        cases += await verify(abc, status: 200, hash: abcHash + "\n", error: .secureConnectionFailed)
        let limit = 30 * 1024 * 1024
        let atLimit = Data(repeating: 0x6D, count: limit)
        cases += await verify(atLimit, status: 200)
        cases += await verify(atLimit + Data([0x6D]), status: 200, hash: "bad", error: .badServerResponse)

        let fixture = theme(count: abc.count, hash: abcHash, url: URL(string: "https://example.invalid/transport.zip")!)
        let sentinel = NSError(domain: "TransportSentinel", code: 778, userInfo: ["payload": "retained"])
        for error: Error in [URLError(.notConnectedToInternet), URLError(.cancelled), CancellationError(), sentinel] {
            for reference in [false, true] {
                let spy = Spy()
                do {
                    _ = try await download(reference: reference, theme: fixture) { request in
                        spy.record(request); throw error
                    }
                    preconditionFailure("Transport error swallowed")
                } catch let caught {
                    let original = error as NSError, received = caught as NSError
                    precondition(failure(caught) == failure(error))
                    precondition(NSDictionary(dictionary: received.userInfo).isEqual(to: original.userInfo))
                    if original === sentinel { precondition(received === sentinel, "Transport error identity was replaced") }
                }
                precondition(spy.requests.count == 1 && spy.events == ["fetch"])
                validateRequest(spy.requests[0], theme: fixture)
                cases += 1
            }
        }

        // Match the public await: cancellation is observed through the fetch.
        // A cancelled task whose fetch returns verified bytes still succeeds.
        for reference in [false, true] {
            for cancelMode in 0...2 {
                let spy = Spy()
                let task = Task { @MainActor in
                    let outcome = await run(reference: reference, theme: fixture) { request in
                        spy.record(request)
                        return try await withCheckedThrowingContinuation { spy.continuation = $0 }
                    }
                    MainActor.preconditionIsolated()
                    spy.completed = true; spy.events.append("completed")
                    return outcome
                }
                for _ in 0..<1000 {
                    if spy.continuation != nil { break }
                    await Task.yield()
                }
                precondition(spy.continuation != nil && !spy.completed && spy.events == ["fetch"])
                precondition(spy.requests.count == 1)
                validateRequest(spy.requests[0], theme: fixture)
                if cancelMode == 1 {
                    task.cancel()
                    spy.continuation!.resume(throwing: CancellationError())
                } else {
                    if cancelMode == 2 { task.cancel() }
                    spy.continuation!.resume(returning: (abc, response(200)))
                }
                spy.continuation = nil
                let actual = await task.value
                let expected: Outcome = cancelMode == 1 ? .error(failure(CancellationError())) : .data(abc)
                precondition(actual == expected)
                precondition(spy.completed && spy.events == ["fetch", "completed"] && spy.requests.count == 1)
                cases += 1
            }
        }
        print("PASS: \(cases) async downloader cases; exact request/defaults, raw bytes, status/size/hash priority, transport identity, one fetch, MainActor, suspension and cancellation")
    }
}
