import Foundation
import UIKit
import CoreImage

@MainActor
private func theme(
    frames: Int = 1, fps: Double? = nil, width: Int = 1146, height: Int = 318
) -> EagleDockGalleryTheme {
    EagleDockGalleryTheme(
        id: "uikit-frame-fixture", version: 1, title: "Fixture", titleES: "Fixture",
        subtitle: "Fixture", subtitleES: "Fixture", accent: "#20C0F0",
        previewURL: URL(string: "https://example.invalid/preview.png")!,
        animatedPreviewURL: nil,
        packageURL: URL(string: "https://example.invalid/package.zip")!,
        sha256: String(repeating: "a", count: 64), byteCount: 4096,
        frameCount: frames, fps: fps ?? (frames == 17 ? 6 : 1), width: width, height: height
    )
}

@MainActor
private func bitmap(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.125, green: 0.75, blue: 0.94, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@MainActor
private func outcome(_ operation: () throws -> Void) -> URLError? {
    do { try operation(); return nil }
    catch let error as URLError { return error }
    catch { preconditionFailure("Unexpected adapter error: \(error)") }
}

@MainActor
private func verifyDecode(_ data: Data, theme: EagleDockGalleryTheme, accepted: Bool) {
    let original = outcome { try PublicDockFrameAdapter.validate(data, theme: theme) }
    let actual = outcome { try ProductionDockFrameAdapter.validate(data, theme: theme) }
    precondition((original == nil) == accepted && (actual == nil) == accepted)
    precondition(EagleDockGalleryFrameImage.isValid(data, theme: theme) == accepted)
    if let original, let actual {
        precondition(original.code == .cannotDecodeContentData && actual.code == original.code)
        precondition((original as NSError).domain == (actual as NSError).domain)
        precondition((original as NSError).userInfo.isEmpty && (actual as NSError).userInfo.isEmpty)
    }
}

@MainActor
private func verifyImage(_ image: UIImage, theme: EagleDockGalleryTheme, accepted: Bool) {
    precondition(PublicDockFrameAdapter.dimensions(image, theme: theme) == accepted)
    precondition(ProductionDockFrameAdapter.dimensions(image, theme: theme) == accepted)
}

// A real UIImage subclass verifies that the production adapter preserves two independent
// cgImage projections and skips the second getter after a failed width check.
nonisolated private final class ProjectionImage: UIImage, @unchecked Sendable {
    // All access happens synchronously on the test's main actor.
    var projections: [CGImage?] = [nil]
    private(set) var reads = 0

    override var cgImage: CGImage? {
        let value = projections[min(reads, projections.count - 1)]
        reads += 1
        return value
    }
}

@main
private enum EagleDockFrameUIKitContract {
    @MainActor
    static func main() throws {
        let expected = theme()
        let exact = bitmap(width: 1146, height: 318)
        let wrongWidth = bitmap(width: 1145, height: 318)
        let wrongHeight = bitmap(width: 1146, height: 319)
        let wrongBoth = bitmap(width: 1145, height: 319)
        let tiny = bitmap(width: 1, height: 1)
        let exactPNG = UIImage(cgImage: exact).pngData()!
        let widthPNG = UIImage(cgImage: wrongWidth).pngData()!
        let heightPNG = UIImage(cgImage: wrongHeight).pngData()!
        let bothPNG = UIImage(cgImage: wrongBoth).pngData()!
        let tinyPNG = UIImage(cgImage: tiny).pngData()!
        let corrupt = Data([0x00, 0x45, 0x61, 0x67, 0x6c, 0x65])
        var decodeCases = 0
        for (data, accepted) in [
            (exactPNG, true), (widthPNG, false), (heightPNG, false), (bothPNG, false),
            (tinyPNG, false), (Data(), false), (corrupt, false), (Data(exactPNG.prefix(8)), false)
        ] {
            verifyDecode(data, theme: expected, accepted: accepted)
            decodeCases += 1
        }
        // Decoding does not add the catalog's separate supported-format gate.
        verifyDecode(tinyPNG, theme: theme(width: 1, height: 1), accepted: true)
        decodeCases += 1

        var imageCases = 0
        for scale in [1.0, 2.0, 3.0] {
            for orientation in [UIImage.Orientation.up, .right, .downMirrored, .rightMirrored] {
                let image = UIImage(cgImage: exact, scale: scale, orientation: orientation)
                verifyImage(image, theme: expected, accepted: true)
                precondition(image.cgImage?.width == 1146 && image.cgImage?.height == 318)
                if scale != 1 { precondition(image.size != CGSize(width: 1146, height: 318)) }
                imageCases += 1
            }
        }
        let ciImage = CIImage(color: CIColor(red: 0.125, green: 0.75, blue: 0.94))
            .cropped(to: CGRect(x: 0, y: 0, width: 1146, height: 318))
        let ciBacked = UIImage(ciImage: ciImage, scale: 2, orientation: .right)
        precondition(ciBacked.cgImage == nil)
        verifyImage(ciBacked, theme: expected, accepted: false)
        verifyImage(UIImage(), theme: expected, accepted: false)
        imageCases += 2

        var projectionCases = 0
        let projections: [([CGImage?], Bool, Int)] = [
            ([nil, exact], false, 1), ([wrongWidth, exact], false, 1),
            ([exact, nil], false, 2), ([exact, wrongHeight], false, 2),
            ([exact, exact], true, 2), ([wrongHeight, wrongWidth], true, 2)
        ]
        for (images, accepted, reads) in projections {
            let original = ProjectionImage()
            original.projections = images
            let actual = ProjectionImage()
            actual.projections = images
            precondition(PublicDockFrameAdapter.dimensions(original, theme: expected) == accepted)
            precondition(ProductionDockFrameAdapter.dimensions(actual, theme: expected) == accepted)
            precondition(original.reads == reads && actual.reads == reads)
            projectionCases += 1
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("eagle-frame-cache-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        var cacheCases = 0
        func verifyCache(_ directory: URL, _ catalog: EagleDockGalleryTheme, accepted: Bool) {
            precondition(PublicDockFrameAdapter.validFrames(in: directory, theme: catalog) == accepted)
            precondition(ProductionDockFrameAdapter.validFrames(in: directory, theme: catalog) == accepted)
            cacheCases += 1
        }
        for frames in [1, 17] {
            let catalog = theme(frames: frames)
            let directory = root.appendingPathComponent("frames-\(frames)")
            verifyCache(directory, catalog, accepted: false)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            verifyCache(directory, catalog, accepted: false)
            for index in 1...frames {
                let url = directory.appendingPathComponent(String(format: "frame%02d.png", index))
                try exactPNG.write(to: url)
                verifyCache(directory, catalog, accepted: index == frames)
            }
            try corrupt.write(to: directory.appendingPathComponent("unrelated.png"))
            try fm.createDirectory(at: directory.appendingPathComponent("unrelated"), withIntermediateDirectories: false)
            verifyCache(directory, catalog, accepted: true)
            let last = directory.appendingPathComponent(String(format: "frame%02d.png", frames))
            for badData in [widthPNG, heightPNG, bothPNG, tinyPNG, corrupt, Data(), Data(exactPNG.prefix(8))] {
                try badData.write(to: last)
                verifyCache(directory, catalog, accepted: false)
            }
            try fm.removeItem(at: last)
            verifyCache(directory, catalog, accepted: false)
            try fm.createDirectory(at: last, withIntermediateDirectories: false)
            verifyCache(directory, catalog, accepted: false)
            try fm.removeItem(at: last)
            try exactPNG.write(to: last)
            verifyCache(directory, catalog, accepted: true)
            verifyCache(directory, theme(frames: frames, fps: 0), accepted: false)
            verifyCache(directory, theme(frames: frames, width: 1145), accepted: false)
            verifyCache(directory, theme(frames: frames, height: 319), accepted: false)
            verifyCache(directory, theme(frames: 0), accepted: false)
        }
        precondition(decodeCases + imageCases + projectionCases + cacheCases == 81)
        print("PASS: \(decodeCases) real UIImage decode/error/isValid cases, \(imageCases) pixel/scale/orientation/nil-CGImage cases, \(projectionCases) UIImage getter-order cases, \(cacheCases) exact public/production cache cases (81 total)")
    }
}
