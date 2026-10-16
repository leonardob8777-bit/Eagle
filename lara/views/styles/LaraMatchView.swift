import SwiftUI
import PhotosUI
import Combine
import CoreTransferable
import UniformTypeIdentifiers
import AVFoundation
import UIKit
import Vision
import CoreImage

private enum LaraMatchSourceKind: String, Codable, Sendable {
    case photo = "Foto"
    case video = "Video"

    var localizedTitle: String {
        switch self {
        case .photo: return LaraL10n.text(en: "Photo", es: "Foto")
        case .video: return LaraL10n.text(en: "Video", es: "Video")
        }
    }
}

private struct LaraMatchStoredTone: Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ tone: CompleteStyleTone) {
        red = tone.red
        green = tone.green
        blue = tone.blue
    }

    var tone: CompleteStyleTone {
        CompleteStyleTone(red: red, green: green, blue: blue)
    }
}

private struct LaraSavedMatch: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let name: String
    let sourceKind: LaraMatchSourceKind
    let matchedPackID: String
    let intensityRawValue: String?
    let tones: [LaraMatchStoredTone]
    let thumbnail: Data
}

private struct LaraSmartFocusProfile {
    let focusPoint: CGPoint
    let importantRegion: CGRect
    let faceRegions: [CGRect]
    let attentionConfidence: Float
    let qualityScore: Double

    var faceCount: Int { faceRegions.count }

    var outputFocusPoint: CGPoint {
        CGPoint(x: focusPoint.x, y: faceCount > 0 ? 0.58 : 0.54)
    }

    var localizedSummary: String {
        if faceCount == 1 {
            return LaraL10n.text(
                en: "One face protected from the clock and edges",
                es: "Un rostro protegido del reloj y los bordes"
            )
        }
        if faceCount > 1 {
            return LaraL10n.text(
                en: "\(faceCount) faces kept inside the safe composition",
                es: "\(faceCount) rostros conservados dentro de la composición segura"
            )
        }
        return LaraL10n.text(
            en: "The main visual subject stays inside the safe composition",
            es: "El sujeto visual principal permanece dentro de la composición segura"
        )
    }
}

private struct LaraMatchAnalysis {
    let sourceImage: UIImage
    let sourceKind: LaraMatchSourceKind
    let tones: [CompleteStyleTone]
    let matchedPack: CompleteStylePack
    let smartFocus: LaraSmartFocusProfile

    var cardPack: CompleteStylePack {
        CompleteStylePack(
            id: matchedPack.id,
            name: "Eagle Composer",
            tagline: LaraL10n.text(en: "Created from your colors.", es: "Creado desde tus colores."),
            summary: LaraL10n.text(
                en: "A composition generated locally from your image.",
                es: "Una composición generada localmente a partir de tu imagen."
            ),
            symbol: "camera.filters",
            tones: tones,
            motif: matchedPack.motif,
            wallpaperName: matchedPack.wallpaperName,
            wallpaperFile: matchedPack.wallpaperFile,
            wallpaperPreview: matchedPack.wallpaperPreview,
            wallpaperAuthor: matchedPack.wallpaperAuthor,
            passcodeName: matchedPack.passcodeName,
            passcodeFile: matchedPack.passcodeFile,
            passcodePreview: matchedPack.passcodePreview,
            passcodeAuthor: matchedPack.passcodeAuthor
        )
    }
}

private enum LaraMatchError: LocalizedError {
    case unsupportedSelection
    case videoFrameFailed
    case paletteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return LaraL10n.text(en: "Eagle could not read that photo or video. Try another item.", es: "Eagle no pudo leer esa foto o video. Prueba con otro elemento.")
        case .videoFrameFailed:
            return LaraL10n.text(en: "A frame could not be extracted from the video.", es: "No se pudo obtener un fotograma del video.")
        case .paletteFailed:
            return LaraL10n.text(en: "The image does not contain enough color information.", es: "La imagen no contiene suficiente información de color.")
        }
    }
}

private struct LaraMatchMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("EagleMatch-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return LaraMatchMovie(url: destination)
        }
    }
}

private enum LaraSmartFocusAnalyzer {
    static func analyze(_ sourceImage: UIImage) -> LaraSmartFocusProfile {
        let image = sourceImage.laraComposerNormalized
        guard let cgImage = image.cgImage else {
            return fallbackProfile(for: image)
        }

        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([attentionRequest, faceRequest])

        let attentionObservation = attentionRequest.results?.first
        let attentionRegion = attentionObservation?
            .salientObjects?
            .max(by: { $0.confidence < $1.confidence })
            .map { topLeftRect($0.boundingBox) }

        let faces = (faceRequest.results ?? [])
            .filter { $0.confidence >= 0.35 }
            .map { topLeftRect($0.boundingBox) }

        let faceRegion = faces.reduce(nil as CGRect?) { partial, face in
            partial?.union(face) ?? face
        }
        let important = clipped(faceRegion ?? attentionRegion ?? CGRect(x: 0.25, y: 0.22, width: 0.5, height: 0.56))

        let attentionCenter = center(of: attentionRegion ?? important)
        let focus: CGPoint
        if let faceRegion {
            let faceCenter = center(of: faceRegion)
            focus = CGPoint(
                x: faceCenter.x * 0.76 + attentionCenter.x * 0.24,
                y: faceCenter.y * 0.76 + attentionCenter.y * 0.24
            )
        } else {
            focus = attentionCenter
        }

        return LaraSmartFocusProfile(
            focusPoint: clipped(focus),
            importantRegion: important,
            faceRegions: faces,
            attentionConfidence: attentionObservation?.confidence ?? 0,
            qualityScore: visualQuality(of: cgImage)
        )
    }

    static func videoFrameScore(_ image: UIImage) -> Double {
        let profile = analyze(image)
        let faceBonus = min(Double(profile.faceCount) * 0.12, 0.30)
        let attentionBonus = Double(profile.attentionConfidence) * 0.12
        let edgePenalty = importantRegionEdgePenalty(profile.importantRegion)
        return profile.qualityScore + faceBonus + attentionBonus - edgePenalty
    }

    private static func fallbackProfile(for image: UIImage) -> LaraSmartFocusProfile {
        let score: Double
        if let cgImage = image.cgImage {
            score = visualQuality(of: cgImage)
        } else {
            score = 0.5
        }
        return LaraSmartFocusProfile(
            focusPoint: CGPoint(x: 0.5, y: 0.5),
            importantRegion: CGRect(x: 0.25, y: 0.22, width: 0.5, height: 0.56),
            faceRegions: [],
            attentionConfidence: 0,
            qualityScore: score
        )
    }

    private static func visualQuality(of image: CGImage) -> Double {
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0.5 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminances = [Double](repeating: 0, count: width * height)
        var sum = 0.0
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            let value = (
                Double(pixels[offset]) * 0.2126 +
                Double(pixels[offset + 1]) * 0.7152 +
                Double(pixels[offset + 2]) * 0.0722
            ) / 255
            luminances[pixel] = value
            sum += value
        }

