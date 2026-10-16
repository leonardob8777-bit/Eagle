import Foundation

typealias AuraStudioTarget = EagleAuraStudioTarget
// Construction/interaction recorder, not SwiftUI rendering or real tap dispatch.
@MainActor protocol View { var recorded: Recorded { get } }
enum Weight { case semibold }
enum Font { case caption, system(size: Double, weight: Weight)
    func weight(_ value: Weight) -> Font { self }
}
enum ButtonStyle { case plain }
enum CornerStyle { case continuous }
enum Edge { case horizontal }
enum UIColor { case tertiarySystemGroupedBackground }
struct Color {
    let name: String
    var alpha = 1.0
    init(name: String) { self.name = name }
    init(uiColor: UIColor) { name = "tertiary" }
    static let primary = Color(name: "primary")
    static let clear = Color(name: "clear")
    func opacity(_ value: Double) -> Color { var result = self; result.alpha = value; return result }
    var token: String { "\(name):\(alpha)" }
}
@MainActor final class Control {
    let action: () -> Void
    var disabled = false
    var opacity = 1.0
    init(_ action: @escaping () -> Void) { self.action = action }
}
@MainActor struct Recorded: View {
    var controls: [Control] = []
    var recorded: Recorded { self }
}
@MainActor extension View {
    func font(_ value: Font) -> Recorded { World.log("font.\(value)"); return recorded }
    func foregroundStyle(_ color: Color) -> Recorded { World.log("fg.\(color.token)"); return recorded }
    func frame(width: Double, height: Double) -> Recorded { World.log("size.\(width).\(height)"); return recorded }
    func frame(height: Double) -> Recorded { World.log("height.\(height)"); return recorded }
    func frame(maxWidth: Double) -> Recorded { World.log("maxWidth.\(maxWidth)"); return recorded }
    func background(_ color: Color, in shape: RoundedRectangle) -> Recorded {
        World.log("background.\(color.token).\(shape.radius)"); return recorded
    }
    func overlay(@Builder _ content: () -> Recorded) -> Recorded {
        _ = content(); World.log("overlay"); return recorded
    }
    func lineLimit(_ count: Int) -> Recorded { World.log("lines.\(count)"); return recorded }
    func padding(_ edges: Edge, _ value: Double) -> Recorded { World.log("padding.\(value)"); return recorded }
    func contentShape(_ shape: Rectangle) -> Recorded { World.log("contentShape"); return recorded }
    func buttonStyle(_ value: ButtonStyle) -> Recorded { World.log("plain"); return recorded }
    func disabled(_ value: Bool) -> Recorded {
        World.log("disabled.\(value)"); for control in recorded.controls { control.disabled = value }; return recorded
    }
    func opacity(_ value: Double) -> Recorded {
        World.log("opacity.\(value)"); for control in recorded.controls { control.opacity = value }; return recorded
    }
    func accessibilityLabel(_ value: String) -> Recorded { World.log("label.\(value)"); return recorded }
    func accessibilityValue(_ value: String) -> Recorded { World.log("value.\(value)"); return recorded }
    func accessibilityHint(_ value: String) -> Recorded { World.log("hint.\(value)"); return recorded }
}
@resultBuilder @MainActor enum Builder {
    static func buildExpression<V: View>(_ value: V) -> Recorded { value.recorded }
    static func buildBlock(_ items: Recorded...) -> Recorded { Recorded(controls: items.flatMap(\.controls)) }
}
@MainActor func HStack(spacing: Double, @Builder content: () -> Recorded) -> Recorded {
    World.log("stack.\(spacing)"); return content()
}
@MainActor func ForEach<T, V: View>(_ values: [T], content: (T) -> V) -> Recorded {
    Recorded(controls: values.flatMap { content($0).recorded.controls })
}
@MainActor func Button(action: @escaping () -> Void, @Builder label: () -> Recorded) -> Recorded {
    _ = label(); return Recorded(controls: [Control(action)])
}
@MainActor func Image(systemName: String) -> Recorded { World.log("image.\(systemName)"); return Recorded() }
@MainActor func Text(_ value: String) -> Recorded { World.log("text.\(value)"); return Recorded() }
struct Rectangle {}
@MainActor struct RoundedRectangle {
    let radius: Double
    init(cornerRadius: Double, style: CornerStyle) { radius = cornerRadius; World.log("shape.\(radius)") }
    func strokeBorder(_ color: Color, lineWidth: Double) -> Recorded {
        World.log("stroke.\(color.token).\(lineWidth)"); return Recorded()
    }
}
@MainActor final class Context {
    var editing = false
    var target: AuraStudioTarget = .island
    var available = false
    var busy = false
    var spanish = false
    var modes = ["Glow", "Pulse"]
    var events: [String] = []
    var flipTargetOnIconWrite = false
    var snapshot: String { "\(editing).\(target.rawValue).\(modes)" }
}
@MainActor enum World {
    static var context = Context()
    static func log(_ value: String) { context.events.append(value) }
}
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        World.log("localized"); return World.context.spanish ? es : en
    }
}
struct Mode { let title: String }
@MainActor protocol Host {
    var context: Context { get }
    associatedtype Content: View
    var surfaceProfilesCard: Content { get }
}
extension Host {
    var editingIcons: Bool {
        get { context.events.append("readIcons"); return context.editing }
        nonmutating set {
            context.events.append("writeIcons.\(newValue)"); context.editing = newValue
            if context.flipTargetOnIconWrite { context.target = context.target == .island ? .dock : .island }
        }
    }
    var selectedTarget: AuraStudioTarget {
        get { context.events.append("readTarget"); return context.target }
        nonmutating set { context.events.append("writeTarget.\(newValue.rawValue)"); context.target = newValue }
    }
    var islandProfileAvailable: Bool { context.events.append("available"); return context.available }
    var isApplying: Bool { context.events.append("busy"); return context.busy }
    func mode(for target: AuraStudioTarget) -> Mode {
        context.events.append("mode.\(target.rawValue)"); return Mode(title: context.modes[target.rawValue - 1])
    }
}
@main struct Runner {
    @MainActor static func main() {
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        var scenarios = 0, actions = 0
        for bits in 0..<64 {
            for variant in 0..<4 {
                for context in [old.context, owned.context] {
                    context.editing = bits & 1 != 0
                    context.target = bits & 2 != 0 ? .dock : .island
                    context.available = bits & 4 != 0
                    context.busy = bits & 8 != 0
                    context.spanish = bits & 16 != 0
                    context.flipTargetOnIconWrite = bits & 32 != 0
                    context.modes = [["Glow", "Pulse"], ["Rainbow", "Photo"],
                                     ["Tint", "Glow"], ["Photo", "Rainbow"]][variant]
                    context.events = []
                }
                World.context = old.context
                let a = old.surfaceProfilesCard.recorded
                World.context = owned.context
                let b = owned.surfaceProfilesCard.recorded
                precondition(old.context.events == owned.context.events)
                precondition(a.controls.count == 3 && b.controls.count == 3)
                let trace = owned.context.events
                precondition(!trace.contains { $0.hasPrefix("write") })
                precondition(trace.filter { $0 == "available" }.count == 1)
                precondition(trace.filter { $0 == "readTarget" }.count == (bits & 1 == 0 ? 2 : 0))
                precondition(trace.filter { $0 == "busy" }.count == 3)
                precondition(trace.filter { $0 == "readIcons" }.count == 4)
                for index in 0..<3 {
                    let blocked = bits & 8 != 0 || (index == 0 && bits & 4 == 0)
                    let alpha = index == 0 && bits & 4 == 0 ? 0.64 : 1.0
                    precondition(a.controls[index].disabled == blocked && b.controls[index].disabled == blocked)
                    precondition(a.controls[index].opacity == alpha && b.controls[index].opacity == alpha)
                }
                precondition(trace.contains("image.capsule.fill") && trace.contains("image.dock.rectangle") && trace.contains("image.app.fill"))
                precondition(trace.contains("text.Island") && trace.contains("text.Dock"))
                precondition(trace.contains("text.\(bits & 16 == 0 ? "Icons" : "Iconos")"))
                precondition(trace.contains("value.\(owned.context.modes[0])") && trace.contains("value.\(owned.context.modes[1])"))
                precondition(trace.filter { $0 == "stroke.primary:0.35.1.5" }.count == 1)
                precondition(trace.filter { $0 == "stroke.clear:1.0.1.5" }.count == 2)
                // Reuse the rendered controls for a navigation sequence. Never tap disabled mocks.
                for index in [2, 1, 0, 2, 0, 1] where !b.controls[index].disabled {
                    for context in [old.context, owned.context] { context.events = [] }
                    a.controls[index].action(); b.controls[index].action()
                    let expected = index == 2 ? ["writeIcons.true"] : ["writeIcons.false", "writeTarget.\(index + 1)"]
                    precondition(old.context.events == expected && owned.context.events == expected)
                    precondition(old.context.snapshot == owned.context.snapshot)
                    if index != 2 { precondition(owned.context.target.rawValue == index + 1 && !owned.context.editing) }
                    else { precondition(owned.context.editing) }
                    actions += 2
                }
                scenarios += 1
            }
        }
        print("PASS: \(scenarios) public/owned surface rows, \(actions) deferred mock actions; both targets/languages, icons, hardware/busy guards, accessibility and ordered state writes")
    }
}
