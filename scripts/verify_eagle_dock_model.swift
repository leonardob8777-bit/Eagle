import Foundation

nonisolated private func fixture(
    _ changes: [String: Any] = [:], removing keys: [String] = []
) throws -> Data {
    var value: [String: Any] = [
        "id": "test-theme", "version": 4,
        "title": "Original title", "titleES": "Título original",
        "subtitle": "Original subtitle", "subtitleES": "Subtítulo original",
        "accent": "#20C0F0", "previewURL": "https://example.invalid/still.png?old=1#still",
        "animatedPreviewURL": "https://example.invalid/live.gif?old=2#live",
        "packageURL": "https://example.invalid/package.zip",
        "sha256": String(repeating: "a", count: 64), "byteCount": 4096,
        "frameCount": 1, "fps": 1, "width": 1146, "height": 318
    ]
    value.merge(changes) { _, new in new }
    for key in keys { value.removeValue(forKey: key) }
    return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

nonisolated private func decodingFailure(_ error: Error) -> String {
    switch error {
    case DecodingError.keyNotFound(let key, let context):
        return "missing:\(key.stringValue):\(context.codingPath.map(\.stringValue))"
    case DecodingError.typeMismatch(let type, let context):
        return "type:\(type):\(context.codingPath.map(\.stringValue))"
    case DecodingError.valueNotFound(let type, let context):
        return "null:\(type):\(context.codingPath.map(\.stringValue))"
    case DecodingError.dataCorrupted(let context):
        return "corrupt:\(context.codingPath.map(\.stringValue)):\(context.debugDescription)"
    default:
        return String(describing: error)
    }
}

nonisolated private func compareWithPublicModel(_ data: Data) throws {
    let original = try JSONDecoder().decode(BaselineDockGalleryTheme.self, from: data)
    let actual = try JSONDecoder().decode(EagleDockGalleryTheme.self, from: data)
    precondition(actual.id == original.id && actual.version == original.version)
    precondition(actual.title == original.title && actual.titleES == original.titleES)
    precondition(actual.subtitle == original.subtitle && actual.subtitleES == original.subtitleES)
    precondition(actual.accent == original.accent && actual.previewURL == original.previewURL)
    precondition(actual.animatedPreviewURL == original.animatedPreviewURL)
    precondition(actual.packageURL == original.packageURL && actual.sha256 == original.sha256)
    precondition(actual.byteCount == original.byteCount && actual.frameCount == original.frameCount)
    precondition(actual.fps == original.fps && actual.width == original.width && actual.height == original.height)
    precondition(actual.rgb.0 == original.rgb.0 && actual.rgb.1 == original.rgb.1 && actual.rgb.2 == original.rgb.2)
    precondition(actual.presentationPreviewURL == original.presentationPreviewURL)
    precondition(actual.duration == original.duration || (actual.duration.isNaN && original.duration.isNaN))
    precondition(actual.isSupportedPackage == original.isSupportedPackage)
    let same = try JSONDecoder().decode(EagleDockGalleryTheme.self, from: data)
    precondition(actual == same && Set([actual, same]).count == 1)
}

nonisolated private func compareRejectedFixture(_ data: Data) {
    let oldFailure: String
    let newFailure: String
    do {
        _ = try JSONDecoder().decode(BaselineDockGalleryTheme.self, from: data)
        preconditionFailure("Public reference accepted a required-field failure")
    } catch { oldFailure = decodingFailure(error) }
    do {
        _ = try JSONDecoder().decode(EagleDockGalleryTheme.self, from: data)
        preconditionFailure("Core accepted a required-field failure")
    } catch { newFailure = decodingFailure(error) }
    precondition(oldFailure == newFailure, "Changed catalog decoding failure")
}

@main
private enum EagleDockModelContract {
    static func main() async throws {
        var checked = 0
        // Exact format boundary, including zero/negative values and the 30 MiB edge.
        for frames in [-1, 0, 1, 2, 16, 17, 18] {
            for fps in [-1.0, 0.0, 1.0, 6.0, 6.1] {
                for bytes in [-1, 0, 1, 30 * 1024 * 1024, 30 * 1024 * 1024 + 1] {
                    for width in [1145, 1146] {
                        for height in [318, 319] {
                            try compareWithPublicModel(fixture([
                                "frameCount": frames, "fps": fps, "byteCount": bytes,
                                "width": width, "height": height
                            ]))
                            checked += 1
                        }
                    }
                }
            }
        }
        for accent in ["#20C0F0", "abcdef", "##12AB34##", "", "not-hex", "100000000", "12345678"] {
            try compareWithPublicModel(fixture(["accent": accent]))
            checked += 1
        }
        for frames in [1, 17] {
            try compareWithPublicModel(fixture(["frameCount": frames], removing: ["animatedPreviewURL"]))
            try compareWithPublicModel(fixture(["frameCount": frames, "animatedPreviewURL": NSNull()]))
            checked += 2
        }
        try compareWithPublicModel(fixture(["futureCatalogField": "ignored"])); checked += 1

        let decoder = JSONDecoder()
        let still = try decoder.decode(EagleDockGalleryTheme.self, from: fixture())
        precondition(still.presentationPreviewURL.absoluteString == "https://example.invalid/still.png?preview=4-static#still")
        let live = try decoder.decode(EagleDockGalleryTheme.self, from: fixture(["frameCount": 17, "fps": 6]))
        precondition(live.presentationPreviewURL.absoluteString == "https://example.invalid/live.gif?preview=4-animated#live")
        let fallback = try decoder.decode(EagleDockGalleryTheme.self, from: fixture(["accent": "bad-hex"]))
        precondition(fallback.rgb.0 == 219 && fallback.rgb.1 == 64 && fallback.rgb.2 == 224)

        let required = ["id", "version", "title", "titleES", "subtitle", "subtitleES", "accent",
                        "previewURL", "packageURL", "sha256", "byteCount", "frameCount", "fps", "width", "height"]
        for key in required {
            compareRejectedFixture(try fixture(removing: [key]))
            compareRejectedFixture(try fixture([key: NSNull()]))
            checked += 2
        }
        let malformed: [[String: Any]] = [["frameCount": "17"], ["fps": "6"], ["id": 5], ["previewURL": [:]]]
        for changes in malformed {
            compareRejectedFixture(try fixture(changes)); checked += 1
        }

        // The exact production data/request types can cross out of the UI actor.
        let encoded = try fixture()
        let request = try await Task.detached {
            let theme = try JSONDecoder().decode(EagleDockGalleryTheme.self, from: encoded)
            return EagleDockGalleryApplyRequest(
                theme: theme, directory: URL(fileURLWithPath: "/tmp/eagle-prepared-dock"), intensity: 0.72
            )
        }.value
        precondition(request.theme == still && request.intensity == 0.72)
        print("PASS: \(checked) public-model parity cases, decoding failures, preview URLs, RGB, format rules and UI-independent request")
    }
}
