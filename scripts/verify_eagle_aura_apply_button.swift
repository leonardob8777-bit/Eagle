import Foundation

// Record view construction; this is not a SwiftUI renderer or gesture engine.
@MainActor protocol View {}
enum Font { case headline }
enum ButtonStyle { case plain }
struct EagleApplyButtonStyle { let fill: Color? }
enum CornerStyle { case continuous }
enum Scheme { case light, dark }
struct Color {
    let name: String
    var alpha = 1.0
    static let red = Color(name: "red")
    func opacity(_ value: Double) -> Color { Color(name: name, alpha: value) }
    var token: String { "\(name):\(alpha)" }
}
@MainActor struct Recorded: View {
    var action: (() -> Void)?
    var blocked = false
    func font(_ value: Font) -> Recorded { World.log("font.headline"); return self }
    func foregroundStyle(_ value: Color) -> Recorded { World.log("foreground.\(value.token)"); return self }
    func frame(maxWidth: Double) -> Recorded { World.log("width.\(maxWidth)"); return self }
    func frame(height: Double) -> Recorded { World.log("height.\(height)"); return self }
    func background(_ color: Color, in shape: RoundedRectangle) -> Recorded {
        World.log("background.\(color.token).\(shape.radius)"); return self
    }
    func overlay(_ content: () -> Recorded) -> Recorded {
        _ = content(); World.log("overlay"); return self
    }
    func buttonStyle(_ value: ButtonStyle) -> Recorded { World.log("style.plain"); return self }
    func buttonStyle(_ value: EagleApplyButtonStyle) -> Recorded {
        precondition(value.fill == nil)
        World.log("style.eagle"); return self
    }
    func disabled(_ value: Bool) -> Recorded {
        World.log("disabled.\(value)"); var copy = self; copy.blocked = value; return copy
    }
    func accessibilityHint(_ value: String) -> Recorded { World.log("hint.\(value)"); return self }
}
@MainActor struct RoundedRectangle {
    let radius: Double
    init(cornerRadius: Double, style: CornerStyle) { radius = cornerRadius; World.log("shape.\(radius)") }
    func strokeBorder(_ color: Color, lineWidth: Double) -> Recorded {
        World.log("stroke.\(color.token).\(lineWidth)"); return Recorded()
    }
}
@MainActor func Button(action: @escaping () -> Void, label: () -> Recorded) -> Recorded {
    var result = label(); result.action = action; return result
}
@MainActor func Label(_ title: String, systemImage: String) -> Recorded {
    World.log("label.\(title).\(systemImage)"); return Recorded()
}
@MainActor final class Context {
    var ready = [false, false, false]
    var cursor = 0
    var dark = false
    var disabled = false
    var spanish = false
    var mode = 1
    var flags: UInt32 = 1
    var target = "Island"
    var events: [String] = []
    var dsready: Bool {
        events.append("ready.\(cursor)")
        defer { cursor += 1 }
        return ready[cursor]
    }
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
@MainActor enum EagleVisualTheme {
    static func surfaceBorder(for scheme: Scheme) -> Color {
        World.log("surfaceBorder"); return Color(name: scheme == .dark ? "darkBorder" : "lightBorder")
    }
}
@MainActor struct Mode {
    let value: Int
    var title: String { World.log("modeTitle"); return "Mode\(value)" }
}
@MainActor struct Target {
    let context: Context
    var title: String { context.events.append("targetTitle"); return context.target }
}
enum Operation { case apply(Mode) }
@MainActor protocol Host {
    var context: Context { get }
    associatedtype Content: View
    var applyButton: Content { get }
}
extension Host {
    var mgr: Context { context }
    var selectedMode: Mode { context.events.append("mode"); return Mode(value: context.mode) }
    var selectedFlags: UInt32 { context.events.append("flags"); return context.flags }
    var selectedTarget: Target { Target(context: context) }
    var colorScheme: Scheme { context.events.append("scheme"); return context.dark ? .dark : .light }
    var isApplyButtonDisabled: Bool { context.events.append("disabledRead"); return context.disabled }
    var applyButtonForeground: Color { context.events.append("foregroundRead"); return Color(name: "fg") }
    var applyButtonBackground: Color { context.events.append("backgroundRead"); return Color(name: "bg") }
    func runAuraOperation(_ operation: Operation, flags: UInt32) {
        if case .apply(let mode) = operation { context.events.append("apply.\(mode.value).\(flags)") }
    }
}
@main struct Runner {
    @MainActor static func main() {
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        var count = 0, actions = 0
        for pattern in 0..<8 {
            for dark in [false, true] {
                for disabled in [false, true] {
                    for spanish in [false, true] {
                        for target in ["Island", "Dock"] {
                            for mode in [1, 2, 3, 4, 8, 9, 10, 11, 12, 13, 14] {
                                for context in [old.context, owned.context] {
                                    context.ready = (0..<3).map { pattern & (1 << $0) != 0 }
                                    context.cursor = 0; context.dark = dark; context.disabled = disabled
                                    context.spanish = spanish; context.target = target; context.mode = mode; context.events = []
                                }
                                World.context = old.context
                                let a = old.applyButton as! Recorded
                                World.context = owned.context
                                let b = owned.applyButton as! Recorded
                                precondition(old.context.events == owned.context.events)
                                precondition(a.blocked == disabled && b.blocked == disabled)
                                precondition(owned.context.cursor == 3)
                                let events = owned.context.events
                                precondition(!events.contains { $0.hasPrefix("apply.") })
                                precondition(events.filter { $0 == "modeTitle" }.count == (pattern & 1 != 0 ? 2 : 0))
                                precondition(events.filter { $0 == "targetTitle" }.count == 2)
                                let title = pattern & 1 != 0 ? (spanish ? "Aplicar Mode\(mode)" : "Apply Mode\(mode)") : (spanish ? "Se requiere acceso al sistema" : "System Access Required")
                                let icon = pattern & 2 != 0 ? "sparkles" : "lock.shield.fill"
                                precondition(events.contains("label.\(title).\(icon)"))
                                let border = pattern & 4 != 0 ? (dark ? "darkBorder:1.0" : "lightBorder:1.0") : (dark ? "red:0.42" : "red:0.3")
                                precondition(events.contains("stroke.\(border).1.0"))
                                precondition(events.filter { $0 == "surfaceBorder" }.count == (pattern & 4 != 0 ? 1 : 0))
                                if !disabled {
                                    for (next, flags): (Int, UInt32) in [(4, 32), (1, 1)] {
                                        for context in [old.context, owned.context] { context.mode = next; context.flags = flags; context.events = [] }
                                        a.action?(); b.action?()
                                        precondition(old.context.events == ["mode", "flags", "apply.\(next).\(flags)"])
                                        precondition(old.context.events == owned.context.events)
                                        actions += 2
                                    }
                                }
                                count += 1
                            }
                        }
                    }
                }
            }
        }
        print("PASS: \(count) public/owned Apply controls, \(actions) deferred mock actions; changing readiness reads, 11 modes, both schemes/languages/targets, label/border goldens")
    }
}
