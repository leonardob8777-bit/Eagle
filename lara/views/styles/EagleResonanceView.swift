import AVFoundation
import Combine
import CryptoKit
import SwiftUI
import UIKit

enum EagleResonanceMode: String, CaseIterable, Identifiable {
    case voice
    case rhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "Voiceprint"
        case .rhythm: return "Tapprint"
        }
    }

    var symbol: String {
        switch self {
        case .voice: return "waveform.and.mic"
        case .rhythm: return "hand.tap.fill"
        }
    }
}

enum EagleResonanceError: LocalizedError {
    case microphoneDenied
    case recordingFailed
    case tooQuiet
    case notEnoughTaps
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return LaraL10n.text(
                en: "Microphone access is off. You can enable it in Settings or use Tapprint without a microphone.",
                es: "El acceso al micrófono está apagado. Puedes activarlo en Ajustes o usar Tapprint sin micrófono."
            )
        case .recordingFailed:
            return LaraL10n.text(
                en: "Eagle could not capture a clean sound sample.",
                es: "Eagle no pudo capturar una muestra de sonido limpia."
            )
        case .tooQuiet:
            return LaraL10n.text(
                en: "The sample was almost silent. Try speaking, humming, or tapping closer to the iPhone.",
                es: "La muestra estaba casi en silencio. Intenta hablar, tararear o tocar más cerca del iPhone."
            )
        case .notEnoughTaps:
            return LaraL10n.text(
                en: "Tap at least five times to create a rhythm signature.",
                es: "Toca al menos cinco veces para crear una firma rítmica."
            )
        case .renderingFailed:
            return LaraL10n.text(
                en: "The visual signature could not be rendered.",
                es: "No se pudo renderizar la firma visual."
            )
        }
    }
}

struct EagleResonanceProfile: Sendable {
    let envelope: [Double]
    let spectrum: [Double]
    let energy: Double
    let complexity: Double
    let primaryHue: Double
    let secondaryHue: Double
    let accentHue: Double
    let fingerprint: String
    let source: EagleResonanceMode
}

struct EagleResonanceAssets {
    let wallpaper: UIImage
    let floatingWave: UIImage
    let card: UIImage
    let digits: [String: Data]

    var cardData: Data? { card.pngData() }
}

