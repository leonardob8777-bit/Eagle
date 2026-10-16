import Foundation
import CryptoKit

/// The public download-integrity rule, independent of networking and the UI.
/// Runs synchronously on its caller, as the original store validation did.
nonisolated enum EagleDockGalleryPackageValidation {
    static func validateDownload(
        _ data: Data,
        httpStatusCode: Int?,
        expectedByteCount: Int,
        expectedSHA256: String
    ) throws {
        guard let httpStatusCode,
              (200..<300).contains(httpStatusCode),
              data.count == expectedByteCount,
              data.count <= 30 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw URLError(.secureConnectionFailed)
        }
    }
}