        let mean = sum / Double(luminances.count)
        let variance = luminances.reduce(0) { $0 + pow($1 - mean, 2) } / Double(luminances.count)
        var edgeEnergy = 0.0
        var edgeSamples = 0
        for y in 1..<height {
            for x in 1..<width {
                let index = y * width + x
                edgeEnergy += abs(luminances[index] - luminances[index - 1])
                edgeEnergy += abs(luminances[index] - luminances[index - width])
                edgeSamples += 2
            }
        }
        let sharpness = edgeSamples > 0 ? edgeEnergy / Double(edgeSamples) : 0
        let exposure = max(0, 1 - abs(mean - 0.52) * 1.55)
        let contrast = min(1, sqrt(variance) * 4.2)
        let detail = min(1, sharpness * 7.5)
        return exposure * 0.34 + contrast * 0.28 + detail * 0.38
    }

    private static func importantRegionEdgePenalty(_ rect: CGRect) -> Double {
        let left = max(0, 0.035 - rect.minX)
        let right = max(0, rect.maxX - 0.965)
        let top = max(0, 0.035 - rect.minY)
        let bottom = max(0, rect.maxY - 0.965)
        return Double(left + right + top + bottom) * 1.8
    }

    private static func topLeftRect(_ visionRect: CGRect) -> CGRect {
        clipped(CGRect(
            x: visionRect.minX,
            y: 1 - visionRect.maxY,
            width: visionRect.width,
            height: visionRect.height
        ))
    }

    private static func center(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func clipped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(0.98, max(0.02, point.x)),
            y: min(0.98, max(0.02, point.y))
        )
    }

    private static func clipped(_ rect: CGRect) -> CGRect {
        let x = min(1, max(0, rect.minX))
        let y = min(1, max(0, rect.minY))
        return CGRect(
            x: x,
            y: y,
            width: min(1 - x, max(0, rect.width)),
            height: min(1 - y, max(0, rect.height))
        )
    }
}

private enum LaraDepthSubjectKind {
    case person
    case foreground

    var localizedTitle: String {
        switch self {
        case .person:
            return LaraL10n.text(en: "Person depth", es: "Profundidad de persona")
        case .foreground:
            return LaraL10n.text(en: "Subject depth", es: "Profundidad de sujeto")
        }
    }
}

private struct LaraDepthResult {
    let background: UIImage
    let subject: UIImage
    let composite: UIImage
    let kind: LaraDepthSubjectKind
    let coverage: Double
}

private enum LaraDepthEngine {
    private static let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false
    ])

    static func create(
        maskSource: UIImage,
        styledImage: UIImage,
        intensity: EagleComposerIntensity
    ) -> LaraDepthResult? {
        guard let maskCG = maskSource.laraComposerNormalized.cgImage,
              let styledCG = styledImage.laraComposerNormalized.cgImage else {
            return nil
        }

        let inputExtent = CGRect(
            x: 0,
            y: 0,
            width: styledCG.width,
            height: styledCG.height
        )
        guard let generated = generateMask(from: maskCG),
              let preparedMask = prepare(
                mask: generated.mask,
                for: inputExtent
              ) else {
            return nil
        }

        let statistics = maskStatistics(preparedMask, extent: inputExtent)
        guard statistics.coverage >= 0.025,
              statistics.coverage <= 0.72,
              statistics.unsafeEdgeRatio <= 0.48 else {
            return nil
        }

        let input = CIImage(cgImage: styledCG)
        let clear = CIImage(color: .clear).cropped(to: inputExtent)
        guard let subjectCI = blend(
            foreground: input,
            background: clear,
            mask: preparedMask
        ) else {
            return nil
        }

        let blurRadius: CGFloat
        switch intensity {
        case .soft: blurRadius = 5
        case .balanced: blurRadius = 9
        case .bold: blurRadius = 14
        }
        let backgroundCI = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: inputExtent)

        let compositeCI = subjectCI.composited(over: backgroundCI).cropped(to: inputExtent)
        guard let background = image(from: backgroundCI, extent: inputExtent),
              let subject = image(from: subjectCI, extent: inputExtent),
              let composite = image(from: compositeCI, extent: inputExtent) else {
            return nil
        }

        return LaraDepthResult(
            background: background,
            subject: subject,
            composite: composite,
            kind: generated.kind,
            coverage: statistics.coverage
        )
    }

    private static func generateMask(
        from image: CGImage
    ) -> (mask: CIImage, kind: LaraDepthSubjectKind)? {
        if #available(iOS 17.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                if let observation = request.results?.first,
                   !observation.allInstances.isEmpty {
                    let buffer = try observation.generateScaledMaskForImage(
                        forInstances: observation.allInstances,
                        from: handler
                    )
                    return (CIImage(cvPixelBuffer: buffer), .foreground)
                }
            } catch {
                // Person segmentation below remains available as a safe fallback.
            }
        }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let buffer = request.results?.first?.pixelBuffer else { return nil }
            return (CIImage(cvPixelBuffer: buffer), .person)
        } catch {
            return nil
        }
    }

    private static func prepare(mask: CIImage, for extent: CGRect) -> CIImage? {
        guard mask.extent.width > 0, mask.extent.height > 0 else { return nil }
        let scale = CGAffineTransform(
            scaleX: extent.width / mask.extent.width,
            y: extent.height / mask.extent.height
        )
        return mask
            .transformed(by: scale)
            .cropped(to: extent)
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.25])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.1])
            .cropped(to: extent)
    }

    private static func blend(
        foreground: CIImage,
        background: CIImage,
        mask: CIImage
    ) -> CIImage? {
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        return filter.outputImage
    }

    private static func image(from image: CIImage, extent: CGRect) -> UIImage? {
        guard let cgImage = ciContext.createCGImage(image, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private static func maskStatistics(
        _ mask: CIImage,
        extent: CGRect
    ) -> (coverage: Double, unsafeEdgeRatio: Double) {
        let width = 96
        let height = 96
        var bytes = [UInt8](repeating: 0, count: width * height)
        let sampleExtent = CGRect(x: 0, y: 0, width: width, height: height)
        let sampled = mask
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / extent.width,
                y: CGFloat(height) / extent.height
            ))
            .cropped(to: sampleExtent)
        ciContext.render(
            sampled,
            toBitmap: &bytes,
            rowBytes: width,
            bounds: sampleExtent,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )

        var foreground = 0
        var unsafeEdge = 0
        let edgeWidth = 3
        for y in 0..<height {
            for x in 0..<width {
                guard bytes[y * width + x] > 48 else { continue }
                foreground += 1
                if x < edgeWidth || x >= width - edgeWidth || y >= height - edgeWidth {
                    unsafeEdge += 1
                }
            }
        }
        guard foreground > 0 else { return (0, 1) }
        return (
            Double(foreground) / Double(width * height),
            Double(unsafeEdge) / Double(foreground)
        )
    }
}

@MainActor
private final class LaraMatchStore: ObservableObject {
    static let shared = LaraMatchStore()

