import Foundation
import CryptoKit

nonisolated private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

nonisolated private func response(_ status: Int?) -> URLResponse {
    let url = URL(string: "https://example.invalid/dock.zip")!
    if let status, let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) {
        return http
    }
    return URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
}

nonisolated private func failure(_ operation: () throws -> Void) -> URLError? {
    do { try operation(); return nil }
    catch let error as URLError { return error }
    catch { preconditionFailure("Unexpected download-validation error: \(error)") }
}

nonisolated private func verify(
    _ data: Data, status: Int?, count: Int, hash: String, expectedError: URLError.Code? = nil,
    accepted: Bool? = nil
) {
    let received = response(status)
    let old = failure {
        try publicDockDownloadValidation(data, response: received, expectedByteCount: count, expectedSHA256: hash)
    }
    let new = failure {
        try EagleDockGalleryPackageValidation.validateDownload(
            data, httpStatusCode: (received as? HTTPURLResponse)?.statusCode,
            expectedByteCount: count, expectedSHA256: hash
        )
    }
    precondition(old?.code == new?.code, "Validation success/error differs from public code")
    if let old, let new {
        precondition((old as NSError).domain == (new as NSError).domain)
        precondition((old as NSError).userInfo.isEmpty && (new as NSError).userInfo.isEmpty)
    }
    if let expectedError { precondition(new?.code == expectedError) }
    if let accepted { precondition((new == nil) == accepted) }
}

@main
private enum EagleDockDownloadContract {
    static func main() async throws {
        let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        precondition(digest(Data()) == emptyHash)
        precondition(digest(Data("abc".utf8)) == abcHash)
        verify(Data(), status: 200, count: 0, hash: emptyHash, accepted: true)
        verify(Data("abc".utf8), status: 200, count: 3, hash: abcHash, accepted: true)
        var checked = 2
        let payloads = [Data(), Data("abc".utf8), Data([0]), Data((0...255).map { UInt8($0) }), Data(repeating: 0xA7, count: 4096)]
        let statuses: [Int?] = [nil, -1, 0, 199, 200, 201, 204, 206, 299, 300, 404, 500, Int.min, Int.max]
        for data in payloads {
            let correct = digest(data)
            let mixed = String(correct.enumerated().map { index, character in
                index % 2 == 0 ? Character(String(character).uppercased()) : character
            })
            let hashes = [correct, correct.uppercased(), mixed, String(repeating: "0", count: 64),
                          "", "bad-hash", String(correct.prefix(12)), " " + correct, correct + " ", correct + "\n"]
            for status in statuses {
                for count in [data.count, data.count + 1, -1, 0, Int.min, Int.max] {
                    for hash in hashes {
                        verify(data, status: status, count: count, hash: hash)
                        checked += 1
                    }
                }
            }
        }

        // Hash large data only at the acceptance boundary. Other competing
        // failures must preserve badServerResponse before any checksum decision.
        let limit = 30 * 1024 * 1024
        let atLimit = Data(repeating: 0x6D, count: limit)
        let limitHash = digest(atLimit)
        verify(atLimit, status: 200, count: limit, hash: limitHash, accepted: true)
        verify(atLimit, status: 299, count: limit, hash: limitHash.uppercased(), accepted: true)
        verify(atLimit, status: 200, count: limit - 1, hash: "bad", expectedError: .badServerResponse)
        let oversized = Data(repeating: 0x6D, count: limit + 1)
        verify(oversized, status: 200, count: oversized.count, hash: limitHash, expectedError: .badServerResponse)
        verify(oversized, status: 300, count: oversized.count, hash: "bad", expectedError: .badServerResponse)
        verify(Data("abc".utf8), status: 200, count: 3, hash: "bad", expectedError: .secureConnectionFailed)
        checked += 6

        // Test outside the UI actor. The production store remains synchronous.
        try await Task.detached {
            try EagleDockGalleryPackageValidation.validateDownload(
                Data("abc".utf8), httpStatusCode: 200, expectedByteCount: 3, expectedSHA256: abcHash
            )
        }.value
        print("PASS: \(checked) public download-validation parity cases, status/size/hash boundaries, exact errors and UI-independent execution")
    }
}
