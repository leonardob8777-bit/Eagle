import SwiftUI
import UIKit
import CoreImage

// Port of rit3zh/expo-dynamic-notifications: get-notification-layout.ts,
// build-notification-geometry.ts, neck-profile.ts and gooey.tsx.
// Same constants, geometry and alpha matrix. Core Image reproduces Skia's
// render order (blur first, alpha gain/cutoff second) without bundling Skia.
// MIT attribution: NOTICE_Dynamic_Notifications.txt.
struct EagleNotificationLayout {
    let width: CGFloat
    let insetTop: CGFloat
    var cardHeight: CGFloat = 74
    var centerX: CGFloat { width / 2 }
    var islandWidth: CGFloat { 126 }
    var islandHeight: CGFloat { 37.33 }
    var islandTop: CGFloat { max(insetTop - islandHeight - 11, 12) }
    var islandBottom: CGFloat { islandTop + islandHeight }
    var islandRadius: CGFloat { islandHeight / 2 }
    var islandRect: CGRect {
        CGRect(x: centerX - islandWidth / 2, y: islandTop,
               width: islandWidth, height: islandHeight)
    }
    var cardWidth: CGFloat { max(1, min(width - 32, 396)) }
    var cardRadius: CGFloat { cardHeight / 2 }
    var cardTop: CGFloat { islandBottom + 34 }
    var cardCenterY: CGFloat { cardTop + cardHeight / 2 }
    var cardRect: CGRect {
        CGRect(x: centerX - cardWidth / 2, y: cardTop,
               width: cardWidth, height: cardHeight)
    }
    var canvasHeight: CGFloat { cardTop + cardHeight + 96 }
}

struct EagleNotificationGeometry {
    let rect: CGRect
    let radius: CGFloat
    let neck: CGRect
    let shadowOpacity: CGFloat
    let offsetY: CGFloat
    let widthRatio: CGFloat
    /// 0-1 while the neck joins island and drop; the island swells with it.
    let neckProfile: CGFloat

    static func clamp(_ value: CGFloat, _ low: CGFloat = 0, _ high: CGFloat = 1) -> CGFloat {
        min(high, max(low, value))
    }

    init(drop: CGFloat, expand: CGFloat, layout l: EagleNotificationLayout) {
        let grow = 1 - pow(1 - Self.clamp(drop / 0.7), 1.25)
        let t = Self.clamp(drop / 0.82)
        let peak: CGFloat = 1.6 / 3
        let normal = pow(peak, 1.6) * pow(1 - peak, 1.4)
        let profile = t <= 0 || t >= 1 ? 0 : pow(t, 1.6) * pow(1 - t, 1.4) / normal
        let stretch = 1 + 0.38 * profile
        let droplet = 52 * grow
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + expand * (b - a) }
        let w = max(0, min(mix(droplet / stretch, l.cardWidth), l.width - 20))
        let h = max(0, mix(droplet * stretch, l.cardHeight))
        radius = max(0, min(mix(droplet * 0.5, l.cardRadius), min(w, h) / 2))
        let origin = l.islandBottom - l.islandHeight * 0.34
        let cy = origin + drop * (l.cardCenterY - origin)
        let nw = min(60, w) * profile
        let ny = l.islandBottom - l.islandHeight * 0.5
        rect = CGRect(x: l.centerX - w / 2, y: cy - h / 2, width: w, height: h)
        neck = CGRect(x: l.centerX - nw / 2, y: ny, width: nw, height: max(cy - ny, 0))
        shadowOpacity = Self.clamp(expand)
        offsetY = cy - l.cardCenterY
        widthRatio = w / l.cardWidth
        neckProfile = profile
    }
}

/// Reanimated 4.5's duration-based spring translated to SwiftUI's physical
/// spring. The source computes stiffness by bisection so that the spring's
/// energy reaches 6e-9 at 1.5x its perceptual duration; duplicating that step
/// avoids the visibly different timing produced by SwiftUI `response:`.
enum EagleReferenceSpring {
    private static let mass = 4.0
    private static let energyThreshold = 6e-9

    static func animation(milliseconds: Double, dampingRatio: Double) -> Animation {
        let stiffness = matchingStiffness(milliseconds: milliseconds,
                                          dampingRatio: dampingRatio)
        let damping = 2 * dampingRatio * sqrt(stiffness * mass)
        return .interpolatingSpring(mass: mass, stiffness: stiffness,
                                    damping: damping, initialVelocity: 0)
    }