    @Published private(set) var matches: [LaraSavedMatch] = []
    private let storageURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaraMatches", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("Matches.plist")
        load()
    }

    func save(
        _ analysis: LaraMatchAnalysis,
        intensity: EagleComposerIntensity
    ) throws {
        guard let thumbnail = analysis.sourceImage.laraMatchThumbnailData else {
            throw LaraMatchError.paletteFailed
        }
        let match = LaraSavedMatch(
            id: UUID(),
            createdAt: Date(),
            name: LaraL10n.text(
                en: "Composer · \(analysis.matchedPack.localizedName)",
                es: "Composer · \(analysis.matchedPack.localizedName)"
            ),
            sourceKind: analysis.sourceKind,
            matchedPackID: analysis.matchedPack.id,
            intensityRawValue: intensity.rawValue,
            tones: analysis.tones.map(LaraMatchStoredTone.init),
            thumbnail: thumbnail
        )
        matches.insert(match, at: 0)
        matches = Array(matches.prefix(8))
        try persist()
    }

    func delete(_ match: LaraSavedMatch) {
        matches.removeAll { $0.id == match.id }
        try? persist()
    }

    func analysis(from match: LaraSavedMatch) -> LaraMatchAnalysis? {
        guard let image = UIImage(data: match.thumbnail),
              let pack = CompleteStylePack.all.first(where: { $0.id == match.matchedPackID }),
              match.tones.count >= 3 else { return nil }
        return LaraMatchAnalysis(
            sourceImage: image,
            sourceKind: match.sourceKind,
            tones: Array(match.tones.prefix(3)).map(\.tone),
            matchedPack: pack,
            smartFocus: LaraSmartFocusAnalyzer.analyze(image)
        )
    }

    func intensity(from match: LaraSavedMatch) -> EagleComposerIntensity {
        match.intensityRawValue.flatMap(EagleComposerIntensity.init(rawValue:)) ?? .balanced
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? PropertyListDecoder().decode([LaraSavedMatch].self, from: data) else {
            return
        }
        matches = decoded
    }

    private func persist() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(matches).write(to: storageURL, options: .atomic)
    }
}

private enum LaraMatchPaletteExtractor {
    private struct Bucket {
        var count = 0
        var red = 0.0
        var green = 0.0
        var blue = 0.0

        var tone: CompleteStyleTone {
            let divisor = Double(max(count, 1))
            return CompleteStyleTone(
                red: red / divisor,
                green: green / divisor,
                blue: blue / divisor
            )
        }
    }

    static func analyze(_ image: UIImage, sourceKind: LaraMatchSourceKind) throws -> LaraMatchAnalysis {
        let normalized = image.laraComposerNormalized
        let sampled = try sample(normalized)
        let tones = curatedTones(from: sampled)
        guard tones.count == 3 else { throw LaraMatchError.paletteFailed }
        let match = CompleteStylePack.all.min { left, right in
            distance(tones, from: left.tones) < distance(tones, from: right.tones)
        } ?? CompleteStylePack.all[0]
        return LaraMatchAnalysis(
            sourceImage: normalized,
            sourceKind: sourceKind,
            tones: tones,
            matchedPack: match,
            smartFocus: LaraSmartFocusAnalyzer.analyze(normalized)
        )
    }

    private static func sample(_ image: UIImage) throws -> [(tone: CompleteStyleTone, weight: Int)] {
        guard let cgImage = image.cgImage else { throw LaraMatchError.paletteFailed }
        let width = 48
        let height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw LaraMatchError.paletteFailed }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [Int: Bucket] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[index + 3] > 180 else { continue }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let key = (Int(red * 7) << 8) | (Int(green * 7) << 4) | Int(blue * 7)
            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            buckets[key] = bucket
        }

        return buckets.values
            .sorted { score($0) > score($1) }
            .map { ($0.tone, $0.count) }
    }

    private static func curatedTones(
        from sampled: [(tone: CompleteStyleTone, weight: Int)]
    ) -> [CompleteStyleTone] {
        guard let first = sampled.first?.tone else { return [] }
        var selected = [first]
        for candidate in sampled.dropFirst() {
            guard selected.allSatisfy({ colorDistance($0, candidate.tone) > 0.18 }) else { continue }
            selected.append(candidate.tone)
            if selected.count == 3 { break }
        }
        while selected.count < 3 {
            let base = selected.last ?? first
            selected.append(shifted(base, amount: Double(selected.count) * 0.16))
        }

        selected.sort { luminance($0) < luminance($1) }
        return [
            adjusted(selected[0], saturation: 0.38, brightness: 0.30),
            adjusted(selected[1], saturation: 0.48, brightness: 0.68),
            adjusted(selected[2], saturation: 0.56, brightness: 0.92)
        ]
    }

    private static func score(_ bucket: Bucket) -> Double {
        let tone = bucket.tone
        let maximum = max(tone.red, tone.green, tone.blue)
        let minimum = min(tone.red, tone.green, tone.blue)
        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
        return Double(bucket.count) * (0.72 + saturation * 0.55)
    }

    private static func adjusted(
        _ tone: CompleteStyleTone,
        saturation minimumSaturation: CGFloat,
        brightness targetBrightness: CGFloat
    ) -> CompleteStyleTone {
        let color = UIColor(red: tone.red, green: tone.green, blue: tone.blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let result = UIColor(
            hue: hue,
            saturation: max(saturation, minimumSaturation),
            brightness: targetBrightness,
            alpha: 1
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        result.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return CompleteStyleTone(red: red, green: green, blue: blue)
    }

    private static func shifted(_ tone: CompleteStyleTone, amount: Double) -> CompleteStyleTone {
        CompleteStyleTone(
            red: min(1, tone.red + amount * 0.45),
            green: min(1, tone.green + amount * 0.25),
            blue: min(1, tone.blue + amount * 0.55)
        )
    }

    private static func distance(_ tones: [CompleteStyleTone], from reference: [CompleteStyleTone]) -> Double {
        tones.reduce(0) { total, tone in
            total + (reference.map { colorDistance(tone, $0) }.min() ?? 1)
        }
    }

    private static func colorDistance(_ lhs: CompleteStyleTone, _ rhs: CompleteStyleTone) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return sqrt(red * red + green * green + blue * blue)
    }

    private static func luminance(_ tone: CompleteStyleTone) -> Double {
        tone.red * 0.2126 + tone.green * 0.7152 + tone.blue * 0.0722
    }
}

private enum EagleComposerIntensity: String, CaseIterable, Identifiable {
    case soft
    case balanced
    case bold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: return LaraL10n.text(en: "Soft", es: "Suave")
        case .balanced: return LaraL10n.text(en: "Balanced", es: "Equilibrado")
        case .bold: return LaraL10n.text(en: "Bold", es: "Intenso")
        }
    }

    var detail: String {
        switch self {
        case .soft:
            return LaraL10n.text(
                en: "Keeps the photo natural with quiet accents.",
                es: "Conserva la foto natural con acentos discretos."
            )
        case .balanced:
            return LaraL10n.text(
                en: "Adds contrast and color without taking over.",
                es: "Añade contraste y color sin dominar la imagen."
            )
        case .bold:
            return LaraL10n.text(
                en: "Uses richer color and a stronger graphic finish.",
                es: "Usa colores más vivos y un acabado gráfico marcado."
            )
        }
    }

    var overlayAlpha: CGFloat {
        switch self {
        case .soft: return 0.10
        case .balanced: return 0.19
        case .bold: return 0.31
        }
    }

    var accentAlpha: CGFloat {
        switch self {
        case .soft: return 0.10
        case .balanced: return 0.20
        case .bold: return 0.34
        }
    }
}

