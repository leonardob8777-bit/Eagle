import Foundation
import CoreGraphics

/// Display and frame calculations. Platform measurements and model reads are supplied by the caller.
nonisolated struct EagleAuraStudioDisplayGeometry: Sendable {
    let logicalSize: CGSize
    let nativePixelSize: CGSize
    let standardLogicalSize: CGSize
    let renderScale: CGFloat
    let nativeScale: CGFloat
    let xFactor: CGFloat
    let yFactor: CGFloat
    let isDisplayZoomed: Bool

    func scaleStandardFrame(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x * xFactor,
            y: frame.origin.y * yFactor,
            width: frame.width * xFactor,
            height: frame.height * yFactor
        )
    }

    func compactIslandFrame(readModel: () -> String) -> CGRect {
        let model = readModel()
        let firstGenerationIsland = model == "iPhone15,2" || model == "iPhone15,3"
        let baseY: CGFloat = firstGenerationIsland ? 10 : (model == "iPhone17,3" ? 10 : 13)
        return CGRect(
            x: (logicalSize.width - 134) / 2,
            y: baseY,
            width: 134,
            height: 39
        )
    }

    func dockAuraFrame(readModel: () -> String) -> CGRect {
        let firstGenerationIsland = readModel() == "iPhone15,2" ||
            readModel() == "iPhone15,3"
        let inset: CGFloat = firstGenerationIsland ? 18 : 15
        return scaleStandardFrame(CGRect(
            x: inset,
            y: firstGenerationIsland ? 3 : 1,
            width: standardLogicalSize.width - (inset * 2),
            height: firstGenerationIsland ? 90 : 94
        ))
    }

    static func resolve(
        readBounds: () -> CGRect,
        readNativeBounds: () -> CGRect,
        readScale: () -> CGFloat,
        readNativeScale: () -> CGFloat
    ) -> EagleAuraStudioDisplayGeometry {
        let logical = CGSize(
            width: min(readBounds().width, readBounds().height),
            height: max(readBounds().width, readBounds().height)
        )
        let native = CGSize(
            width: min(readNativeBounds().width, readNativeBounds().height),
            height: max(readNativeBounds().width, readNativeBounds().height)
        )
        let renderScale = max(readScale(), 1)
        let nativeScale = max(readNativeScale(), 1)
        let standard = CGSize(
            width: native.width / renderScale,
            height: native.height / renderScale
        )
        let rawX = standard.width > 0 ? logical.width / standard.width : 1
        let rawY = standard.height > 0 ? logical.height / standard.height : 1
        var xFactor = (0.75...1.015).contains(rawX) ? rawX : 1
        var yFactor = (0.75...1.015).contains(rawY) ? rawY : 1
        if xFactor >= 0.985,
           yFactor >= 0.985,
           nativeScale > renderScale * 1.015 {
            let uniformFactor = renderScale / nativeScale
            if (0.75..<0.985).contains(uniformFactor) {
                xFactor = uniformFactor
                yFactor = uniformFactor
            }
        }
        return EagleAuraStudioDisplayGeometry(
            logicalSize: logical,
            nativePixelSize: native,
            standardLogicalSize: standard,
            renderScale: renderScale,
            nativeScale: nativeScale,
            xFactor: xFactor,
            yFactor: yFactor,
            isDisplayZoomed: xFactor < 0.985 || yFactor < 0.985
        )
    }
}