@MainActor
final class EagleResonanceManager: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isRendering = false
    @Published private(set) var level: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var taps: [TimeInterval] = []
    @Published private(set) var profile: EagleResonanceProfile?
    @Published private(set) var assets: EagleResonanceAssets?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?
    private let maximumDuration = 4.0

    override init() {
        super.init()
        let temporary = FileManager.default.temporaryDirectory
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: temporary,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in leftovers where url.lastPathComponent.hasPrefix("EagleResonance-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func reset() {
        if isRecording { cancelRecording() }
        taps = []
        profile = nil
        assets = nil
        errorMessage = nil
        level = 0
        elapsed = 0
    }

    func cancelRecording() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func startVoiceprint() {
        guard !isRecording, !isRendering else { return }
        errorMessage = nil
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            beginAuthorizedRecording()
        case .denied:
            errorMessage = EagleResonanceError.microphoneDenied.localizedDescription
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.beginAuthorizedRecording()
                    } else {
                        self.errorMessage = EagleResonanceError.microphoneDenied.localizedDescription
                    }
                }
            }
        @unknown default:
            errorMessage = EagleResonanceError.microphoneDenied.localizedDescription
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0

        let url = recordingURL
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        guard let url else {
            errorMessage = EagleResonanceError.recordingFailed.localizedDescription
            return
        }

        do {
            let samples = try readSamples(from: url)
            try? FileManager.default.removeItem(at: url)
            createProfile(from: samples, source: .voice)
        } catch {
            try? FileManager.default.removeItem(at: url)
            errorMessage = error.localizedDescription
        }
    }

    func addTap() {
        guard !isRecording, !isRendering else { return }
        let now = CACurrentMediaTime()
        if let last = taps.last, now - last > 2.5 {
            taps = []
        }
        taps.append(now)
        level = min(1, 0.35 + Double(taps.count) * 0.055)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.level *= 0.42
        }
    }

    func createTapprint() {
        guard taps.count >= 5 else {
            errorMessage = EagleResonanceError.notEnoughTaps.localizedDescription
            return
        }
        let first = taps[0]
        let relative = taps.map { $0 - first }
        let duration = max(relative.last ?? 1, 0.8)
        let count = 8_192
        var samples = [Float](repeating: 0, count: count)

        for (index, time) in relative.enumerated() {
            let center = min(count - 1, Int((time / duration) * Double(count - 1)))
            let strength = Float(0.65 + Double(index % 4) * 0.10)
            let radius = 150
            for offset in -radius...radius {
                let position = center + offset
                guard samples.indices.contains(position) else { continue }
                let distance = Float(abs(offset)) / Float(radius)
                let decay = max(0, 1 - distance)
                let pulse = sin(Float(offset) * 0.23) * decay * strength
                samples[position] += pulse
            }
        }
        createProfile(from: samples, source: .rhythm)
    }

    private func beginAuthorizedRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("EagleResonance-\(UUID().uuidString)")
                .appendingPathExtension("caf")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw EagleResonanceError.recordingFailed
            }
            self.recorder = recorder
            recordingURL = url
            elapsed = 0
            level = 0
            profile = nil
            assets = nil
            isRecording = true

            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(
                timeInterval: 0.05,
                target: self,
                selector: #selector(updateMeter),
                userInfo: nil,
                repeats: true
            )
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }

    @objc private func updateMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        level = max(0, min(1, (decibels + 58) / 58))
        elapsed = recorder.currentTime
        if recorder.currentTime >= maximumDuration {
            stopRecording()
        }
    }

    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let capacity = AVAudioFrameCount(file.length)
        guard capacity > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: capacity
              ) else {
            throw EagleResonanceError.recordingFailed
        }
        try file.read(into: buffer)
        guard let pointer = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            throw EagleResonanceError.recordingFailed
        }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength)))
    }

    private func createProfile(from samples: [Float], source: EagleResonanceMode) {
        isRendering = true
        errorMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            do {
                let profile = try EagleResonanceAnalyzer.analyze(samples, source: source)
                let assets = try EagleResonanceRenderer.render(profile)
                self.profile = profile
                self.assets = assets
                self.isRendering = false
            } catch {
                self.isRendering = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

enum EagleResonanceAnalyzer {
    static func analyze(
        _ rawSamples: [Float],
        source: EagleResonanceMode
    ) throws -> EagleResonanceProfile {
        guard rawSamples.count >= 512 else { throw EagleResonanceError.recordingFailed }
        let stride = max(1, rawSamples.count / 12_000)
        var samples = Swift.stride(from: 0, to: rawSamples.count, by: stride).map {
            Double(rawSamples[$0])
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        for index in samples.indices { samples[index] -= mean }

        let energy = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
        guard energy > 0.0015 else { throw EagleResonanceError.tooQuiet }
        let difference = zip(samples.dropFirst(), samples).reduce(0) {
            $0 + abs($1.0 - $1.1)
        } / Double(max(1, samples.count - 1))
        let complexity = min(1, difference / max(energy * 1.75, 0.0001))

        let envelopeCount = 96
        let binSize = max(1, samples.count / envelopeCount)
        var envelope: [Double] = []
        for bin in 0..<envelopeCount {
            let start = min(samples.count - 1, bin * binSize)
            let end = min(samples.count, start + binSize)
            let value = samples[start..<end].reduce(0) { $0 + abs($1) } / Double(max(1, end - start))
            envelope.append(value)
        }
        normalize(&envelope)

        let frequencies: [Double] = [0.012, 0.018, 0.028, 0.043, 0.065, 0.095, 0.14, 0.20, 0.27, 0.34, 0.41, 0.47]
        var spectrum = frequencies.map { goertzel(samples, normalizedFrequency: $0) }
        normalize(&spectrum)

        var fingerprintBytes = envelope.map { UInt8(max(0, min(255, Int($0 * 255)))) }
        fingerprintBytes += spectrum.map { UInt8(max(0, min(255, Int($0 * 255)))) }
        fingerprintBytes.append(UInt8(max(0, min(255, Int(energy * 900)))))
        fingerprintBytes.append(UInt8(max(0, min(255, Int(complexity * 255)))))
        let digest = Array(SHA256.hash(data: Data(fingerprintBytes)))
        let fingerprint = digest.prefix(6).map { String(format: "%02X", $0) }.joined()
        let primary = Double(digest[0]) / 255
        let secondary = (primary + 0.16 + Double(digest[1]) / 510).truncatingRemainder(dividingBy: 1)
        let accent = (primary + 0.48 + Double(digest[2]) / 765).truncatingRemainder(dividingBy: 1)

        return EagleResonanceProfile(
            envelope: envelope,
            spectrum: spectrum,
            energy: min(1, energy * 7.5),
            complexity: complexity,
            primaryHue: primary,
            secondaryHue: secondary,
            accentHue: accent,
            fingerprint: fingerprint,
            source: source
        )
    }

    private static func goertzel(_ samples: [Double], normalizedFrequency: Double) -> Double {
        let omega = 2 * Double.pi * normalizedFrequency
        let coefficient = 2 * cos(omega)
        var first = 0.0
        var second = 0.0
        for sample in samples {
            let next = sample + coefficient * first - second
            second = first
            first = next
        }
        return max(0, first * first + second * second - coefficient * first * second)
    }

    private static func normalize(_ values: inout [Double]) {
        guard let maximum = values.max(), maximum > 0 else { return }
        values = values.map { pow(max(0, $0 / maximum), 0.62) }
    }
}

enum EagleResonanceRenderer {
    static func render(_ profile: EagleResonanceProfile) throws -> EagleResonanceAssets {
        let wallpaperSize = AnimatedWallpaperBuilder.recommendedPixelSize()
        let wallpaper = renderWallpaper(profile, size: wallpaperSize)
        let floating = renderFloatingWave(profile, size: wallpaperSize)
        let card = renderCard(profile)
        let digits = renderDigits(profile)
        guard digits.count == 10 else { throw EagleResonanceError.renderingFailed }
        return EagleResonanceAssets(
            wallpaper: wallpaper,
            floatingWave: floating,
            card: card,
            digits: digits
        )
    }

    private static func colors(_ profile: EagleResonanceProfile) -> (UIColor, UIColor, UIColor) {
        (
            UIColor(hue: profile.primaryHue, saturation: 0.72, brightness: 0.34, alpha: 1),
            UIColor(hue: profile.secondaryHue, saturation: 0.78, brightness: 0.72, alpha: 1),
            UIColor(hue: profile.accentHue, saturation: 0.62, brightness: 0.98, alpha: 1)
        )
    }

    private static func renderWallpaper(_ profile: EagleResonanceProfile, size: CGSize) -> UIImage {
        let palette = colors(profile)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            let rect = CGRect(origin: .zero, size: size)
            gradient(cg, rect: rect, colors: [
                UIColor.black,
                palette.0,
                palette.1.withAlphaComponent(0.82)
            ], locations: [0, 0.48, 1])

            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.045).cgColor)
            cg.setLineWidth(1)
            let spacing = max(42, size.width / 13)
            var x: CGFloat = 0
            while x <= size.width {
                cg.move(to: CGPoint(x: x, y: size.height * 0.30))
                cg.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y = size.height * 0.32
            while y <= size.height {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            cg.strokePath()

            let center = CGPoint(x: size.width * 0.72, y: size.height * 0.70)
            for (index, value) in profile.spectrum.enumerated() {
                let radius = size.width * (0.08 + CGFloat(index) * 0.035)
                cg.setStrokeColor(palette.2.withAlphaComponent(0.035 + value * 0.10).cgColor)
                cg.setLineWidth(1 + CGFloat(value) * 4)
                cg.strokeEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
            drawWave(
                profile,
                in: CGRect(x: size.width * 0.06, y: size.height * 0.48, width: size.width * 0.88, height: size.height * 0.30),
                context: cg,
                color: palette.2.withAlphaComponent(0.19),
                lineWidth: max(2, size.width * 0.003),
                phase: 0
            )
            drawFingerprint(profile.fingerprint, in: rect, context: cg, color: UIColor.white.withAlphaComponent(0.40))
        }
    }

    private static func renderFloatingWave(_ profile: EagleResonanceProfile, size: CGSize) -> UIImage {
        let palette = colors(profile)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            let rect = CGRect(x: size.width * 0.055, y: size.height * 0.49, width: size.width * 0.89, height: size.height * 0.29)
            cg.setShadow(offset: .zero, blur: size.width * 0.018, color: palette.2.withAlphaComponent(0.72).cgColor)
            drawWave(profile, in: rect, context: cg, color: palette.2.withAlphaComponent(0.94), lineWidth: max(4, size.width * 0.006), phase: 0)
            drawWave(profile, in: rect.offsetBy(dx: 0, dy: size.height * 0.012), context: cg, color: UIColor.white.withAlphaComponent(0.34), lineWidth: max(1, size.width * 0.002), phase: 9)
        }
    }

    private static func renderCard(_ profile: EagleResonanceProfile) -> UIImage {
        let palette = colors(profile)
        let size = CGSize(width: 1016, height: 640)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            let rect = CGRect(origin: .zero, size: size)
            gradient(cg, rect: rect, colors: [palette.0, palette.1, UIColor.black], locations: [0, 0.58, 1], horizontal: true)
            for (index, value) in profile.spectrum.enumerated() {
                let width = size.width / CGFloat(profile.spectrum.count)
                let bar = CGRect(
                    x: CGFloat(index) * width,
                    y: size.height * (0.10 + CGFloat(1 - value) * 0.36),
                    width: width * 0.62,
                    height: size.height * CGFloat(value) * 0.42
                )
                cg.setFillColor(palette.2.withAlphaComponent(0.08 + value * 0.22).cgColor)
                cg.fill(bar)
            }
            drawWave(profile, in: rect.insetBy(dx: 55, dy: 145), context: cg, color: UIColor.white.withAlphaComponent(0.78), lineWidth: 5, phase: 0)
            drawFingerprint(profile.fingerprint, in: rect, context: cg, color: UIColor.white.withAlphaComponent(0.58))
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.14).cgColor)
            cg.setLineWidth(2)
            cg.stroke(rect.insetBy(dx: 24, dy: 24))
        }
    }

    private static func renderDigits(_ profile: EagleResonanceProfile) -> [String: Data] {
        let palette = colors(profile)
        let size = CGSize(width: 202, height: 202)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var result: [String: Data] = [:]

        for value in 0...9 {
            let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let cg = renderer.cgContext
                let circle = CGRect(x: 8, y: 8, width: 186, height: 186)
                cg.saveGState()
                cg.addEllipse(in: circle)
                cg.clip()
                gradient(cg, rect: circle, colors: [palette.0, palette.1, UIColor.black], locations: [0, 0.58, 1])
                drawWave(
                    profile,
                    in: circle.insetBy(dx: 8, dy: 48),
                    context: cg,
                    color: palette.2.withAlphaComponent(0.48),
                    lineWidth: 3,
                    phase: value * 7
                )
                cg.restoreGState()
                cg.setStrokeColor(palette.2.withAlphaComponent(0.86).cgColor)
                cg.setLineWidth(4)
                cg.strokeEllipse(in: circle.insetBy(dx: 2, dy: 2))

                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let shadow = NSShadow()
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
                shadow.shadowBlurRadius = 7
                shadow.shadowOffset = CGSize(width: 0, height: 2)
                (String(value) as NSString).draw(
                    in: CGRect(x: 0, y: 48, width: size.width, height: 110),
                    withAttributes: [
                        .font: UIFont.monospacedDigitSystemFont(ofSize: 86, weight: .semibold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: paragraph,
                        .shadow: shadow
                    ]
                )
            }
            if let data = image.pngData() { result[String(value)] = data }
        }
        return result
    }

    private static func drawWave(
        _ profile: EagleResonanceProfile,
        in rect: CGRect,
        context: CGContext,
        color: UIColor,
        lineWidth: CGFloat,
        phase: Int
    ) {
        guard profile.envelope.count > 2 else { return }
        let path = CGMutablePath()
        let values = profile.envelope
        for index in values.indices {
            let source = values[(index + phase) % values.count]
            let x = rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width
            let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let y = rect.midY + direction * CGFloat(source) * rect.height * 0.46
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
    }

    private static func gradient(
        _ context: CGContext,
        rect: CGRect,
        colors: [UIColor],
        locations: [CGFloat],
        horizontal: Bool = false
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: horizontal ? CGPoint(x: rect.minX, y: rect.midY) : CGPoint(x: rect.midX, y: rect.minY),
            end: horizontal ? CGPoint(x: rect.maxX, y: rect.midY) : CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }

    private static func drawFingerprint(
        _ fingerprint: String,
        in rect: CGRect,
        context: CGContext,
        color: UIColor
    ) {
        let text = "RESONANCE  \(fingerprint)" as NSString
        text.draw(
            at: CGPoint(x: rect.minX + 30, y: rect.maxY - 54),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: max(12, rect.width * 0.018), weight: .medium),
                .foregroundColor: color,
                .kern: 2.0
            ]
        )
    }
}

