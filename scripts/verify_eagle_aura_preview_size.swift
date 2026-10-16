import Foundation
import CoreGraphics

struct Sample: Sendable {
    let logical: CGFloat
    let width: CGFloat
    let height: CGFloat
    var frame: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
}
@MainActor final class Context {
    var samples: [Sample] = []
    var cursor = 0
    var events: [String] = []
    func reset(_ samples: [Sample]) {
        self.samples = samples
        cursor = 0
        events = []
    }
    func geometry() -> Geometry {
        precondition(cursor < samples.count)
        events.append("geometry.\(cursor)")
        let value = samples[cursor]
        cursor += 1
        return Geometry(value: value, context: self)
    }
}
@MainActor struct Geometry {
    let value: Sample
    let context: Context
    var logicalSize: CGSize {
        context.events.append("logical")
        return CGSize(width: value.logical, height: 844)
    }
    var compactIslandFrame: CGRect {
        context.events.append("compact")
        return value.frame
    }
}
@MainActor protocol Host {
    var context: Context { get }
    var compactIslandPreviewSize: CGSize { get }
}
extension Host {
    var displayGeometry: Geometry { context.geometry() }
}

@main struct Runner {
    static func same(_ lhs: CGSize, _ rhs: CGSize) {
        for (a, b) in [(lhs.width, rhs.width), (lhs.height, rhs.height)] {
            precondition(Double(a).bitPattern == Double(b).bitPattern || (a.isNaN && b.isNaN))
        }
    }
    @MainActor static func main() async {
        let old = PublicHost(context: Context())
        let owned = OwnedHost(context: Context())
        let trace = ["geometry.0", "logical", "geometry.1", "compact",
                     "geometry.2", "compact", "geometry.3", "compact"]
        var count = 0
        func check(_ samples: [Sample]) -> CGSize {
            old.context.reset(samples)
            owned.context.reset(samples)
            let expected = old.compactIslandPreviewSize
            let result = owned.compactIslandPreviewSize
            same(expected, result)
            precondition(old.context.events == trace && owned.context.events == trace)
            precondition(old.context.cursor == 4 && owned.context.cursor == 4)
            count += 1
            return result
        }
        let values: [CGFloat] = [-.infinity, -.greatestFiniteMagnitude, -1, -0.0, 0,
                                .leastNonzeroMagnitude, 1, 31, 96.nextDown, 96,
                                96.nextUp, 122.nextDown, 122, 122.nextUp, 134, 318,
                                393, 430, .greatestFiniteMagnitude, .infinity, .nan]
        var samples: [Sample] = []
        var expected: [CGSize] = []
        for logical in values {
            for width in values {
                for height in values {
                    let sample = Sample(logical: logical, width: width, height: height)
                    samples.append(sample)
                    expected.append(check(Array(repeating: sample, count: 4)))
                }
            }
        }
        // Each of the four provider reads may reflect a different geometry.
        // Caching one frame or moving a read changes these results or traces.
        for index in 0..<512 {
            let changing = (0..<4).map { offset in
                Sample(logical: CGFloat(280 + index + offset),
                       width: CGFloat(80 + (index * 7 + offset * 13) % 180),
                       height: CGFloat(10 + (index * 3 + offset * 19) % 90))
            }
            _ = check(changing)
            _ = check(Array(changing.reversed()))
        }
        let goldens: [(Sample, CGSize)] = [
            (Sample(logical: 318, width: 134, height: 39), CGSize(width: 122, height: 122 * (39.0 / 134))),
            (Sample(logical: 636, width: 134, height: 39), CGSize(width: 96, height: 31)),
            (Sample(logical: 318, width: 100, height: 50), CGSize(width: 100, height: 50)),
            (Sample(logical: 318, width: 100, height: 1), CGSize(width: 100, height: 31)),
            (Sample(logical: 0, width: 0, height: 39), CGSize(width: 96, height: 3744)),
        ]
        for (sample, golden) in goldens {
            let actual = check(Array(repeating: sample, count: 4))
            precondition(abs(actual.width - golden.width) < 1e-12)
            precondition(abs(actual.height - golden.height) < 1e-12)
        }
        let immutable = samples
        let detached = await Task.detached {
            immutable.map { value in
                EagleAuraStudioPreview.compactIslandSize(
                    readLogicalWidth: { value.logical },
                    readCompactWidth: { value.frame.width },
                    readCompactHeight: { value.frame.height }
                )
            }
        }.value
        for (a, b) in zip(expected, detached) { same(a, b) }
        print("PASS: \(count) public/owned preview-size cases, \(count * 8) ordered events, \(detached.count) detached cases; 1,024 changing-geometry sequences, five goldens, reused hosts")
    }
}
