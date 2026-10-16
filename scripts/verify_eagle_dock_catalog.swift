import Foundation

nonisolated private func theme(
    _ changes: [String: Any] = [:], removing keys: [String] = []
) -> [String: Any] {
    var value: [String: Any] = [
        "id": "still", "version": 4, "title": "Original title", "titleES": "Título original",
        "subtitle": "Original subtitle", "subtitleES": "Subtítulo original", "accent": "#20C0F0",
        "previewURL": "https://example.invalid/still.png?old=1#still",
        "animatedPreviewURL": "https://example.invalid/live.gif?old=2#live",
        "packageURL": "https://example.invalid/package.zip", "sha256": String(repeating: "a", count: 64),
        "byteCount": 4096, "frameCount": 1, "fps": 1, "width": 1146, "height": 318
    ]
    value.merge(changes) { _, new in new }
    for key in keys { value.removeValue(forKey: key) }
    return value
}

nonisolated private func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
}

nonisolated private func catalog(_ themes: [Any], schema: Any = 1) throws -> Data {
    try json(["schemaVersion": schema, "themes": themes])
}

nonisolated private struct PathKey: Equatable, Sendable {
    let string: String
    let int: Int?
    init(_ key: any CodingKey) { string = key.stringValue; int = key.intValue }
}

nonisolated private struct Failure: Equatable, Sendable {
    let kind: String
    let type: String?
    let key: PathKey?
    let path: [PathKey]
    let reason: String
    let domain: String
    let code: Int
    let underlyingDomain: String?
    let underlyingCode: Int?

    init(_ error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        let context: DecodingError.Context?
        switch error {
        case DecodingError.keyNotFound(let missing, let value):
            kind = "missing"; type = nil; key = PathKey(missing); context = value
        case DecodingError.typeMismatch(let expected, let value):
            kind = "type"; type = Self.normalize(String(describing: expected)); key = nil; context = value
        case DecodingError.valueNotFound(let expected, let value):
            kind = "null"; type = Self.normalize(String(describing: expected)); key = nil; context = value
        case DecodingError.dataCorrupted(let value):
            kind = "corrupt"; type = nil; key = nil; context = value
        case let url as URLError:
            precondition(url.code == .cannotParseResponse, "Unexpected catalog URL error")
            kind = "schema"; type = nil; key = nil; context = nil
            precondition(nsError.userInfo.isEmpty, "Schema error acquired new metadata")
        default:
            preconditionFailure("Unexpected catalog error: \(error)")
        }
        path = context?.codingPath.map(PathKey.init) ?? []
        reason = Self.normalize(context?.debugDescription ?? "")
        let underlying = context?.underlyingError as NSError?
        underlyingDomain = underlying?.domain
        underlyingCode = underlying?.code
    }

    // The reference catalog has a distinct type name; all theme decoding uses
    // the exact production type already checked against the public predecessor.
    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "PublicDockGalleryCatalog", with: "Catalog")
            .replacingOccurrences(of: "EagleDockGalleryCatalog", with: "Catalog")
    }
}

nonisolated private enum Outcome: Equatable, Sendable {
    case accepted([EagleDockGalleryTheme])
    case rejected(Failure)
}

nonisolated private func outcome(_ operation: () throws -> [EagleDockGalleryTheme]) -> Outcome {
    do { return .accepted(try operation()) }
    catch { return .rejected(Failure(error)) }
}

nonisolated private enum Expectation {
    case ids([String])
    case failure(String)
}

nonisolated private struct Checks {
    private(set) var count = 0

    @discardableResult
    mutating func verify(_ data: Data, _ label: String, expected: Expectation? = nil) -> Outcome {
        let old = outcome { try publicDockCatalogDecode(data) }
        let actual = outcome { try EagleDockGalleryCatalog.decodeSupportedThemes(from: data) }
        precondition(old == actual, "Public catalog parity failed: \(label)\n\(old)\n\(actual)")
        switch (expected, actual) {
        case (.ids(let ids), .accepted(let themes)):
            precondition(themes.map(\.id) == ids, "Unexpected selected order: \(label)")
        case (.failure(let kind), .rejected(let failure)):
            precondition(failure.kind == kind, "Unexpected rejection: \(label), \(failure)")
        case (nil, _): break
        default: preconditionFailure("Expected acceptance/rejection differs: \(label)")
        }
        count += 1
        return actual
    }
}