struct EagleResonanceView: View {
    @StateObject private var resonance = EagleResonanceManager()
    @ObservedObject private var styleManager = CompleteStyleManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @State private var mode = EagleResonanceMode.voice
    @State private var includeWallpaper = true
    @State private var includePasscode = true
    @State private var includeCard = true

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero

                Picker(
                    LaraL10n.text(en: "Resonance source", es: "Fuente de Resonance"),
                    selection: $mode
                ) {
                    ForEach(EagleResonanceMode.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in resonance.reset() }

                if mode == .voice {
                    voiceprintCard
                } else {
                    tapprintCard
                }

                if resonance.isRendering {
                    renderingCard
                }

                if let profile = resonance.profile,
                   let assets = resonance.assets {
                    resultSection(profile: profile, assets: assets)
                }

                privacyCard
            }
            .padding(20)
        }
        // Once there is a result, Apply stays fixed at the bottom; Prepare takes its place until ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let profile = resonance.profile, let assets = resonance.assets {
                EagleApplyBar(ready: mgr.sbxready, onPrepared: { styleManager.refreshCompatibility() }) {
                    resonanceApplyButton(profile: profile, assets: assets)
                }
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("Resonance")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if resonance.isRecording { resonance.cancelRecording() }
        }
        .eagleNotice(item: $styleManager.lastResult, title: "Resonance") { $0.message }
        .overlay {
            if styleManager.isWorking {
                EagleBlockingProgress(
                    title: styleManager.stage,
                    progress: styleManager.progress
                )
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Spacer()
                Text(LaraL10n.text(en: "LOCAL SIGNAL", es: "SEÑAL LOCAL"))
                    .font(.caption.monospaced().bold())
            }

            ResonanceWaveView(
                values: resonance.profile?.envelope ?? [],
                liveLevel: resonance.level,
                color: .white
            )
            .frame(height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(LaraL10n.text(en: "Turn a sound into identity.", es: "Convierte un sonido en identidad."))
                    .font(.title2.bold())
                Text(LaraL10n.text(
                    en: "One signal becomes a layered wallpaper, ten passcode keys, and Wallet artwork derived from that exact sample.",
                    es: "Una señal se convierte en un fondo por capas, diez teclas y un diseño de Wallet derivado de esa muestra exacta."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.80))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.08, blue: 0.18), .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var voiceprintCard: some View {
        VStack(spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: resonance.isRecording ? "mic.fill" : "waveform.and.mic")
                    .font(.title3)
                    .foregroundStyle(resonance.isRecording ? .red : .purple)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(resonance.isRecording
                         ? LaraL10n.text(en: "Listening…", es: "Escuchando…")
                         : LaraL10n.text(en: "Four-second Voiceprint", es: "Voiceprint de cuatro segundos"))
                        .font(.headline)
                    Text(LaraL10n.text(
                        en: "Speak, hum, laugh, or capture a meaningful sound. Eagle uses its shape—not speech recognition.",
                        es: "Habla, tararea, ríe o captura un sonido especial. Eagle usa su forma, no reconocimiento de voz."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ResonanceMeter(level: resonance.level)
                .frame(height: 54)

            if resonance.isRecording {
                HStack {
                    Text(String(format: "%.1fs", resonance.elapsed))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("4.0s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: resonance.elapsed, total: 4)
                    .tint(.red)
            }

            Button {
                resonance.isRecording
                    ? resonance.stopRecording()
                    : resonance.startVoiceprint()
            } label: {
                Label(
                    resonance.isRecording
                        ? LaraL10n.text(en: "Finish now", es: "Terminar ahora")
                        : LaraL10n.text(en: "Create Voiceprint", es: "Crear Voiceprint"),
                    systemImage: resonance.isRecording ? "stop.fill" : "mic.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(resonance.isRecording ? .red : EagleVisualTheme.actionFill)
            .foregroundStyle(resonance.isRecording ? Color.white : EagleVisualTheme.actionText)
            .disabled(resonance.isRendering)

            errorText
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var tapprintCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(LaraL10n.text(en: "Tap your signature", es: "Marca tu firma"))
                    .font(.headline)
                Text(LaraL10n.text(
                    en: "Tap a rhythm from memory. Five to sixteen beats works best and needs no microphone permission.",
                    es: "Toca un ritmo de memoria. Entre cinco y dieciséis golpes funciona mejor y no necesita micrófono."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                resonance.addTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.pink, .purple, .indigo],
                                center: .topLeading,
                                startRadius: 5,
                                endRadius: 92
                            )
                        )
                    Circle()
                        .stroke(.white.opacity(0.26), lineWidth: 2)
                        .padding(8)
                    VStack(spacing: 5) {
                        Image(systemName: "hand.tap.fill").font(.title)
                        Text(LaraL10n.text(en: "TAP", es: "TOCA"))
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 142, height: 142)
                .scaleEffect(1 + resonance.level * 0.045)
                .animation(.spring(response: 0.18, dampingFraction: 0.55), value: resonance.level)
            }
            .buttonStyle(EaglePressableStyle(kind: .card))

            HStack(spacing: 6) {
                ForEach(0..<min(max(resonance.taps.count, 5), 16), id: \.self) { index in
                    Capsule()
                        .fill(index < resonance.taps.count ? Color.purple : Color.secondary.opacity(0.16))
                        .frame(width: index < resonance.taps.count ? 13 : 8, height: 7)
                }
            }
            .frame(height: 16)

            HStack(spacing: 10) {
                Button(LaraL10n.text(en: "Clear", es: "Borrar")) {
                    resonance.reset()
                }
                .buttonStyle(.bordered)

                Button {
                    resonance.createTapprint()
                } label: {
                    Label(LaraL10n.text(en: "Generate", es: "Generar"), systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(EagleVisualTheme.actionFill)
                // Grey while it waits for enough taps, instead of white on light grey.
                .eagleProminentLabel()
                .disabled(resonance.taps.count < 5 || resonance.isRendering)
            }
            errorText
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var renderingCard: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(LaraL10n.text(en: "Extracting visual DNA…", es: "Extrayendo ADN visual…"))
                .font(.headline)
            Text(LaraL10n.text(
                en: "Mapping energy, rhythm, complexity, and twelve spectral bands.",
                es: "Mapeando energía, ritmo, complejidad y doce bandas espectrales."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func resultSection(
        profile: EagleResonanceProfile,
        assets: EagleResonanceAssets
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LaraL10n.text(en: "Your Resonance", es: "Tu Resonance"))
                        .font(.title3.bold())
                    Text(profile.fingerprint)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    resonance.reset()
                } label: {
                    Label(LaraL10n.text(en: "New", es: "Nueva"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            preview(assets)
            metrics(profile)

            VStack(spacing: 0) {
                resonanceToggle(.wallpaper, detail: LaraL10n.text(en: "Layered waveform", es: "Onda por capas"), isOn: $includeWallpaper)
                Divider().padding(.leading, 43)
                resonanceToggle(.passcode, detail: LaraL10n.text(en: "Ten spectral keys", es: "Diez teclas espectrales"), isOn: $includePasscode)
                Divider().padding(.leading, 43)
                resonanceToggle(.card, detail: LaraL10n.text(en: "Matching Wallet signal", es: "Señal coordinada de Wallet"), isOn: $includeCard)
            }
            .padding(.horizontal, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))

        }
    }

    private func resonanceApplyButton(profile: EagleResonanceProfile, assets: EagleResonanceAssets) -> some View {
        Button {
            apply(profile: profile, assets: assets)
        } label: {
            Label(
                LaraL10n.text(en: "Apply Resonance", es: "Aplicar Resonance"),
                systemImage: "waveform.badge.plus"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(EagleApplyButtonStyle(busy: styleManager.isWorking))
        .disabled(
            !mgr.sbxready ||
            styleManager.isWorking ||
            ![includeWallpaper, includePasscode, includeCard].contains(true)
        )
    }

    private func preview(_ assets: EagleResonanceAssets) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Image(uiImage: assets.wallpaper)
                    .resizable()
                    .scaledToFill()
                Image(uiImage: assets.floatingWave)
                    .resizable()
                    .scaledToFill()
            }
            .frame(width: 112, height: 218)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.24), lineWidth: 2)
            }

            VStack(spacing: 12) {
                Image(uiImage: assets.card)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

                HStack(spacing: 7) {
                    ForEach(["1", "2", "3"], id: \.self) { digit in
                        if let data = assets.digits[digit], let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 52)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func metrics(_ profile: EagleResonanceProfile) -> some View {
        HStack(spacing: 9) {
            resonanceMetric(
                LaraL10n.text(en: "Energy", es: "Energía"),
                value: Int(profile.energy * 100)
            )
            resonanceMetric(
                LaraL10n.text(en: "Texture", es: "Textura"),
                value: Int(profile.complexity * 100)
            )
            VStack(spacing: 3) {
                Text(profile.source.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(LaraL10n.text(en: "Source", es: "Fuente"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }

    private func resonanceMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(value)%").font(.subheadline.monospacedDigit().bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func resonanceToggle(
        _ component: CompleteStyleComponent,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 11) {
                Image(systemName: component.systemImage)
                    .foregroundStyle(.purple)
                    .frame(width: 31)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var errorText: some View {
        if let message = resonance.errorMessage {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.badge.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(LaraL10n.text(en: "Sound leaves no recording", es: "El sonido no deja grabación"))
                    .font(.subheadline.weight(.semibold))
                Text(LaraL10n.text(
                    en: "Voiceprint uses a temporary PCM sample, extracts numbers locally, deletes the sample, and keeps only the generated artwork. Tapprint never opens the microphone.",
                    es: "Voiceprint usa una muestra PCM temporal, extrae números localmente, elimina la muestra y conserva solo el diseño generado. Tapprint nunca abre el micrófono."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(.green.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private func apply(
        profile: EagleResonanceProfile,
        assets: EagleResonanceAssets
    ) {
        styleManager.apply(custom: CompleteCustomStyleSelection(
            title: "Eagle Resonance · \(profile.fingerprint)",
            wallpaperImage: includeWallpaper ? assets.wallpaper : nil,
            wallpaperFloatingImage: includeWallpaper ? assets.floatingWave : nil,
            passcodeImages: includePasscode ? assets.digits : nil,
            cardImage: includeCard ? assets.cardData : nil,
            visualPackID: nil
        ))
    }
}

private struct ResonanceMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<24, id: \.self) { index in
                    let position = Double(index) / 23
                    let shape = 0.25 + abs(sin(position * .pi * 2.8)) * 0.75
                    Capsule()
                        .fill(position <= level ? Color.purple : Color.secondary.opacity(0.13))
                        .frame(
                            width: max(2, (proxy.size.width - 92) / 24),
                            height: max(6, proxy.size.height * CGFloat(shape) * CGFloat(0.45 + level * 0.55))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ResonanceWaveView: View {
    let values: [Double]
    let liveLevel: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let samples = values.isEmpty ? fallbackValues : values
                var path = Path()
                for index in samples.indices {
                    let x = CGFloat(index) / CGFloat(max(1, samples.count - 1)) * size.width
                    let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                    let amplitude = CGFloat(samples[index]) * size.height * 0.42
                    let y = size.height / 2 + direction * amplitude
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color.opacity(0.92)), lineWidth: 2.5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var fallbackValues: [Double] {
        (0..<64).map { index in
            let base = abs(sin(Double(index) * 0.36) * cos(Double(index) * 0.11))
            return 0.12 + base * (0.22 + liveLevel * 0.75)
        }
    }
}
