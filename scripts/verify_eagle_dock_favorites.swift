import Foundation

@main
private enum EagleDockFavoritesContract {
    static func main() async throws {
        MainActor.preconditionIsolated()
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        var samples = [
            "", " ", "\n\t", "[]", " [ ] \n", "null", "true", "false", "0", "1.5", "\"one\"", "{}",
            "[null]", "[true]", "[1]", "[1.5]", "[[]]", "[{}]", "[\"one\",null]", "[\"one\",1]",
            "[\"one\",false]", "[\"one\",[]]", "[\"one\",{}]", "[\"one\"]garbage", "[] []",
            "[", "[\"", "[\"one\"", "[\"one\",]", "[\"one\",\"two\"]", "[\"\",\" \",\"\"]",
            "[\"one\",\"one\"]", "[\"a\",\"A\",\" a \"]", "\u{feff}[\"one\"]",
            #"["quote\"","backslash\\","slash\/","line\n","null\u0000"]"#,
            #"["\u0061","\u00e9","e\u0301","\ud83e\udd85"]"#,
            #"["\ud800"]"#, #"["\udc00"]"#, #"["\uZZZZ"]"#,
            "[\"literal\0control\"]", "[\"literal\nnewline\"]",
        ]
        let groups: [[String]] = [
            [], ["one"], ["one", "one"], ["two", "one", "two"], ["", "", " "],
            ["a", "A", " a ", "a"], ["é", "e\u{301}", "É"], ["🦅", "主题", "тема", "テーマ"],
            ["slash/", "backslash\\", "quote\"", "line\n", "tab\t", "null\0", "\u{2028}", "\u{2029}"],
            (0..<512).map { "favorite-\($0)" }, [String(repeating: "🦅x", count: 8192)],
        ]
        for ids in groups {
            for options: JSONEncoder.OutputFormatting in [[], [.prettyPrinted], [.withoutEscapingSlashes]] {
                let encoder = JSONEncoder()
                encoder.outputFormatting = options // Input variants only; production uses the default encoder.
                samples.append(String(data: try encoder.encode(ids), encoding: .utf8)!)
            }
        }
        let originals = samples
        for json in originals {
            samples.append(" \n\t" + json + "\r\n ")
            samples.append(json + " invalid")
            samples.append(String(json.dropLast()))
        }
        var decodedCases: [(String, Set<String>)] = []
        for json in samples {
            let expected = BaselineDockGalleryFavorites.decode(json)
            let actual = EagleDockGalleryFavorites.decode(json)
            expect(actual == expected, "Public decode/default failure/duplicate/ID semantics changed")
            expect(EagleDockGalleryFavorites.decode(json) == actual, "Repeated decode gained mutable state")
            decodedCases.append((json, expected))
        }

        let uniqueIDs = ["", "a", "A", " a ", "🦅", "slash/", "quote\"", "é"]
        var sets = groups.map(Set.init)
        for mask in 0..<(1 << uniqueIDs.count) {
            sets.append(Set(uniqueIDs.enumerated().compactMap { index, id in
                mask & (1 << index) == 0 ? nil : id
            }))
        }
        var encodedCases: [(Set<String>, String?)] = []
        for ids in sets {
            let expected = BaselineDockGalleryFavorites.encode(ids)
            let actual = EagleDockGalleryFavorites.encode(ids)
            expect(actual == expected, "Exact default sorted JSON output differs from public")
            expect(actual != nil, "Ordinary String-set fixture should be encodable")
            let json = actual!
            expect(EagleDockGalleryFavorites.decode(json) == ids, "Favorite identities were lost on roundtrip")
            expect(try JSONDecoder().decode([String].self, from: Data(json.utf8)) == ids.sorted(),
                   "Output order is not the original sorted-ID array")
            expect(EagleDockGalleryFavorites.encode(ids) == actual, "Repeated encode gained mutable state")
            let reinserted = Set(ids.sorted().reversed())
            expect(EagleDockGalleryFavorites.encode(reinserted) == actual, "Set insertion order changed JSON output")
            encodedCases.append((ids, expected))
        }

        let immutableDecoded = decodedCases
        let immutableEncoded = encodedCases
        let detachedMatches = await Task.detached {
            immutableDecoded.allSatisfy { json, expected in
                EagleDockGalleryFavorites.decode(json) == expected
            } && immutableEncoded.allSatisfy { ids, expected in
                EagleDockGalleryFavorites.encode(ids) == expected
            }
        }.value
        expect(detachedMatches, "Pure favorites rules changed outside MainActor")
        print("PASS: \(checks) public/owned favorites checks across \(samples.count) valid/malformed JSON inputs and \(sets.count) sets; exact sorted output/Unicode/duplicates/roundtrip/repeated calls preserved; \(decodedCases.count + encodedCases.count) detached cases match; normal String sets do not exercise encoder failure")
    }
}
