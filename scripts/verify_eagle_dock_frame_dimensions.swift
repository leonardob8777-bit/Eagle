import Foundation

nonisolated private func traced(
    original: Bool, width: Int?, height: Int?, expectedWidth: Int, expectedHeight: Int
) -> (Bool, [String]) {
    var reads: [String] = []
    func readWidth() -> Int? { reads.append("width"); return width }
    func readHeight() -> Int? { reads.append("height"); return height }
    func readExpectedWidth() -> Int { reads.append("expectedWidth"); return expectedWidth }
    func readExpectedHeight() -> Int { reads.append("expectedHeight"); return expectedHeight }
    let matches: Bool
    if original {
        matches = publicDockFrameDimensions(
            width: readWidth(), height: readHeight(),
            expectedWidth: readExpectedWidth(), expectedHeight: readExpectedHeight()
        )
    } else {
        matches = EagleDockGalleryFrameDimensions.matches(
            width: readWidth(), height: readHeight(),
            expectedWidth: readExpectedWidth(), expectedHeight: readExpectedHeight()
        )
    }
    return (matches, reads)
}

@main
private enum EagleDockFrameDimensionsContract {
    static func main() async {
        var checked = 0
        let actual: [Int?] = [nil, Int.min, -1, 0, 1, 317, 318, 1145, 1146, 1147, Int.max]
        let widths = [Int.min, -1, 0, 1, 1146, Int.max]
        let heights = [Int.min, -1, 0, 1, 318, Int.max]
        for width in actual {
            for height in actual {
                for expectedWidth in widths {
                    for expectedHeight in heights {
                        let original = publicDockFrameDimensions(
                            width: width, height: height,
                            expectedWidth: expectedWidth, expectedHeight: expectedHeight
                        )
                        let matches = EagleDockGalleryFrameDimensions.matches(
                            width: width, height: height,
                            expectedWidth: expectedWidth, expectedHeight: expectedHeight
                        )
                        precondition(matches == original)
                        precondition(matches == (width == expectedWidth && height == expectedHeight))
                        checked += 1
                    }
                }
            }
        }
        let tracedWidths: [Int?] = [nil, -1, 0, 1145, 1146]
        let tracedHeights: [Int?] = [nil, 0, 317, 318]
        for width in tracedWidths {
            for height in tracedHeights {
                let original = traced(original: true, width: width, height: height, expectedWidth: 1146, expectedHeight: 318)
                let actual = traced(original: false, width: width, height: height, expectedWidth: 1146, expectedHeight: 318)
                precondition(actual.0 == original.0 && actual.1 == original.1)
                let expectedReads = width == 1146
                    ? ["width", "expectedWidth", "height", "expectedHeight"]
                    : ["width", "expectedWidth"]
                precondition(actual.1 == expectedReads)
                checked += 1
            }
        }
        let detached = await Task.detached {
            EagleDockGalleryFrameDimensions.matches(width: 1146, height: 318, expectedWidth: 1146, expectedHeight: 318)
        }.value
        precondition(detached)
        print("PASS: \(checked) public dimension parity cases, nil/extreme values, exact lazy getter order and UI-independent execution")
    }
}