private struct EagleCompositionAssets {
    let wallpaper: UIImage
    let wallpaperBackground: UIImage
    let floatingSubject: UIImage?
    let centeredWallpaper: UIImage
    let card: UIImage
    let passcodeImages: [String: Data]
    let depthKind: LaraDepthSubjectKind?
    let depthCoverage: Double

    var cardData: Data? { card.pngData() }

    var passcodePreviewImages: [String: UIImage] {
        passcodeImages.reduce(into: [:]) { result, item in
            result[item.key] = UIImage(data: item.value)
        }
    }
}

private enum EagleCompositionRenderer {
    static func render(
        analysis: LaraMatchAnalysis,
        intensity: EagleComposerIntensity
    ) throws -> EagleCompositionAssets {
        let focusedBase = renderWallpaperBase(analysis: analysis, usesSmartFocus: true)
        let focusedWallpaper = styleWallpaper(
            focusedBase,
            analysis: analysis,
            intensity: intensity
        )
        let centeredBase = renderWallpaperBase(analysis: analysis, usesSmartFocus: false)
        let centeredWallpaper = styleWallpaper(
            centeredBase,
            analysis: analysis,
            intensity: intensity
        )
        let depth = LaraDepthEngine.create(
            maskSource: focusedBase,
            styledImage: focusedWallpaper,
            intensity: intensity
        )
        let card = renderCard(analysis: analysis, intensity: intensity)
        let digits = renderDigits(analysis: analysis, intensity: intensity)
        guard digits.count == 10 else { throw LaraMatchError.paletteFailed }
        return EagleCompositionAssets(
            wallpaper: depth?.composite ?? focusedWallpaper,
            wallpaperBackground: depth?.background ?? focusedWallpaper,
            floatingSubject: depth?.subject,
            centeredWallpaper: centeredWallpaper,
            card: card,
            passcodeImages: digits,
            depthKind: depth?.kind,
            depthCoverage: depth?.coverage ?? 0
        )
    }

    private static func renderWallpaperBase(
        analysis: LaraMatchAnalysis,
        usesSmartFocus: Bool
    ) -> UIImage {
        let target = AnimatedWallpaperBuilder.recommendedPixelSize()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            drawAspectFill(
                analysis.sourceImage,
                in: CGRect(origin: .zero, size: target),
                focus: usesSmartFocus ? analysis.smartFocus.focusPoint : CGPoint(x: 0.5, y: 0.5),
                outputFocus: usesSmartFocus ? analysis.smartFocus.outputFocusPoint : CGPoint(x: 0.5, y: 0.5)
            )
        }
    }

    private static func styleWallpaper(
        _ base: UIImage,
        analysis: LaraMatchAnalysis,
        intensity: EagleComposerIntensity
    ) -> UIImage {
        let target = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            base.draw(in: CGRect(origin: .zero, size: target))
            let cg = context.cgContext

            cg.setFillColor(analysis.tones[0].uiColor.withAlphaComponent(intensity.overlayAlpha).cgColor)
            cg.fill(CGRect(origin: .zero, size: target))

            drawVerticalGradient(
                in: cg,
                rect: CGRect(origin: .zero, size: target),
                colors: [
                    UIColor.black.withAlphaComponent(0.48),
                    UIColor.clear,
                    analysis.tones[0].uiColor.withAlphaComponent(0.26 + intensity.overlayAlpha)
                ],
                locations: [0, 0.38, 1]
            )
            drawMotif(
                analysis.matchedPack.motif,
                in: CGRect(origin: .zero, size: target),
                color: analysis.tones[2].uiColor.withAlphaComponent(intensity.accentAlpha),
                context: cg
            )
        }
    }

    private static func renderCard(
        analysis: LaraMatchAnalysis,
        intensity: EagleComposerIntensity
    ) -> UIImage {
        let target = CGSize(width: 1016, height: 640)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            let rect = CGRect(origin: .zero, size: target)
            drawAspectFill(
                analysis.sourceImage,
                in: rect,
                focus: analysis.smartFocus.focusPoint,
                outputFocus: CGPoint(x: 0.58, y: 0.52)
            )
            let cg = context.cgContext
            drawHorizontalGradient(
                in: cg,
                rect: rect,
                colors: [
                    analysis.tones[0].uiColor.withAlphaComponent(0.84),
                    analysis.tones[1].uiColor.withAlphaComponent(0.20 + intensity.overlayAlpha),
                    UIColor.clear
                ],
                locations: [0, 0.52, 1]
            )
            drawMotif(
                analysis.matchedPack.motif,
                in: rect,
                color: analysis.tones[2].uiColor.withAlphaComponent(intensity.accentAlpha + 0.08),
                context: cg
            )
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(2)
            cg.stroke(rect.insetBy(dx: 24, dy: 24))
        }
    }

    private static func renderDigits(
        analysis: LaraMatchAnalysis,
        intensity: EagleComposerIntensity
    ) -> [String: Data] {
        let target = CGSize(width: 202, height: 202)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var images: [String: Data] = [:]

        for value in 0...9 {
            let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
                let circle = CGRect(x: 8, y: 8, width: 186, height: 186)
                let cg = context.cgContext
                cg.saveGState()
                cg.addEllipse(in: circle)
                cg.clip()
                drawAspectFill(
                    analysis.sourceImage,
                    in: circle,
                    focus: analysis.smartFocus.focusPoint,
                    outputFocus: CGPoint(x: 0.5, y: 0.5)
                )
                cg.setFillColor(analysis.tones[0].uiColor.withAlphaComponent(0.58 + intensity.overlayAlpha).cgColor)
                cg.fill(circle)
                drawVerticalGradient(
                    in: cg,
                    rect: circle,
                    colors: [
                        analysis.tones[2].uiColor.withAlphaComponent(intensity.accentAlpha),
                        UIColor.black.withAlphaComponent(0.44)
                    ],
                    locations: [0, 1]
                )
                cg.restoreGState()

                cg.setStrokeColor(analysis.tones[2].uiColor.withAlphaComponent(0.88).cgColor)
                cg.setLineWidth(intensity == .bold ? 6 : 4)
                cg.strokeEllipse(in: circle.insetBy(dx: 2, dy: 2))

                let text = String(value) as NSString
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 86, weight: intensity == .soft ? .medium : .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                    .shadow: {
                        let shadow = NSShadow()
                        shadow.shadowColor = UIColor.black.withAlphaComponent(0.48)
                        shadow.shadowBlurRadius = 7
                        shadow.shadowOffset = CGSize(width: 0, height: 2)
                        return shadow
                    }()
                ]
                let textRect = CGRect(x: 0, y: 49, width: target.width, height: 108)
                text.draw(in: textRect, withAttributes: attributes)
            }
            if let data = rendered.pngData() {
                images[String(value)] = data
            }
        }
        return images
    }

    private static func drawAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        focus: CGPoint = CGPoint(x: 0.5, y: 0.5),
        outputFocus: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) {
        let source = image.size
        guard source.width > 0, source.height > 0 else { return }
        let scale = max(rect.width / source.width, rect.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        let desiredX = rect.minX + rect.width * outputFocus.x - size.width * focus.x
        let desiredY = rect.minY + rect.height * outputFocus.y - size.height * focus.y
        let x = min(rect.minX, max(rect.maxX - size.width, desiredX))
        let y = min(rect.minY, max(rect.maxY - size.height, desiredY))
        image.draw(in: CGRect(
            x: x,
            y: y,
            width: size.width,
            height: size.height
        ))
    }

    private static func drawVerticalGradient(
        in context: CGContext,
        rect: CGRect,
        colors: [UIColor],
        locations: [CGFloat]
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }

    private static func drawHorizontalGradient(
        in context: CGContext,
        rect: CGRect,
        colors: [UIColor],
        locations: [CGFloat]
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
    }

    private static func drawMotif(
        _ motif: CompleteStyleMotif,
        in rect: CGRect,
        color: UIColor,
        context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineCap(.round)

        switch motif {
        case .orbit, .bubbles:
            for index in 0..<5 {
                let diameter = rect.width * (0.20 + CGFloat(index) * 0.12)
                let x = rect.maxX - diameter * (0.72 + CGFloat(index) * 0.05)
                let y = rect.minY + rect.height * 0.54 + CGFloat(index) * 34
                context.setLineWidth(index == 0 ? 5 : 2)
                context.strokeEllipse(in: CGRect(x: x, y: y, width: diameter, height: diameter))
            }
        case .ribbons, .prism:
            for index in 0..<4 {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.minX - 80, y: rect.height * 0.58 + CGFloat(index) * 74))
                path.addCurve(
                    to: CGPoint(x: rect.maxX + 80, y: rect.height * 0.44 + CGFloat(index) * 58),
                    controlPoint1: CGPoint(x: rect.width * 0.32, y: rect.height * 0.88),
                    controlPoint2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.18)
                )
                path.lineWidth = CGFloat(5 + index * 3)
                color.withAlphaComponent(color.cgColor.alpha * (1 - CGFloat(index) * 0.15)).setStroke()
                path.stroke()
            }
        case .grid, .circuit:
            context.setLineWidth(2)
            let spacing = max(54, rect.width / 10)
            for x in stride(from: rect.minX, through: rect.maxX, by: spacing) {
                context.move(to: CGPoint(x: x, y: rect.height * 0.58))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for y in stride(from: rect.height * 0.58, through: rect.maxY, by: spacing) {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.strokePath()
        }
    }
}

