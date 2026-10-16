import Foundation

// Recording view construction, not a SwiftUI renderer or gesture dispatcher.
@MainActor protocol View {}
enum Weight { case semibold }
enum Font { case caption; func weight(_ value: Weight) -> Font { self } }
enum ButtonStyle { case bordered }
@MainActor struct Recorded: View {
    var action: (() -> Void)?
    var blocked = false
    var alpha = 1.0
    func font(_ value: Font) -> Recorded { World.log("font.caption.semibold"); return self }
    func frame(maxWidth: Double) -> Recorded { World.log("width.\(maxWidth)"); return self }
    func frame(height: Double) -> Recorded { World.log("height.\(height)"); return self }
    func buttonStyle(_ value: ButtonStyle) -> Recorded { World.log("style.bordered"); return self }
    func disabled(_ value: Bool) -> Recorded {
        World.log("disabled.\(value)"); var copy = self; copy.blocked = value; return copy
    }
    func opacity(_ value: Double) -> Recorded {
        World.log("opacity.\(value)"); var copy = self; copy.alpha = value; return copy
    }
    func accessibilityHint(_ value: String) -> Recorded { World.log("hint.\(value)"); return self }
}
@MainActor func Button(action: @escaping () -> Void, label: () -> Recorded) -> Recorded {
    var result = label(); result.action = action; return result
}
@MainActor func Label(_ title: String, systemImage: String) -> Recorded {
    World.log("label.\(title).\(systemImage)"); return Recorded()
}
@MainActor final class Context {
    var bits = 0
    var flags: UInt32 = 0
    var title = "Island"
    var spanish = false
    var events: [String] = []
    func read(_ name: String, _ mask: Int) -> Bool {
        events.append(name); return bits & mask != 0
    }
    var dsready: Bool { read("ready", 2) }
    var rcSafetyLocked: Bool { read("remote", 8) }
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
@MainActor struct Target {
    let context: Context
    var title: String { context.events.append("title"); return context.title }
}
enum Operation { case remove }
@MainActor protocol Host {
    var context: Context { get }
    associatedtype Content: View
    var restoreButton: Content { get }
}
extension Host {
    var mgr: Context { context }
    var isApplying: Bool { context.read("busy", 1) }
    var applySafetyBlocked: Bool { context.read("local", 4) }
    var selectedFlags: UInt32 { context.events.append("flags"); return context.flags }
    var selectedTarget: Target { Target(context: context) }
    func runAuraOperation(_ operation: Operation, flags: UInt32) {
        context.events.append("restore.\(flags)")
    }
}
@main struct Runner {
    @MainActor static func main() {
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        var scenarios = 0, presses = 0
        for bits in 0..<16 {
            for flags: UInt32 in [0, 1, 32, 33, .max] {
                for spanish in [false, true] {
                    for title in ["Island", "Dock"] {
                        for context in [old.context, owned.context] {
                            context.bits = bits; context.flags = flags
                            context.spanish = spanish; context.title = title; context.events = []
                        }
                        World.context = old.context
                        let a = old.restoreButton as! Recorded
                        World.context = owned.context
                        let b = owned.restoreButton as! Recorded
                        precondition(old.context.events == owned.context.events)
                        precondition(!owned.context.events.contains { $0.hasPrefix("restore.") })
                        let disabled = bits & 1 != 0 || bits & 2 == 0 || flags == 0 || bits & 4 != 0 || bits & 8 != 0
                        let opacity = bits & 2 == 0 || bits & 4 != 0 || bits & 8 != 0 ? 0.52 : 1.0
                        precondition(a.blocked == disabled && b.blocked == disabled)
                        precondition(a.alpha == opacity && b.alpha == opacity)
                        let reads = owned.context.events.filter { ["busy", "ready", "flags", "local", "remote"].contains($0) }
                        var expected = ["busy"]
                        if bits & 1 == 0 {
                            expected.append("ready")
                            if bits & 2 != 0 {
                                expected.append("flags")
                                if flags != 0 {
                                    expected.append("local")
                                    if bits & 4 == 0 { expected.append("remote") }
                                }
                            }
                        }
                        expected.append("ready")
                        if bits & 2 != 0 {
                            expected.append("local")
                            if bits & 4 == 0 { expected.append("remote") }
                        }
                        precondition(reads == expected)
                        precondition(owned.context.events.filter { $0 == "title" }.count == 2)
                        // Invoke only enabled mock controls; verify action flags are read at tap time.
                        if !disabled {
                            for next: UInt32 in [1, 32, 1] {
                                for context in [old.context, owned.context] { context.flags = next; context.events = [] }
                                a.action?(); b.action?()
                                precondition(old.context.events == ["flags", "restore.\(next)"])
                                precondition(old.context.events == owned.context.events)
                                presses += 2
                            }
                        }
                        scenarios += 1
                    }
                }
            }
        }
        print("PASS: \(scenarios) public/owned Restore controls, \(presses) deferred mock actions; all busy/access/flags/lock combinations, both languages/targets and exact lazy reads")
    }
}