nonisolated private struct Generator {
    var state: UInt64 = 0xEA61ECA7A106
    mutating func index(_ count: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(count))
    }
}

@main
private enum EagleDockCatalogContract {
    static func main() async throws {
        var checks = Checks()
        let still = theme()
        let live = theme(["id": "live", "frameCount": 17, "fps": 6])
        let unsupported = theme(["id": "unsupported", "frameCount": 2])
        checks.verify(try catalog([]), "empty", expected: .ids([]))
        checks.verify(try catalog([unsupported]), "all filtered", expected: .ids([]))
        checks.verify(try catalog([still, unsupported, live, still, live]), "order and duplicates", expected: .ids(["still", "live", "still", "live"]))
        for schema in [Int.min, -1, 0, 1, 2, Int.max] {
            checks.verify(try catalog([still, live], schema: schema), "schema \(schema)", expected: schema == 1 ? .ids(["still", "live"]) : .failure("schema"))
        }
        for badSchema: Any in [NSNull(), "1", true, 1.5, [], [:]] {
            checks.verify(try catalog([still], schema: badSchema), "schema type")
        }
        checks.verify(try json(["themes": [still]]), "missing schema", expected: .failure("missing"))
        checks.verify(try json(["schemaVersion": 1]), "missing themes", expected: .failure("missing"))
        checks.verify(try json(["schema_version": 1, "themes": [still]]), "default key strategy", expected: .failure("missing"))
        for root: Any in [NSNull(), [], "catalog", 1, true] {
            checks.verify(try json(root), "root shape")
        }
        for schema in [1, 2] {
            for value: Any in [NSNull(), "themes", 1, true, [:]] {
                checks.verify(try json(["schemaVersion": schema, "themes": value]), "themes shape with schema \(schema)")
            }
            for entry: Any in [NSNull(), "theme", 1, true, [], [:]] {
                checks.verify(try catalog([still, entry, live], schema: schema), "bad theme entry with schema \(schema)")
            }
        }

        let required = ["id", "version", "title", "titleES", "subtitle", "subtitleES", "accent",
                        "previewURL", "packageURL", "sha256", "byteCount", "frameCount", "fps", "width", "height"]
        for key in required {
            for schema in [1, 2] {
                let absent = theme(["frameCount": 2], removing: [key])
                var nullChanges: [String: Any] = ["frameCount": 2]
                nullChanges[key] = NSNull()
                var wrongChanges: [String: Any] = ["frameCount": 2]
                wrongChanges[key] = [String: Any]()
                let null = theme(nullChanges)
                let wrong = theme(wrongChanges)
                // Unsupported entries still decode in full. Invalid schema must
                // not mask malformed theme errors or allow early filtering.
                checks.verify(try catalog([still, absent, live], schema: schema), "missing \(key), schema \(schema)", expected: .failure("missing"))
                checks.verify(try catalog([still, null, live], schema: schema), "null \(key), schema \(schema)", expected: .failure("null"))
                checks.verify(try catalog([still, wrong, live], schema: schema), "type \(key), schema \(schema)", expected: .failure("type"))
            }
        }
        for position in 0...2 {
            var entries: [Any] = [still, live]
            entries.insert(theme(["frameCount": 2], removing: ["id"]), at: position)
            checks.verify(try catalog(entries, schema: 0), "decode before schema, index \(position)", expected: .failure("missing"))
        }
        for frames in [1, 17] {
            for optional: Any in [NSNull(), "https://example.invalid/live.gif", "/relative.gif"] {
                let entry = theme(["frameCount": frames, "fps": frames == 1 ? 1 : 6, "animatedPreviewURL": optional])
                checks.verify(try catalog([entry]), "optional animated URL", expected: .ids(["still"]))
            }
            checks.verify(try catalog([theme(["frameCount": frames, "fps": frames == 1 ? 1 : 6], removing: ["animatedPreviewURL"])]), "missing optional URL", expected: .ids(["still"]))
        }
        checks.verify(try catalog([theme(["animatedPreviewURL": [:]])]), "malformed optional URL", expected: .failure("type"))
        checks.verify(try json(["schemaVersion": 1, "themes": [theme(["unknownThemeField": "ignored"])], "unknownCatalogField": [:]]), "unknown fields", expected: .ids(["still"]))

        let limit = 30 * 1024 * 1024
        let frames = [Int.min, -1, 0, 1, 2, 16, 17, 18, Int.max]
        let rates = [-1.0, 0, 1, 6, 6.0001]
        let bytes = [Int.min, -1, 0, 1, limit, limit + 1, Int.max]
        let widths = [Int.min, 1145, 1146, Int.max]
        let heights = [Int.min, 318, 319, Int.max]
        for frameCount in frames {
            for fps in rates {
                for byteCount in bytes {
                    for width in widths {
                        for height in heights {
                            let entry = theme(["frameCount": frameCount, "fps": fps, "byteCount": byteCount, "width": width, "height": height])
                            let accepted = ((frameCount == 1 && fps == 1) || (frameCount == 17 && fps == 6)) && width == 1146 && height == 318 && byteCount > 0 && byteCount <= limit
                            checks.verify(try catalog([entry]), "format boundary", expected: .ids(accepted ? ["still"] : []))
                        }
                    }
                }
            }
        }

        var generator = Generator()
        for iteration in 0..<300 {
            var entries: [Any] = []
            var selectedIDs: [String] = []
            for index in 0..<generator.index(15) {
                let accepted = generator.index(3) == 0
                let isLive = generator.index(2) == 0
                let id = "duplicate-\(generator.index(4))"
                var changes: [String: Any] = [
                    "id": id, "version": index, "title": "Title \(iteration)/\(index)",
                    "titleES": "Título \(index)", "subtitle": "Subtitle \(iteration)", "subtitleES": "Descripción \(index)",
                    "accent": index % 2 == 0 ? "not-hex" : "#A0B1C2", "sha256": "any-format-\(index)",
                    "frameCount": isLive ? 17 : 1, "fps": isLive ? 6 : 1,
                    "byteCount": index % 2 == 0 ? 1 : limit
                ]
                if !accepted { changes["width"] = 1145 }
                entries.append(theme(changes, removing: index % 2 == 0 ? ["animatedPreviewURL"] : []))
                if accepted { selectedIDs.append(id) }
            }
            checks.verify(try catalog(entries), "deterministic mixture \(iteration)", expected: .ids(selectedIDs))
        }

        for raw in ["", "{", "[] trailing", "{\"schemaVersion\":1,\"themes\":[}", "{\"schemaVersion\":1,\"themes\":[{\"fps\":NaN}]}", "{\"schemaVersion\":9223372036854775808,\"themes\":[]}"] {
            checks.verify(Data(raw.utf8), "malformed raw JSON")
        }
        checks.verify(Data([0xFF, 0xFE, 0xFF]), "malformed encoding")
        let object = "{\"schemaVersion\":1,\"themes\":[]}"
        checks.verify(object.data(using: .utf16)!, "default UTF-16 JSON decoding", expected: .ids([]))
        var padded = try catalog([still])
        padded.append(Data(repeating: 0x20, count: 512 * 1024 + 1))
        checks.verify(padded, "transport size limit remains outside Core", expected: .ids(["still"]))

        // Pass both the decoded catalog and returned themes across the UI actor
        // boundary; the production call site itself remains synchronous.
        let encoded = try catalog([still, unsupported, live, still])
        let detached = try await Task.detached {
            let decoded = try JSONDecoder().decode(EagleDockGalleryCatalog.self, from: encoded)
            let selected = try EagleDockGalleryCatalog.decodeSupportedThemes(from: encoded)
            return (decoded, selected)
        }.value
        precondition(detached.0.schemaVersion == 1 && detached.0.themes.count == 4)
        precondition(detached.1.map(\.id) == ["still", "live", "still"])
        let direct = try EagleDockGalleryCatalog.decodeSupportedThemes(from: encoded)
        precondition(detached.1 == direct)
        print("PASS: \(checks.count) public catalog parity cases, complete field/order/duplicate retention, default decoder and structural errors, schema precedence, support boundaries and detached Sendable execution")
    }
}