struct LaraMatchView: View {
    @ObservedObject private var manager = CompleteStyleManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @ObservedObject private var store = LaraMatchStore.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var analysis: LaraMatchAnalysis?
    @State private var composition: EagleCompositionAssets?
    @State private var intensity: EagleComposerIntensity = .balanced
    @State private var renderToken = UUID()
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var includeWallpaper = true
    @State private var includePasscode = true
    @State private var includeCard = true
    @State private var showPreview = false
    @State private var showComponents = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro

                if let analysis, let composition {
                    resultHero(analysis, composition: composition)
                    palette(analysis)
                    intensityControl(analysis)
                    recommendation(analysis, composition: composition)

                    DisclosureGroup(isExpanded: $showComponents) {
                        VStack(spacing: 0) {
                            matchToggle(
                                .wallpaper,
                                detail: LaraL10n.text(en: "Generated from your image", es: "Generado desde tu imagen"),
                                isOn: $includeWallpaper
                            )
                            Divider().padding(.leading, 52)
                            matchToggle(
                                .passcode,
                                detail: LaraL10n.text(en: "Ten coordinated digits", es: "Diez números coordinados"),
                                isOn: $includePasscode
                            )
                            Divider().padding(.leading, 52)
                            matchToggle(
                                .card,
                                detail: LaraL10n.text(en: "Photo artwork with adaptive contrast", es: "Diseño fotográfico con contraste adaptativo"),
                                isOn: $includeCard
                            )
                        }
                        .padding(.top, 8)
                    } label: {
                        Label(
                            LaraL10n.text(en: "What Eagle will apply", es: "Qué aplicará Eagle"),
                            systemImage: "checklist"
                        )
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    actions(analysis, composition: composition)
                } else if analysis != nil {
                    composingCard
                } else {
                    pickerHero
                }

                savedMatches

                Label(
                    LaraL10n.text(
                        en: "Everything is created on your iPhone. Eagle never uploads your photo or video.",
                        es: "Todo se crea en tu iPhone. Eagle nunca sube tu foto ni tu video."
                    ),
                    systemImage: "hand.raised.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .eagleBackdropText()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        // With a composition ready, Apply (and its progress) stays fixed at the bottom; Prepare takes
        // its place until Eagle is ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let analysis, let composition {
                EagleApplyBar(ready: mgr.sbxready, onPrepared: { manager.refreshCompatibility() }) {
                    if manager.isWorking {
                        progressCard
                    }
                    Button { apply(analysis, composition: composition) } label: {
                        Label(LaraL10n.text(en: "Apply composition", es: "Aplicar composición"), systemImage: "wand.and.sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EagleApplyButtonStyle(busy: manager.isWorking))
                    .disabled(
                        manager.isWorking ||
                        !mgr.sbxready ||
                        !(includeWallpaper || includePasscode || includeCard)
                    )
                }
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("Eagle Composer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if analysis != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                    .accessibilityLabel(LaraL10n.text(en: "Choose another photo or video", es: "Elegir otra foto o video"))
                }
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await process(item) }
        }
        .onChange(of: intensity) { _ in
            guard let analysis else { return }
            rebuildComposition(from: analysis)
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let analysis, let composition {
                EagleComposerPreviewView(
                    analysis: analysis,
                    composition: composition,
                    intensity: intensity,
                    includeWallpaper: includeWallpaper,
                    includePasscode: includePasscode,
                    includeCard: includeCard
                ) {
                    apply(analysis, composition: composition)
                }
            }
        }
        .onChange(of: errorMessage) { value in
            guard let value else { return }
            EagleNotifications.shared.result(false, title: "Eagle Composer", message: value)
            errorMessage = nil
        }
        .onChange(of: savedMessage) { value in
            guard let value else { return }
            EagleNotifications.shared.result(true, title: "Eagle Composer", message: value)
            savedMessage = nil
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LaraL10n.text(en: "One image. One complete phone.", es: "Una imagen. Un teléfono completo."))
                .font(.title2.bold())
            Text(LaraL10n.text(
                en: "Smart Focus protects the subject while Eagle creates a wallpaper, passcode, and Wallet card around it.",
                es: "Smart Focus protege al sujeto mientras Eagle crea a su alrededor un fondo, código y tarjeta de Wallet."
            ))
                .foregroundStyle(.secondary)
        }
        .eagleHeaderCard()
    }