    private static func matchingStiffness(milliseconds: Double,
                                          dampingRatio: Double) -> Double {
        let settlingDuration = milliseconds * 1.5 / 1_000
        func energyDifference(_ stiffness: Double) -> Double {
            let x0 = 1.0
            let v0 = 0.0
            let omega = sqrt(stiffness / mass) * dampingRatio
            let envelope = exp(-omega * settlingDuration)
            let common = x0 + (v0 + x0 * omega) * settlingDuration
            let x = common * envelope
            let v = common * envelope * -omega + (v0 + x0 * omega) * envelope
            let initial = 0.5 * stiffness * x0 * x0 + 0.5 * mass * v0 * v0
            let current = 0.5 * stiffness * x * x + 0.5 * mass * v * v
            return current / initial - energyThreshold
        }

        var low = Double.ulpOfOne
        var high = 8_000.0
        let direction = energyDifference(high) >= energyDifference(low) ? 1.0 : -1.0
        var value = (low + high) / 2
        let precision = energyThreshold * 1e-3
        for _ in 0..<100 {
            if abs(energyDifference(value)) <= precision { break }
            if energyDifference(value) * direction < 0 {
                low = value
            } else {
                high = value
            }
            value = (low + high) / 2
        }
        return value
    }
}

struct EagleNotificationMorph<Content: View>: View, Animatable {
    let layout: EagleNotificationLayout
    var drop: CGFloat
    var expand: CGFloat
    var reveal: CGFloat
    var tint: CGFloat
    var dragY: CGFloat
    /// 1 when the card is white, 0 when it is black (the drop then stays the island's black).
    var cardTone: CGFloat = 1
    @ViewBuilder let content: () -> Content

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(drop, expand), AnimatablePair(reveal, tint)) }
        set {
            drop = newValue.first.first; expand = newValue.first.second
            reveal = newValue.second.first; tint = newValue.second.second
        }
    }

    var body: some View {
        let g = EagleNotificationGeometry(drop: drop, expand: expand, layout: layout)
        let progress = EagleNotificationGeometry.clamp(reveal)
        let overshoot = EagleNotificationGeometry.clamp(g.widthRatio - 1, 0, 0.2)
        let scale = 0.88 + 0.12 * progress + overshoot * progress
        ZStack(alignment: .topLeading) {
            EagleNotificationGooSurface(layout: layout, geometry: g, tint: tint * cardTone)
            .frame(width: layout.width, height: layout.canvasHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // The reference reveals the body through a fading blur; on Eagle it read as blurry, so the
            // body appears sharp: it fades in and settles from 88% scale onto the card.
            content()
                .clipShape(RoundedRectangle(cornerRadius: layout.cardRadius, style: .continuous))
                .opacity(Double(progress))
                .scaleEffect(scale)
                .offset(x: layout.cardRect.minX, y: layout.cardTop + g.offsetY + dragY)
        }
    }
}

private struct EagleNotificationGooSurface: UIViewRepresentable {
    let layout: EagleNotificationLayout
    let geometry: EagleNotificationGeometry
    let tint: CGFloat

    func makeUIView(context: Context) -> EagleNotificationGooView {
        let view = EagleNotificationGooView()
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: EagleNotificationGooView, context: Context) {
        view.update(layout: layout, geometry: geometry, tint: tint)
    }
}

