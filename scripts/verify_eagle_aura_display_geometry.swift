import Foundation
import CoreGraphics

@MainActor enum Measurements {
    static var bounds = [CGRect.zero]
    static var nativeBounds = [CGRect.zero]
    static var scale: CGFloat = 3
    static var nativeScale: CGFloat = 3
    static var models = [""]
    static var events: [String] = []
    static var boundsIndex = 0, nativeIndex = 0, modelIndex = 0

    static func reset() {
        events = []; boundsIndex = 0; nativeIndex = 0; modelIndex = 0
    }
}

@MainActor struct UIScreen {
    static var main: UIScreen { Measurements.events.append("screen"); return UIScreen() }
    var bounds: CGRect {
        Measurements.events.append("bounds.\(Measurements.boundsIndex)")
        defer { Measurements.boundsIndex += 1 }
        return Measurements.bounds[Measurements.boundsIndex % Measurements.bounds.count]
    }
    var nativeBounds: CGRect {
        Measurements.events.append("native.\(Measurements.nativeIndex)")
        defer { Measurements.nativeIndex += 1 }
        return Measurements.nativeBounds[Measurements.nativeIndex % Measurements.nativeBounds.count]
    }
    var scale: CGFloat { Measurements.events.append("scale"); return Measurements.scale }
    var nativeScale: CGFloat { Measurements.events.append("nativeScale"); return Measurements.nativeScale }
}

@MainActor func devicemachine() -> String {
    Measurements.events.append("model.\(Measurements.modelIndex)")
    defer { Measurements.modelIndex += 1 }
    return Measurements.models[Measurements.modelIndex % Measurements.models.count]
}

func numbers(_ rect: CGRect) -> [CGFloat] { [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height] }
func check(_ old: [CGFloat], _ new: [CGFloat]) {
    precondition(old.count == new.count)
    for (a, b) in zip(old, new) {
        precondition(Double(a).bitPattern == Double(b).bitPattern || (a.isNaN && b.isNaN), "Geometry mismatch: \(a) / \(b)")
    }
}

@main struct Runner {
    @MainActor static func main() {
        let sizes: [CGSize] = [
            .init(width: 393, height: 852), .init(width: 430, height: 932),
            .init(width: 402, height: 874), .init(width: 440, height: 956),
            .init(width: 390, height: 844), .init(width: 375, height: 812),
            .init(width: 428, height: 926), .init(width: 768, height: 1024),
        ]
        let factors: [CGFloat] = [0.749999, 0.75, 0.750001, 0.90, 0.984999, 0.985, 0.985001, 1, 1.014999, 1.015, 1.015001]
        let models = ["iPhone15,2", "iPhone15,3", "iPhone16,1", "iPhone17,1", "iPhone17,3", "iPhone18,1", "unknown", ""]
        var geometries = 0, frames = 0
        func compare() {
            Measurements.reset()
            let old = PublicGeometry.current
            let oldEvents = Measurements.events
            Measurements.reset()
            let owned = AuraStudioDisplayGeometry.current
            precondition(oldEvents == Measurements.events)
            precondition(oldEvents == ["screen", "bounds.0", "bounds.1", "bounds.2", "bounds.3", "native.0", "native.1", "native.2", "native.3", "scale", "nativeScale"])
            check([old.logicalSize.width, old.logicalSize.height, old.nativePixelSize.width, old.nativePixelSize.height,
                   old.standardLogicalSize.width, old.standardLogicalSize.height, old.renderScale, old.nativeScale, old.xFactor, old.yFactor],
                  [owned.logicalSize.width, owned.logicalSize.height, owned.nativePixelSize.width, owned.nativePixelSize.height,
                   owned.standardLogicalSize.width, owned.standardLogicalSize.height, owned.renderScale, owned.nativeScale, owned.xFactor, owned.yFactor])
            precondition(old.isDisplayZoomed == owned.isDisplayZoomed)
            for pattern in models.map({ [$0] }) + [["unknown", "iPhone15,3"], ["iPhone15,2", "unknown"], ["iPhone15,3", "unknown"]] {
                Measurements.models = pattern
                Measurements.reset(); let oldIsland = old.compactIslandFrame; let oldIslandEvents = Measurements.events
                Measurements.reset(); let newIsland = owned.compactIslandFrame
                precondition(oldIslandEvents == Measurements.events)
                check(numbers(oldIsland), numbers(newIsland))
                Measurements.reset(); let oldDock = old.dockAuraFrame; let oldDockEvents = Measurements.events
                Measurements.reset(); let newDock = owned.dockAuraFrame
                precondition(oldDockEvents == Measurements.events)
                check(numbers(oldDock), numbers(newDock))
                frames += 2
            }
            for frame in [CGRect.zero, CGRect(x: -4.5, y: 2.25, width: 382, height: 106), CGRect(x: 18, y: 3, width: 357, height: 90)] {
                check(numbers(old.scaleStandardFrame(frame)), numbers(owned.scaleStandardFrame(frame)))
                frames += 1
            }
            geometries += 1
        }
        for size in sizes {
            for factor in factors {
                for rotation in [false, true] {
                    for (scale, nativeScale): (CGFloat, CGFloat) in [(1, 1), (2, 2), (3, 3), (3, 3.047), (3, 3.05), (3, 3.3), (0, -1)] {
                        let bounds = CGRect(x: 0, y: 0, width: size.width * factor, height: size.height * factor)
                        let native = CGRect(x: 0, y: 0, width: size.width * max(scale, 1), height: size.height * max(scale, 1))
                        Measurements.bounds = [rotation ? CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width) : bounds]
                        Measurements.nativeBounds = [rotation ? CGRect(x: 0, y: 0, width: native.height, height: native.width) : native]
                        Measurements.scale = scale; Measurements.nativeScale = nativeScale
                        compare()
                    }
                }
            }
        }
        // Changing measurements between reads and malformed values retain the old evaluation behavior.
        for value: CGFloat in [0, -1, .infinity, -.infinity, .nan] {
            Measurements.bounds = [.init(x: 0, y: 0, width: value, height: 852), .init(x: 0, y: 0, width: 393, height: 844)]
            Measurements.nativeBounds = [.init(x: 0, y: 0, width: 1179, height: 2556), .init(x: 0, y: 0, width: value, height: 2532)]
            Measurements.scale = value; Measurements.nativeScale = value
            compare()
        }
        // Known device anchors, independent of the copied reference.
        Measurements.bounds = [.init(x: 0, y: 0, width: 393, height: 852)]
        Measurements.nativeBounds = [.init(x: 0, y: 0, width: 1179, height: 2556)]
        Measurements.scale = 3; Measurements.nativeScale = 3; Measurements.models = ["iPhone15,2"]
        Measurements.reset(); let known = AuraStudioDisplayGeometry.current
        precondition(!known.isDisplayZoomed)
        check(numbers(known.compactIslandFrame), [129.5, 10, 134, 39])
        check(numbers(known.dockAuraFrame), [18, 3, 357, 90])
        print("PASS: \(geometries) public/owned display configurations, \(frames) frame comparisons; model/read order, rotation, zoom thresholds, known anchors and nonfinite inputs")
    }
}
