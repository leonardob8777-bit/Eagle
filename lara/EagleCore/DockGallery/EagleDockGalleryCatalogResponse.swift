import Foundation

/// The public catalog response gate, independent of the HTTP transport.
nonisolated enum EagleDockGalleryCatalogResponse {
    static func validate(data: Data, httpStatusCode: Int?) throws {
        guard let httpStatusCode,
              (200..<300).contains(httpStatusCode),
              data.count <= 512 * 1024 else { throw URLError(.badServerResponse) }
    }
}
