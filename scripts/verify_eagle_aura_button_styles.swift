// Recording Color values verify construction, not SwiftUI pixel rendering.
struct Color: Equatable {
    let name: String
    var alpha: Double = 1
    func opacity(_ value: Double) -> Color { Color(name: name, alpha: value) }
    static let white = Color(name: "white")
    static let black = Color(name: "black")
    static let red = Color(name: "red")
    static let primary = Color(name: "primary")
}
enum Scheme { case light, dark }
@MainActor final class Context {
    var state = 0
    var events: [String] = []
    func read(_ name: String, _ bit: Int) -> Bool {
        events.append(name)
        return state & bit != 0
    }
    var dsready: Bool { read("ready", 4) }
    func theme(_ name: String) -> Color {
        events.append(name)
        return Color(name: name + "-\(state)")
    }
}
@MainActor enum EagleVisualTheme {
    static var context = Context()
    static var actionText: Color { context.theme("text") }
    static var actionFill: Color { context.theme("fill") }
}
@MainActor protocol Host {
    var context: Context { get }
    var applyButtonForeground: Color { get }
    var applyButtonBackground: Color { get }
}
extension Host {
    var isApplyButtonDisabled: Bool { context.read("disabled", 1) }
    var colorScheme: Scheme { context.read("dark", 2) ? .dark : .light }
    var mgr: Context { context }
}
struct Result: Equatable {
    let colors: [Color]
    let events: [String]
}
@MainActor func sample<H: Host>(_ host: H, state: Int) -> Result {
    host.context.state = state
    host.context.events = []
    EagleVisualTheme.context = host.context
    let colors = [host.applyButtonForeground, host.applyButtonBackground]
    return Result(colors: colors, events: host.context.events)
}
@MainActor func golden(_ state: Int) -> Result {
    let disabled = state & 1 != 0, dark = state & 2 != 0, ready = state & 4 != 0
    var events = ["disabled"]
    let text: Color
    if disabled {
        events.append("dark")
        text = dark ? .white.opacity(0.86) : .black.opacity(0.78)
    } else {
        events.append("text")
        text = Color(name: "text-\(state)")
    }
    events.append("ready")
    let fill: Color
    if !ready {
        events.append("dark")
        fill = .red.opacity(dark ? 0.24 : 0.13)
    } else {
        events.append("disabled")
        if disabled {
            events.append("dark")
            fill = .primary.opacity(dark ? 0.14 : 0.09)
        } else {
            events.append("fill")
            fill = Color(name: "fill-\(state)")
        }
    }
    return Result(colors: [text, fill], events: events)
}
@main struct Runner {
    @MainActor static func main() {
        var calls = 0
        for initial in 0..<8 {
            for next in 0..<8 {
                let old = PublicHost(context: Context())
                let owned = OwnedHost(context: Context())
                // Reuse the same adapter while the supplied screen state changes.
                let retained = owned.buttonStyles
                for state in [initial, next, initial, next, next] {
                    let expected = sample(old, state: state)
                    precondition(expected == golden(state))
                    precondition(sample(owned, state: state) == expected)
                    owned.context.events = []
                    let colors = [retained.applyButtonForeground, retained.applyButtonBackground]
                    precondition(Result(colors: colors, events: owned.context.events) == expected)
                    calls += 6
                }
            }
        }
        print("PASS: 64 state transitions, 320 state samples, \(calls) color reads; public/bridge/retained adapter and eight independent goldens")
    }
}
