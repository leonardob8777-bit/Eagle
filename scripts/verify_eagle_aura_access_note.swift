import Foundation

// Recording construction/reads, not SwiftUI pixels or native authorization.
@MainActor protocol View { var recorded: Recorded { get } }
enum Alignment { case top, leading }
enum Weight { case semibold }
enum Font { case title3, subheadline, footnote, caption2
    func weight(_ value: Weight) -> Font { self }
    func monospaced() -> Font { self }
}
enum CornerStyle { case continuous }
enum UIColor { case secondarySystemGroupedBackground }
struct Color {
    let name: String
    var alpha = 1.0
    init(name: String) { self.name = name }
    init(uiColor: UIColor) { name = "grouped" }
    static let primary = Color(name: "primary")
    static let secondary = Color(name: "secondary")
    static let tertiary = Color(name: "tertiary")
    static let orange = Color(name: "orange")
    func opacity(_ value: Double) -> Color { var result = self; result.alpha = value; return result }
    var token: String { "\(name):\(alpha)" }
}
@MainActor struct Recorded: View { var recorded: Recorded { self } }
@MainActor extension View {
    func foregroundStyle(_ color: Color) -> Recorded { World.log("fg.\(color.token)"); return recorded }
    func font(_ value: Font) -> Recorded { World.log("font.\(value)"); return recorded }
    func padding(_ value: Double) -> Recorded { World.log("padding.\(value)"); return recorded }
    func background(_ value: Color) -> Recorded { World.log("background.\(value.token)"); return recorded }
    func clipShape(_ shape: RoundedRectangle) -> Recorded { World.log("clip.\(shape.radius)"); return recorded }
    func overlay(@Builder _ content: () -> Recorded) -> Recorded { _ = content(); World.log("overlay"); return recorded }
}
@resultBuilder @MainActor enum Builder {
    static func buildExpression<V: View>(_ value: V) -> Recorded { value.recorded }
    static func buildBlock(_ items: Recorded...) -> Recorded { Recorded() }
}
@MainActor func HStack(alignment: Alignment, spacing: Double, @Builder content: () -> Recorded) -> Recorded {
    World.log("hstack.\(alignment).\(spacing)"); return content()
}
@MainActor func VStack(alignment: Alignment, spacing: Double, @Builder content: () -> Recorded) -> Recorded {
    World.log("vstack.\(alignment).\(spacing)"); return content()
}
@MainActor func Image(systemName: String) -> Recorded { World.log("image.\(systemName)"); return Recorded() }
@MainActor func Text(_ value: String) -> Recorded { World.log("text.\(value)"); return Recorded() }
@MainActor func Spacer(minLength: Double) -> Recorded { World.log("spacer.\(minLength)"); return Recorded() }
@MainActor struct RoundedRectangle {
    let radius: Double
    init(cornerRadius: Double, style: CornerStyle) { radius = cornerRadius; World.log("shape.\(radius)") }
    func strokeBorder(_ color: Color, lineWidth: Double) -> Recorded {
        World.log("stroke.\(color.token).\(lineWidth)"); return Recorded()
    }
}
@MainActor final class Context {
    var local = [false, false]
    var remote = [false, false]
    var localCursor = 0
    var remoteCursor = 0
    var ready = false
    var zoomed = false
    var title = ""
    var details = ""
    var build = ""
    var channel = ""
    var events: [String] = []
    func localValue() -> Bool {
        events.append("local.\(localCursor)"); defer { localCursor += 1 }; return local[localCursor]
    }
    var rcSafetyLocked: Bool {
        events.append("remote.\(remoteCursor)"); defer { remoteCursor += 1 }; return remote[remoteCursor]
    }
    var dsready: Bool { events.append("ready"); return ready }
}
@MainActor enum World {
    static var context = Context()
    static func log(_ value: String) { context.events.append(value) }
}
@MainActor struct Channel {
    let context: Context
    var title: String { context.events.append("channel"); return context.channel }
}
@MainActor struct Geometry {
    let context: Context
    var isDisplayZoomed: Bool { context.events.append("zoom"); return context.zoomed }
}
@MainActor protocol Host {
    var context: Context { get }
    associatedtype Content: View
    var adaptiveNote: Content { get }
}
extension Host {
    var mgr: Context { context }
    var applySafetyBlocked: Bool { context.localValue() }
    var previewLightColor: Color { context.events.append("light"); return Color(name: "preview") }
    var selectedCapabilityTitle: String { context.events.append("title"); return context.title }
    var selectedCapabilityDescription: String { context.events.append("description"); return context.details }
    var auraEngineBuild: String { context.events.append("build"); return context.build }
    var releaseChannel: Channel { Channel(context: context) }
    var displayGeometry: Geometry { Geometry(context: context) }
}
@main struct Runner {
    @MainActor static func main() {
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        var scenarios = 0
        for bits in 0..<64 {
            for variant in 0..<4 {
                for context in [old.context, owned.context] {
                    context.local = [bits & 1 != 0, bits & 2 != 0]
                    context.remote = [bits & 4 != 0, bits & 8 != 0]
                    context.localCursor = 0; context.remoteCursor = 0
                    context.ready = bits & 16 != 0; context.zoomed = bits & 32 != 0
                    context.title = ["Ready", "Bloqueo activo", "", "Island listo"][variant]
                    context.details = ["Prepare access", "Comparte el informe", "Dock\nIsland", "⚠️"][variant]
                    context.build = ["r57", "", "2026.08.31-r57-trimmed-styles", "ñ"][variant]
                    context.channel = ["Stable", "Laboratory", "Estable", ""][variant]
                    context.events = []
                }
                World.context = old.context; _ = old.adaptiveNote
                World.context = owned.context; _ = owned.adaptiveNote
                precondition(old.context.events == owned.context.events)
                precondition(owned.context.localCursor == 2)
                // Independently compute the short-circuit trace for two separate lock reads.
                var expected = ["local.0"]
                var remoteIndex = 0
                var lockedIcon = owned.context.local[0]
                if !lockedIcon {
                    expected.append("remote.0"); lockedIcon = owned.context.remote[0]; remoteIndex += 1
                }
                if !lockedIcon { expected.append("ready") }
                expected.append("local.1")
                var lockedColor = owned.context.local[1]
                if !lockedColor {
                    expected.append("remote.\(remoteIndex)"); lockedColor = owned.context.remote[remoteIndex]; remoteIndex += 1
                }
                if !lockedColor { expected.append("light") }
                expected += ["title", "description", "build", "channel", "zoom"]
                let reads = owned.context.events.filter {
                    $0.hasPrefix("local.") || $0.hasPrefix("remote.") || ["ready", "light", "title", "description", "build", "channel", "zoom"].contains($0)
                }
                precondition(reads == expected && owned.context.remoteCursor == remoteIndex)
                let icon = lockedIcon ? "exclamationmark.shield.fill" : (owned.context.ready ? "checkmark.shield.fill" : "lock.shield.fill")
                precondition(owned.context.events.contains("image.\(icon)"))
                precondition(owned.context.events.contains(lockedColor ? "fg.orange:1.0" : "fg.preview:1.0"))
                let metadata = "Aura Engine \(owned.context.build) · \(owned.context.channel) · \(owned.context.zoomed ? "Display Zoom" : "Standard")"
                precondition(owned.context.events.contains("text.\(metadata)"))
                scenarios += 1
            }
        }
        print("PASS: \(scenarios) public/owned access notes; changing lock reads, ready/zoom states, exact metadata, lazy color/access reads and reused hosts")
    }
}
