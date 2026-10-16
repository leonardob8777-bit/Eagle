import Foundation

// Recording framework types test binding semantics and conversion outcomes,
// not UIKit's color-space implementation or SwiftUI's picker UI.
@MainActor struct Binding<Value> {
    let get: () -> Value
    let set: (Value) -> Void
    var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
}
@MainActor struct Color {
    let context: Context
    let channels: [Double]
    let succeeds: Bool
}
@MainActor struct UIColor {
    let color: Color
    init(_ color: Color) {
        self.color = color
        color.context.events.append("resolve")
    }
    func getRed(_ red: inout CGFloat, green: inout CGFloat,
                blue: inout CGFloat, alpha: inout CGFloat) -> Bool {
        precondition(red == 0 && green == 0 && blue == 0 && alpha == 0)
        color.context.events.append("convert.\(color.succeeds)")
        red = CGFloat(color.channels[0]); green = CGFloat(color.channels[1])
        blue = CGFloat(color.channels[2]); alpha = CGFloat(color.channels[3])
        return color.succeeds
    }
}
@MainActor final class Context {
    var target = 0
    var modes: [EagleAuraStudioMode] = [.glow, .pulse]
    var rgb: [[Double]] = [[0.1, 0.2, 0.3], [0.7, 0.8, 0.9]]
    var events: [String] = []
    var switchOnModeWrite = false
    var snapshot: String {
        "\(target)|\(modes.map(\.rawValue))|\(rgb.map { $0.map(\.bitPattern) })"
    }
}
@MainActor protocol Host {
    var context: Context { get }
    var auraColorBinding: Binding<Color> { get }
}
extension Host {
    var auraColor: Color {
        context.events.append("color.\(context.target)")
        return Color(context: context, channels: context.rgb[context.target] + [1], succeeds: true)
    }
    var selectedMode: EagleAuraStudioMode {
        get {
            context.events.append("mode.\(context.target)")
            return context.modes[context.target]
        }
        nonmutating set {
            context.events.append("writeMode.\(context.target).\(newValue.rawValue)")
            context.modes[context.target] = newValue
            if context.switchOnModeWrite { context.target = 1 - context.target }
        }
    }
    func setSelectedRGB(red: Double, green: Double, blue: Double) {
        context.events.append("writeRGB.\(context.target)")
        context.rgb[context.target] = [red, green, blue]
    }
}
@main struct Runner {
    @MainActor static func main() {
        let inputs: [[Double]] = [[0, 1, 0.5, 0], [0.123, 0.456, 0.789, 0.3],
                                 [-0.0, 2, -1, 1], [.nan, .infinity, -.infinity, 1]]
        var scenarios = 0, setters = 0, getters = 0
        for mode in EagleAuraStudioMode.allCases {
            for target in 0..<2 {
                for succeeds in [false, true] {
                    for switches in [false, true] {
                        for input in inputs {
                            let old = PublicHost(context: Context())
                            let owned = OwnedHost(context: Context())
                            let a = old.auraColorBinding, b = owned.auraColorBinding
                            precondition(old.context.events.isEmpty && owned.context.events.isEmpty)
                            // Retain the same binding while the mode and target change.
                            for step in 0..<4 {
                                let selected = (target + step) % 2
                                for context in [old.context, owned.context] {
                                    context.target = selected
                                    context.modes[selected] = mode
                                    context.switchOnModeWrite = switches
                                    context.events = []
                                }
                                let first = a.wrappedValue, second = b.wrappedValue
                                precondition(first.channels.map(\.bitPattern) == second.channels.map(\.bitPattern))
                                precondition(old.context.events == ["color.\(selected)"])
                                precondition(old.context.events == owned.context.events)
                                getters += 2
                                for context in [old.context, owned.context] { context.events = [] }
                                a.wrappedValue = Color(context: old.context, channels: input, succeeds: succeeds)
                                b.wrappedValue = Color(context: owned.context, channels: input, succeeds: succeeds)
                                precondition(old.context.snapshot == owned.context.snapshot)
                                precondition(old.context.events == owned.context.events)
                                let fixed = mode.rawValue >= 4
                                var expected = ["mode.\(selected)"]
                                if fixed { expected.append("writeMode.\(selected).1") }
                                expected += ["resolve", "convert.\(succeeds)"]
                                let destination = fixed && switches ? 1 - selected : selected
                                if succeeds { expected.append("writeRGB.\(destination)") }
                                precondition(owned.context.events == expected)
                                precondition(owned.context.modes[selected] == (fixed ? .glow : mode))
                                if succeeds {
                                    precondition(owned.context.rgb[destination].map(\.bitPattern) == Array(input.prefix(3)).map(\.bitPattern))
                                }
                                setters += 2
                            }
                            scenarios += 1
                        }
                    }
                }
            }
        }
        print("PASS: \(scenarios) retained-binding scenarios, \(setters) setters, \(getters) getters; all modes/both targets/conversion outcomes, lazy reads and mode-before-conversion goldens")
    }
}
