import Foundation

nonisolated private func response(status: Int?) -> URLResponse {
    let url = URL(string: "https://example.invalid/catalog.json")!
    if let status {
        guard let http = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else { preconditionFailure("Could not create HTTP status \(status)") }
        return http
    }
    return URLResponse(url: url, mimeType: "application/json", expectedContentLength: 0, textEncodingName: "utf-8")
}

nonisolated private func failure(_ operation: () throws -> Void) -> NSError? {
    do { try operation(); return nil }
    catch { return error as NSError }
}

nonisolated private func verify(_ data: Data, status: Int?, expectedAccepted: Bool) {
    let received = response(status: status)
    let old = failure { try publicDockCatalogResponseValidate(data, response: received) }
    let actual = failure {
        try EagleDockGalleryCatalogResponse.validate(
            data: data, httpStatusCode: (received as? HTTPURLResponse)?.statusCode
        )
    }
    precondition((old == nil) == (actual == nil), "Public/catalog response acceptance differs")
    precondition((actual == nil) == expectedAccepted, "Unexpected response acceptance")
    if let old, let actual {
        precondition(old.domain == actual.domain && old.code == actual.code, "Error domain/code changed")
        precondition(old.domain == NSURLErrorDomain && old.code == URLError.badServerResponse.rawValue)
        precondition(old.userInfo.isEmpty && actual.userInfo.isEmpty, "Error metadata changed")
    }
}

@main
private enum EagleDockCatalogResponseContract {
    static func main() async throws {
        let limit = 512 * 1024
        let payloads = [
            Data(),
            Data("{not json".utf8),
            Data("{\"schemaVersion\":1,\"themes\":[]}".utf8),
            Data(repeating: 0xA7, count: limit - 1),
            Data(repeating: 0xB4, count: limit),
            Data(repeating: 0xC9, count: limit + 1),
        ]
        let statuses: [Int?] = [nil, 100, 199, 200, 201, 204, 206, 299, 300, 304, 400, 404, 500, 599]
        var checked = 0
        for payload in payloads {
            for status in statuses {
                verify(payload, status: status, expectedAccepted: status.map { (200..<300).contains($0) } == true && payload.count <= limit)
                checked += 1
            }
        }
        // This transport gate accepts malformed JSON at 200; the separate
        // catalog decoder is responsible for rejecting its contents.
        verify(Data("{not json".utf8), status: 200, expectedAccepted: true)
        verify(Data(repeating: 0xAA, count: limit + 1), status: 404, expectedAccepted: false)
        checked += 2

        try await Task.detached {
            try EagleDockGalleryCatalogResponse.validate(data: Data(), httpStatusCode: 200)
            try EagleDockGalleryCatalogResponse.validate(data: Data(repeating: 0x11, count: limit), httpStatusCode: 299)
        }.value
        print("PASS: \(checked) public catalog response parity cases, size/status boundaries, exact errors and detached execution")
    }
}