/// Native equivalent of the reference's Skia layer:
/// RoundedRect sources -> Gaussian blur -> alpha matrix -> sharp island.
/// Each animation step renders only the region that holds the island, neck and drop (plus the blur's
/// reach) and hands the image to a layer, so nothing is redrawn on the CPU. The shadow and the sharp
/// island are plain Core Animation layers. Event-driven: no permanent display link.
private final class EagleNotificationGooView: UIView {
    private static let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: NSNull()
    ])
    private static let blur: CGFloat = 5 + 0.62 * (20 - 5) // 14.3, from the reference.

    private let shadowLayer = CALayer()
    private let gooLayer = CALayer()
    private let islandLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let still: [String: CAAction] = ["contents": NSNull(), "frame": NSNull(), "bounds": NSNull(),
                                         "position": NSNull(), "path": NSNull(), "shadowPath": NSNull(),
                                         "shadowOpacity": NSNull()]
        // Skia draws this shadow outside the filtered group with shadowOnly.
        shadowLayer.shadowColor = UIColor(red: 16 / 255, green: 19 / 255, blue: 28 / 255, alpha: 1).cgColor
        shadowLayer.shadowOffset = CGSize(width: 0, height: 10)
        shadowLayer.shadowRadius = 7
        shadowLayer.actions = still
        gooLayer.actions = still
        gooLayer.contentsGravity = .resize
        gooLayer.minificationFilter = .linear
        gooLayer.magnificationFilter = .linear
        // The hardware-aligned pill is deliberately sharp and sits above the goo.
        islandLayer.fillColor = UIColor.black.cgColor
        islandLayer.actions = still
        layer.addSublayer(shadowLayer)
        layer.addSublayer(gooLayer)
        layer.addSublayer(islandLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var last: (EagleNotificationLayout, EagleNotificationGeometry, CGFloat)?

    override func layoutSubviews() {
        super.layoutSubviews()
        // The first update can arrive before the view has a size (and an immediate replacement
        // never sends a second one), so render again once the size is known.
        if let last { update(layout: last.0, geometry: last.1, tint: last.2) }
    }

    func update(layout l: EagleNotificationLayout,
                geometry g: EagleNotificationGeometry,
                tint: CGFloat) {
        last = (l, g, tint)
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // The island swells slightly while the neck pulls a drop out of it (or draws one back in).
        let island = l.islandRect.insetBy(dx: -5 * g.neckProfile, dy: -1.6 * g.neckProfile)
        islandLayer.path = CGPath(roundedRect: island, cornerWidth: island.height / 2,
                                  cornerHeight: island.height / 2, transform: nil)
        let hasDrop = g.rect.width > 0.5 && g.rect.height > 0.5
        shadowLayer.shadowOpacity = hasDrop ? Float(0.20 * g.shadowOpacity) : 0
        if hasDrop {
            shadowLayer.shadowPath = CGPath(roundedRect: g.rect, cornerWidth: g.radius,
                                            cornerHeight: g.radius, transform: nil)
        }

        // Region worth filtering: everything the blur of the island, neck and drop can reach.
        let blur = Self.blur
        var region = island
        if g.neck.width > 0, g.neck.height > 0 { region = region.union(g.neck) }
        if hasDrop { region = region.union(g.rect) }
        region = region.insetBy(dx: -blur * 2.2, dy: -blur * 2.2).intersection(bounds).integral
        guard !region.isEmpty else { gooLayer.contents = nil; return }

        // The goo's edge is a soft ~3 pt ramp after the 14.3 pt blur, so one sample per point is
        // visually lossless and four times cheaper than the screen's 2-3x.
        let scale: CGFloat = 1
        let pixels = CGRect(x: 0, y: 0, width: region.width * scale, height: region.height * scale)
        func ciRect(_ rect: CGRect) -> CGRect {
            // Core Image's origin is bottom-left; the region is top-left.
            CGRect(x: (rect.minX - region.minX) * scale,
                   y: (region.maxY - rect.maxY) * scale,
                   width: rect.width * scale, height: rect.height * scale)
        }
        func rounded(_ rect: CGRect, _ radius: CGFloat, _ color: CIColor) -> CIImage? {
            guard rect.width > 0, rect.height > 0,
                  let filter = CIFilter(name: "CIRoundedRectangleGenerator") else { return nil }
            filter.setValue(CIVector(cgRect: ciRect(rect)), forKey: "inputExtent")
            filter.setValue(radius * scale, forKey: "inputRadius")
            filter.setValue(color, forKey: kCIInputColorKey)
            return filter.outputImage
        }
        let inset = blur * 0.26
        // The drop leaves the island black and turns into the white card (reference interpolateColor).
        let tone = EagleNotificationGeometry.clamp((tint - 0.06) / (0.88 - 0.06))
        var sources = CIImage(color: CIColor.clear).cropped(to: pixels)
        if let shape = rounded(island.insetBy(dx: inset, dy: inset),
                               max(0, island.height / 2 - inset), .black) {
            sources = shape.composited(over: sources)
        }
        if let shape = rounded(g.neck, g.neck.width / 2, .black) {
            sources = shape.composited(over: sources)
        }
        // The cutoff (0.43) grows a lone shape by ~2.5 pt and leaves a soft rim; inset the drop so
        // that, once expanded, the goo sits entirely under the sharp card instead of haloing it.
        let rim = min(3.5, min(g.rect.width, g.rect.height) * 0.1)
        if hasDrop, let shape = rounded(g.rect.insetBy(dx: rim, dy: rim), max(0, g.radius - rim),
                                        CIColor(red: tone, green: tone, blue: tone, alpha: 1)) {
            sources = shape.composited(over: sources)
        }
        let goo = sources
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur * scale])
            .cropped(to: pixels)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 22),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: -22 * 0.43)
            ])
        gooLayer.frame = region
        gooLayer.contentsScale = scale
        gooLayer.contents = Self.ciContext.createCGImage(goo, from: pixels)
    }
}