    private var pickerHero: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.13))
                        .frame(width: 78, height: 78)
                    if isProcessing {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "camera.filters")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.indigo)
                    }
                }
                VStack(spacing: 4) {
                    Text(isProcessing
                        ? LaraL10n.text(en: "Finding the subject and best composition…", es: "Buscando el sujeto y la mejor composición…")
                        : LaraL10n.text(en: "Choose photo or video", es: "Elegir foto o video"))
                        .font(.headline)
                    Text(LaraL10n.text(en: "A video frame works too", es: "También puedes usar un fotograma de video"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 38)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
                    .foregroundStyle(Color.indigo.opacity(0.25))
            }
        }
        .buttonStyle(EaglePressableStyle())
        .disabled(isProcessing)
    }

    private func resultHero(
        _ analysis: LaraMatchAnalysis,
        composition: EagleCompositionAssets
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: composition.wallpaper)
                .resizable()
                .scaledToFill()
                .frame(height: 280)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Label(analysis.sourceKind.localizedTitle, systemImage: analysis.sourceKind == .video ? "video.fill" : "photo.fill")
                    .font(.caption.weight(.semibold))
                Text(LaraL10n.text(
                    en: "Your \(intensity.title.lowercased()) composition",
                    es: "Tu composición \(intensity.title.lowercased())"
                ))
                    .font(.title2.bold())
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Label(
                composition.depthKind == nil ? "SMART FOCUS" : "EAGLE DEPTH",
                systemImage: composition.depthKind == nil ? "scope" : "square.3.layers.3d"
            )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.48), in: Capsule())
                .padding(14)
        }
    }

    private func intensityControl(_ analysis: LaraMatchAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    LaraL10n.text(en: "Visual strength", es: "Intensidad visual"),
                    systemImage: "dial.medium"
                )
                .font(.headline)
                Spacer()
                Text(intensity.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(analysis.tones[1].color)
            }

            Picker(LaraL10n.text(en: "Visual strength", es: "Intensidad visual"), selection: $intensity) {
                ForEach(EagleComposerIntensity.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(intensity.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.2), value: intensity)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func palette(_ analysis: LaraMatchAnalysis) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(analysis.tones.enumerated()), id: \.offset) { _, tone in
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tone.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }
            }
        }
    }

    private func recommendation(
        _ analysis: LaraMatchAnalysis,
        composition: EagleCompositionAssets
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        composition.depthKind == nil ? "Smart Focus" : "Eagle Depth",
                        systemImage: composition.depthKind == nil
                            ? "viewfinder.circle.fill"
                            : "square.3.layers.3d"
                    )
                        .font(.headline)
                    Text(analysis.smartFocus.localizedSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(composition.depthKind == nil
                    ? LaraL10n.text(en: "ACTIVE", es: "ACTIVO")
                    : LaraL10n.text(en: "DEPTH READY", es: "PROFUNDIDAD LISTA"))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(analysis.tones[1].color.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 8) {
                smartMetric(
                    icon: analysis.smartFocus.faceCount > 0 ? "person.crop.circle.fill" : "scope",
                    value: analysis.smartFocus.faceCount > 0
                        ? LaraL10n.text(
                            en: "\(analysis.smartFocus.faceCount) face\(analysis.smartFocus.faceCount == 1 ? "" : "s")",
                            es: "\(analysis.smartFocus.faceCount) rostro\(analysis.smartFocus.faceCount == 1 ? "" : "s")"
                        )
                        : LaraL10n.text(en: "Main subject", es: "Sujeto principal")
                )
                smartMetric(
                    icon: analysis.sourceKind == .video ? "film.stack.fill" : "crop",
                    value: analysis.sourceKind == .video
                        ? LaraL10n.text(en: "Best of 7 frames", es: "Mejor de 7 cuadros")
                        : LaraL10n.text(en: "3 smart crops", es: "3 recortes inteligentes")
                )
            }

            depthStatus(composition)

            matchSummaryRow(
                .wallpaper,
                value: LaraL10n.text(en: "Subject placed below the clock", es: "Sujeto colocado debajo del reloj"),
                color: analysis.tones[2].color
            )
            matchSummaryRow(
                .passcode,
                value: LaraL10n.text(en: "Adaptive glass digits", es: "Números de vidrio adaptativos"),
                color: analysis.tones[1].color
            )
            matchSummaryRow(
                .card,
                value: LaraL10n.text(en: "Independent subject-aware crop", es: "Recorte independiente consciente del sujeto"),
                color: analysis.tones[0].color
            )
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func depthStatus(_ composition: EagleCompositionAssets) -> some View {
        HStack(spacing: 10) {
            Image(systemName: composition.depthKind == nil
                ? "checkmark.shield.fill"
                : "square.3.layers.3d")
                .foregroundStyle(composition.depthKind == nil ? Color.secondary : Color.indigo)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(composition.depthKind?.localizedTitle ?? LaraL10n.text(
                    en: "Safe flat fallback",
                    es: "Alternativa plana segura"
                ))
                .font(.subheadline.weight(.semibold))
                Text(composition.depthKind == nil
                    ? LaraL10n.text(
                        en: "No reliable mask was forced; Smart Focus remains intact.",
                        es: "No se forzó una máscara poco fiable; Smart Focus permanece intacto."
                    )
                    : LaraL10n.text(
                        en: "Background and subject will be installed as separate PosterBoard layers.",
                        es: "El fondo y el sujeto se instalarán como capas separadas de PosterBoard."
                    ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if composition.depthKind != nil {
                Text("\(Int(composition.depthCoverage * 100))%")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.indigo)
            }
        }
        .padding(12)
        .background(Color.indigo.opacity(composition.depthKind == nil ? 0.04 : 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func smartMetric(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
    }

    private func actions(
        _ analysis: LaraMatchAnalysis,
        composition: EagleCompositionAssets
    ) -> some View {
        VStack(spacing: 10) {
            Button { showPreview = true } label: {
                Label(LaraL10n.text(en: "Full preview", es: "Vista previa completa"), systemImage: "eye.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EagleSecondaryButtonStyle())

            Button {
                do {
                    try store.save(analysis, intensity: intensity)
                    savedMessage = LaraL10n.text(
                        en: "Composition saved. You can find it under My Compositions.",
                        es: "Composición guardada. Puedes recuperarla desde Mis composiciones."
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label(LaraL10n.text(en: "Save to My Compositions", es: "Guardar en Mis composiciones"), systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EaglePressableStyle(kind: .card))
            .font(.subheadline.weight(.semibold))
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var savedMatches: some View {
        if !store.matches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(LaraL10n.text(en: "My Compositions", es: "Mis composiciones"))
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.matches) { match in
                            Button {
                                if let restored = store.analysis(from: match) {
                                    let restoredIntensity = store.intensity(from: match)
                                    intensity = restoredIntensity
                                    analysis = restored
                                    rebuildComposition(from: restored, using: restoredIntensity)
                                }
                            } label: {
                                savedMatchCard(match)
                            }
                            .buttonStyle(EaglePressableStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(match)
                                } label: {
                                    Label(LaraL10n.text(en: "Delete", es: "Eliminar"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func savedMatchCard(_ match: LaraSavedMatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image = UIImage(data: match.thumbnail) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 142, height: 94)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            Text(savedMatchName(match))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(match.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 142, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(manager.stage).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(manager.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: manager.progress)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var composingCard: some View {
        VStack(spacing: 13) {
            ProgressView().controlSize(.large)
            Text(LaraL10n.text(en: "Creating your system…", es: "Creando tu sistema…"))
                .font(.headline)
            Text(LaraL10n.text(
                en: "Preparing a clock-safe wallpaper, ten digits, and a Wallet crop.",
                es: "Preparando un fondo con espacio para el reloj, diez números y un recorte para Wallet."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func savedMatchName(_ match: LaraSavedMatch) -> String {
        let savedIntensity = store.intensity(from: match)
        return "Composer · \(savedIntensity.title)"
    }

    private func matchToggle(
        _ component: CompleteStyleComponent,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: component.systemImage)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 9)
        // The disclosure clips its content at the edge, and the switch draws a little wider than its frame.
        .padding(.trailing, 4)
    }

    private func matchSummaryRow(
        _ component: CompleteStyleComponent,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: component.systemImage)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(component.title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func apply(
        _ analysis: LaraMatchAnalysis,
        composition: EagleCompositionAssets
    ) {
        manager.apply(custom: CompleteCustomStyleSelection(
            title: "Eagle Composer · \(intensity.title)",
            wallpaperImage: includeWallpaper ? composition.wallpaperBackground : nil,
            wallpaperFloatingImage: includeWallpaper ? composition.floatingSubject : nil,
            passcodeImages: includePasscode ? composition.passcodeImages : nil,
            cardImage: includeCard ? composition.cardData : nil,
            visualPackID: analysis.matchedPack.id
        ))
    }

    private func rebuildComposition(
        from analysis: LaraMatchAnalysis,
        using selectedIntensity: EagleComposerIntensity? = nil
    ) {
        let token = UUID()
        renderToken = token
        composition = nil
        let chosenIntensity = selectedIntensity ?? intensity

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try EagleCompositionRenderer.render(
                    analysis: analysis,
                    intensity: chosenIntensity
                )
            }
            DispatchQueue.main.async {
                guard renderToken == token else { return }
                switch result {
                case .success(let rendered):
                    composition = rendered
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func process(_ item: PhotosPickerItem) async {
        isProcessing = true
        errorMessage = nil
        defer {
            isProcessing = false
            pickerItem = nil
        }

        do {
            let supportsImage = item.supportedContentTypes.contains { $0.conforms(to: .image) }
            let supportsVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }

            if supportsImage {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw LaraMatchError.unsupportedSelection
                }
                let result = try LaraMatchPaletteExtractor.analyze(image, sourceKind: .photo)
                analysis = result
                rebuildComposition(from: result)
                return
            }

            if supportsVideo,
               let movie = try await item.loadTransferable(type: LaraMatchMovie.self) {
                defer { try? FileManager.default.removeItem(at: movie.url) }
                let frame = try await bestVideoFrame(from: movie.url)
                let result = try LaraMatchPaletteExtractor.analyze(frame, sourceKind: .video)
                analysis = result
                rebuildComposition(from: result)
                return
            }

            throw LaraMatchError.unsupportedSelection
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bestVideoFrame(from url: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0 else {
            throw LaraMatchError.videoFrameFailed
        }

        let fractions: [Double] = [0.08, 0.20, 0.34, 0.50, 0.66, 0.80, 0.92]
        let times = fractions.map {
            NSValue(time: CMTime(
                seconds: min(max(0, duration.seconds * $0), max(0, duration.seconds - 0.001)),
                preferredTimescale: 600
            ))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var remaining = times.count
            var candidates: [UIImage] = []
            var finalError: Error?

            generator.generateCGImagesAsynchronously(forTimes: times) {
                _, image, _, result, error in
                lock.lock()
                if result == .succeeded, let image {
                    candidates.append(UIImage(cgImage: image).laraComposerNormalized)
                } else {
                    finalError = error ?? finalError
                }
                remaining -= 1
                let finished = remaining == 0
                let completedCandidates = finished ? candidates : []
                let completedError = finalError
                lock.unlock()

                if finished {
                    let ranked = completedCandidates.map {
                        (image: $0, score: LaraSmartFocusAnalyzer.videoFrameScore($0))
                    }
                    if let best = ranked.max(by: { $0.score < $1.score }) {
                        continuation.resume(returning: best.image)
                    } else {
                        continuation.resume(throwing: completedError ?? LaraMatchError.videoFrameFailed)
                    }
                }
            }
        }
    }
}

private struct EagleComposerPreviewView: View {
    let analysis: LaraMatchAnalysis
    let composition: EagleCompositionAssets
    let intensity: EagleComposerIntensity
    let includeWallpaper: Bool
    let includePasscode: Bool
    let includeCard: Bool
    let apply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @GestureState private var revealsCenteredCrop = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(LaraL10n.text(en: "See the system, not separate parts", es: "Mira el sistema, no piezas separadas"))
                            .font(.title2.bold())
                        Text(LaraL10n.text(
                            en: "The clock below is an iOS preview layer. It is not baked into your wallpaper.",
                            es: "El reloj de abajo es una capa de vista previa de iOS. No está dibujado dentro del fondo."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Picker(LaraL10n.text(en: "Screen", es: "Pantalla"), selection: $page) {
                        Text(LaraL10n.text(en: "Lock Screen", es: "Bloqueo")).tag(0)
                        Text(LaraL10n.text(en: "Passcode", es: "Código")).tag(1)
                    }
                    .pickerStyle(.segmented)

                    phonePreview
                        .frame(maxWidth: .infinity)

                    if includeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(LaraL10n.text(en: "Wallet card", es: "Tarjeta de Wallet"), systemImage: "creditcard.fill")
                                .font(.headline)
                            Image(uiImage: composition.card)
                                .resizable()
                                .scaledToFill()
                                .aspectRatio(1.587, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                                }
                        }
                    }

                    HStack(spacing: 8) {
                        previewChip(.wallpaper, enabled: includeWallpaper)
                        previewChip(.passcode, enabled: includePasscode)
                        previewChip(.card, enabled: includeCard)
                    }

                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EagleApplyBar {
                    Button {
                        dismiss()
                        apply()
                    } label: {
                        Label(LaraL10n.text(en: "Apply this composition", es: "Aplicar esta composición"), systemImage: "wand.and.sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EagleApplyButtonStyle())
                }
            }
            .eagleScreenBackdrop()
            .navigationTitle("Eagle Composer · \(intensity.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LaraL10n.text(en: "Close", es: "Cerrar")) { dismiss() }
                }
            }
        }
    }

    private var phonePreview: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 50, style: .continuous)
                    .fill(.black)
                    .frame(width: 286, height: 586)
                    .shadow(color: .black.opacity(0.24), radius: 24, y: 12)

                ZStack {
                    Image(uiImage: revealsCenteredCrop ? composition.centeredWallpaper : composition.wallpaper)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 268, height: 566)
                        .clipped()

                    if page == 0 {
                        lockScreenOverlay
                    } else {
                        passcodeOverlay
                    }
                }
                .frame(width: 268, height: 566)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))

                Capsule()
                    .fill(.black)
                    .frame(width: 86, height: 25)
                    .frame(height: 550, alignment: .top)
            }
            .frame(height: 600)

            Label(
                revealsCenteredCrop
                    ? LaraL10n.text(en: "Centered crop", es: "Recorte centrado")
                    : LaraL10n.text(en: "Hold to compare without Smart Focus", es: "Mantén pulsado para comparar sin Smart Focus"),
                systemImage: revealsCenteredCrop ? "circle.grid.cross" : "hand.tap.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(revealsCenteredCrop ? .orange : .secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .gesture(
                LongPressGesture(minimumDuration: 0.05)
                    .updating($revealsCenteredCrop) { value, state, _ in
                        state = value
                    }
            )
        }
    }

    private var lockScreenOverlay: some View {
        VStack(spacing: 0) {
            Text(LaraL10n.text(en: "Thursday, August 13", es: "jueves, 13 de agosto"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.top, 48)
            Text("9:41")
                .font(.system(size: 66, weight: .thin, design: .rounded))
                .tracking(-3)
            Spacer()
            HStack {
                Image(systemName: "flashlight.off.fill")
                Spacer()
                Image(systemName: "camera.fill")
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 32)
            .padding(.bottom, 25)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.42), radius: 5, y: 2)
    }

    private var passcodeOverlay: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.26))
            VStack(spacing: 11) {
                Text(LaraL10n.text(en: "Enter Passcode", es: "Ingresa el código"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 50)
                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { _ in
                        Circle().stroke(.white, lineWidth: 1.6).frame(width: 10, height: 10)
                    }
                }
                passcodeGrid
                    .padding(.horizontal, 31)
                Spacer(minLength: 12)
            }
        }
    }

    private var passcodeGrid: some View {
        let layout = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", ""]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(Array(layout.enumerated()), id: \.offset) { _, digit in
                if digit.isEmpty {
                    Color.clear.frame(height: 62)
                } else if let data = composition.passcodeImages[digit], let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 62)
                }
            }
        }
    }

    private func previewChip(_ component: CompleteStyleComponent, enabled: Bool) -> some View {
        Label(component.title, systemImage: enabled ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(enabled ? AnyShapeStyle(analysis.tones[1].color) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }
}

struct CompleteStyleComparisonView: View {
    let title: String
    let proposedCardPack: CompleteStylePack
    let proposedPasscodePack: CompleteStylePack

    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentCard: UIImage?
    @State private var currentDigits: [String: UIImage] = [:]
    @State private var reveal: CGFloat = 0.5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Actual frente a nuevo")
                            .font(.title2.bold())
                        Text("Desliza la línea para comparar el diseño de Wallet. Ningún cambio se aplica desde esta pantalla.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    cardComparison

                    VStack(alignment: .leading, spacing: 11) {
                        Text("Código")
                            .font(.headline)
                        HStack(alignment: .top, spacing: 12) {
                            comparisonPasscodeCard(title: LaraL10n.text(en: "Current", es: "Actual")) {
                                CurrentPasscodeGrid(images: currentDigits)
                            }
                            comparisonPasscodeCard(title: LaraL10n.text(en: "New", es: "Nuevo")) {
                                AsyncImage(url: proposedPasscodePack.passcodePreviewURL) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFit()
                                    } else {
                                        ProgressView().tint(.white)
                                    }
                                }
                            }
                        }
                    }

                    Label(
                        mgr.sbxready
                            ? LaraL10n.text(en: "The comparison uses the device's current files.", es: "La comparación usa los archivos actuales del dispositivo.")
                            : LaraL10n.text(en: "Prepare Eagle so it can read the current design.", es: "Prepara el acceso de Eagle para poder leer el diseño actual."),
                        systemImage: mgr.sbxready ? "checkmark.shield.fill" : "lock.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .eagleScreenBackdrop()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear { loadCurrentArtwork() }
        .onChange(of: mgr.sbxready) { ready in
            if ready { loadCurrentArtwork() }
        }
    }

    private var cardComparison: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Tarjeta de Wallet")
                    .font(.headline)
                Spacer()
                Text("ACTUAL")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text("NUEVO")
                    .font(.caption2.bold())
                    .foregroundStyle(proposedCardPack.secondary.color)
            }

            GeometryReader { geometry in
                let proposed = CompleteCardStyleEngine.previewImage(pack: proposedCardPack)
                ZStack(alignment: .leading) {
                    comparisonCardImage(proposed, fallback: proposedCardPack.secondary.color)

                    comparisonCardImage(currentCard, fallback: Color(uiColor: .tertiarySystemFill))
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: geometry.size.width * reveal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                    Rectangle()
                        .fill(.white)
                        .frame(width: 3)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .offset(x: geometry.size.width * reveal - 1.5)

                    Circle()
                        .fill(.white)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.caption.bold())
                                .foregroundStyle(.black)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                        .offset(x: geometry.size.width * reveal - 19)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            reveal = min(0.96, max(0.04, value.location.x / geometry.size.width))
                        }
                )
            }
            .aspectRatio(1.587, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func comparisonCardImage(_ image: UIImage?, fallback: Color) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    fallback
                    Image(systemName: "creditcard")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func comparisonPasscodeCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
        }
        .padding(10)
        .background(.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func loadCurrentArtwork() {
        guard mgr.sbxready else {
            currentCard = nil
            currentDigits = [:]
            return
        }
        currentCard = CompleteCardStyleEngine.currentPreviewImage()
        currentDigits = CompletePasscodeStyleEngine.currentPreviewImages()
    }
}

private struct CurrentPasscodeGrid: View {
    let images: [String: UIImage]
    private let layout = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", ""]

    var body: some View {
        if images.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                Text("No disponible")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.65))
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
                spacing: 5
            ) {
                ForEach(Array(layout.enumerated()), id: \.offset) { _, digit in
                    if digit.isEmpty {
                        Color.clear
                    } else if let image = images[digit] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Circle()
                            .fill(.white.opacity(0.12))
                            .overlay { Text(digit).foregroundStyle(.white) }
                    }
                }
            }
            .padding(6)
        }
    }
}

private extension UIImage {
    var laraComposerNormalized: UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    var laraMatchThumbnailData: Data? {
        let maximum: CGFloat = 1600
        let scale = min(1, maximum / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.jpegData(compressionQuality: 0.88)
    }
}
