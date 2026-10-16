import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
typealias AuraStudioTarget = EagleAuraStudioTarget
typealias AuraStudioOperation = EagleAuraStudioOperation
typealias GalleryPosition = EagleGalleryPosition

@MainActor final class Context {
    var rgb = [Double](repeating: 0, count: 6)
    var islandPosition = GalleryPosition(x: 0, y: 0)
    var dockPosition = GalleryPosition(x: 0, y: 0)
    var mutateOnRead = false
    var events: [String] = []
    func read(_ index: Int) -> Double {
        events.append("read.\(index)")
        if mutateOnRead && (index == 0 || index == 3) { rgb[index + 1] = 0.3125 }
        return rgb[index]
    }
}
@MainActor enum World { static var context = Context() }
extension EagleGalleryPosition {
    @MainActor static func saved(_ surface: String) -> Self {
        World.context.events.append("position.\(surface)")
        return surface == "island" ? World.context.islandPosition : World.context.dockPosition
    }
}
@MainActor protocol Host {
    var context: Context { get }
    func prepare(_ operationTarget: AuraStudioTarget, _ operation: AuraStudioOperation) -> EagleAuraStudioRequestParameters<GalleryPosition>
}
extension Host {
    var islandRed: Double { context.read(0) }
    var islandGreen: Double { context.read(1) }
    var islandBlue: Double { context.read(2) }
    var dockRed: Double { context.read(3) }
    var dockGreen: Double { context.read(4) }
    var dockBlue: Double { context.read(5) }
    func sanitizedChannel(_ value: Double) -> Double {
        context.events.append("sanitize.\(value.bitPattern)")
        return EagleAuraStudioColors.sanitizedChannel(value)
    }
    func channel255(_ value: Double) -> Int {
        context.events.append("channel.\(value.bitPattern)")
        return EagleAuraStudioColors.channel255(value)
    }
}

@main struct Runner {
    @MainActor static func main() async {
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        let values: [Double] = [-.infinity, .infinity, .nan, -1, -0.0, 0, 0.10, 0.25, 0.5,
            0.78, 1, 1.1, 0.5.nextDown, 0.5.nextUp, 0.5 / 255, 1.5 / 255]
        var count = 0, events = 0
        func compare(_ target: AuraStudioTarget, _ operation: AuraStudioOperation,
                     _ input: [Double], _ mutate: Bool) -> EagleAuraStudioRequestParameters<GalleryPosition> {
            for context in [old.context, owned.context] {
                context.rgb = input; context.events = []; context.mutateOnRead = mutate
                context.islandPosition = GalleryPosition(x: 3.125, y: -2.125)
                context.dockPosition = GalleryPosition(x: -4.125, y: 5.125)
            }
            World.context = old.context
            let a = old.prepare(target, operation)
            World.context = owned.context
            let b = owned.prepare(target, operation)
            precondition(a.position == b.position && a.positionSurface == b.positionSurface)
            precondition(a.red == b.red && a.green == b.green && a.blue == b.blue)
            precondition(old.context.events == owned.context.events)
            let reads = owned.context.events.filter { $0.hasPrefix("read.") }
            precondition(reads == (target == .island ? ["read.0", "read.1", "read.2"] : ["read.3", "read.4", "read.5"]))
            let positions = owned.context.events.filter { $0.hasPrefix("position.") }
            precondition(positions == (operation.isRemoving ? [] : [target == .island ? "position.island" : "position.dock"]))
            precondition(b.positionSurface == (target == .island ? 1 : 0))
            precondition((0...255).contains(b.red) && (0...255).contains(b.green) && (0...255).contains(b.blue))
            precondition(!operation.isRemoving || b.position == GalleryPosition(x: 0, y: 0))
            events += owned.context.events.count; count += 1
            // Captured data does not follow later edits to the draft or the saved position.
            owned.context.rgb = [Double](repeating: 0.91, count: 6)
            owned.context.islandPosition = GalleryPosition(x: 12, y: 12)
            owned.context.dockPosition = GalleryPosition(x: -12, y: -12)
            precondition(b.position == a.position && b.red == a.red && b.green == a.green && b.blue == a.blue)
            return b
        }
        for target in AuraStudioTarget.allCases {
            for removing in [false, true] {
                for mutate in [false, true] {
                    for red in values {
                        for green in values {
                            for blue in values {
                                _ = compare(target, removing ? .remove : .apply(.glow),
                                    [red, green, blue, blue, red, green], mutate)
                            }
                        }
                    }
                }
            }
        }
        for mode in AuraStudioMode.allCases {
            for target in AuraStudioTarget.allCases {
                _ = compare(target, .apply(mode), [0.10, 0.78, 1, 0.62, 0.25, 1], false)
            }
        }
        let anchor = compare(.island, .apply(.glow), [.nan, -.infinity, 2, 1, 1, 1], false)
        precondition(anchor.red == 0 && anchor.green == 0 && anchor.blue == 255)
        precondition(anchor.position == GalleryPosition(x: 3.25, y: -2.25))
        let captured = await Task.detached { [anchor.position.x, anchor.position.y, Double(anchor.red), Double(anchor.green), Double(anchor.blue)] }.value
        precondition(captured == [3.25, -2.25, 0, 0, 255])
        print("PASS: \(count) public/owned preparation cases, \(events) exact reads/conversions; both surfaces, removal without saved reads, 11 modes, nonfinite colors, changing drafts and immutable Sendable values")
    }
}
