import Foundation

typealias Preset = (name: String, red: Double, green: Double, blue: Double)
enum Target { case island, dock }

@MainActor enum LaraL10n {
    static var spanish = false
    static var events: [String] = []
    static func text(en: String, es: String) -> String {
        events.append(en + "|" + es)
        return spanish ? es : en
    }
}

@MainActor final class Context {
    var target: Target = .island
    var channels: [Double] = [0.10, 0.78, 1, 0.62, 0.25, 1]
    var events: [String] = []
    var flipOnWrite = false
    func readTarget() -> Target { events.append("target"); return target }
    func read(_ index: Int) -> Double {
        events.append("read:\(index)"); return channels[index]
    }
    func write(_ index: Int, _ value: Double) {
        channels[index] = value
        events.append("write:\(index):\(channels.map(\.bitPattern))")
        // Detect implementations that select the destination again between channels.
        if flipOnWrite { target = target == .island ? .dock : .island }
    }
}

@MainActor protocol Host { var context: Context { get } }
extension Host {
    var selectedTarget: Target { context.readTarget() }
    var islandRed: Double { get { context.read(0) } nonmutating set { context.write(0, newValue) } }
    var islandGreen: Double { get { context.read(1) } nonmutating set { context.write(1, newValue) } }
    var islandBlue: Double { get { context.read(2) } nonmutating set { context.write(2, newValue) } }
    var dockRed: Double { get { context.read(3) } nonmutating set { context.write(3, newValue) } }
    var dockGreen: Double { get { context.read(4) } nonmutating set { context.write(4, newValue) } }
    var dockBlue: Double { get { context.read(5) } nonmutating set { context.write(5, newValue) } }
}

@main struct Check {
    @MainActor static func main() {
        let a = Context(), b = Context()
        let old = PublicHost(context: a), owned = OwnedHost(context: b)
        let inputs: [Double] = [-Double.infinity, -2, -0.0, 0, .leastNonzeroMagnitude,
                                0.002.nextDown, 0.002, 0.002.nextUp, 0.1, 0.5, 0.78,
                                1, 1.nextUp, 2, .greatestFiniteMagnitude, .infinity, .nan]
        var scalarCases = 0, rgbCases = 0, selectionCases = 0, eventCount = 0
        for value in inputs {
            for fallback in inputs {
                precondition(old.sanitize(value, fallback).bitPattern == owned.sanitize(value, fallback).bitPattern)
                scalarCases += 1
            }
            precondition(old.byte(value) == owned.byte(value))
            scalarCases += 1
        }
        for i in 0...255 {
            let midpoint = (Double(i) + 0.5) / 255
            for value in [Double(i) / 255, midpoint.nextDown, midpoint, midpoint.nextUp] {
                precondition(old.byte(value) == owned.byte(value))
                precondition((0...255).contains(owned.byte(value)))
                scalarCases += 1
            }
        }
        precondition(owned.byte(.nan) == 0 && owned.byte(.infinity) == 0)
        precondition(owned.sanitize(.nan, 2) == 2 && owned.sanitize(-2, 2) == 0)
        precondition(owned.sanitize(2, 0) == 1)
        for spanish in [false, true, false] {
            LaraL10n.spanish = spanish; LaraL10n.events = []
            let p = old.palette(), publicEvents = LaraL10n.events
            LaraL10n.events = []
            let q = owned.palette()
            precondition(publicEvents == LaraL10n.events && publicEvents.count == 4)
            precondition(p.count == 4 && q.count == 4)
            precondition(q[0].name == (spanish ? "Azul eléctrico" : "Electric Blue"))
            for index in p.indices {
                precondition(p[index].name == q[index].name)
                precondition(p[index].red == q[index].red && p[index].green == q[index].green && p[index].blue == q[index].blue)
            }
        }
        for target: Target in [.island, .dock] {
            for flip in [false, true] {
                for red in inputs { for green in inputs { for blue in inputs {
                    a.target = target; b.target = target
                    a.flipOnWrite = flip; b.flipOnWrite = flip
                    let before = b.channels.map(\.bitPattern)
                    a.events = []; b.events = []
                    old.set(red, green, blue); owned.set(red, green, blue)
                    precondition(a.channels.map(\.bitPattern) == b.channels.map(\.bitPattern))
                    precondition(a.events == b.events && a.target == b.target)
                    let base = target == .island ? 0 : 3
                    let other = target == .island ? 3 : 0
                    precondition(b.events.count == 4 && b.events[0] == "target")
                    for offset in 0...2 {
                        precondition(b.events[offset + 1].hasPrefix("write:\(base + offset):"))
                        precondition(before[other + offset] == b.channels[other + offset].bitPattern)
                    }
                    eventCount += b.events.count; rgbCases += 1
                } } }
            }
            a.flipOnWrite = false; b.flipOnWrite = false
            for value in inputs {
                a.target = target; b.target = target
                a.channels = [value, value, value, value, value, value]; b.channels = a.channels
                var candidates = owned.palette()
                for delta in [0.0, 0.002.nextDown, 0.002, 0.002.nextUp, -0.002] {
                    candidates.append(("edge", value + delta, value, value))
                    candidates.append(("edge", value, value + delta, value))
                    candidates.append(("edge", value, value, value + delta))
                }
                for candidate in candidates {
                    a.events = []; b.events = []
                    precondition(old.matches(candidate) == owned.matches(candidate))
                    let base = target == .island ? 0 : 3
                    precondition(a.events == b.events && b.events == ["target", "read:\(base)", "read:\(base + 1)", "read:\(base + 2)"])
                    precondition(a.channels.map(\.bitPattern) == b.channels.map(\.bitPattern))
                    eventCount += b.events.count; selectionCases += 1
                }
            }
        }
        // Strict boundary, one RGB snapshot, no palette-channel sanitizing.
        var reads = 0
        for (red, expected) in [(0.002.nextDown, true), (0.002, false), (0.002.nextUp, false), (Double.nan, false)] {
            let matches = EagleAuraStudioColors.presetIsSelected(("boundary", red, 0, 0), selectedRGB: {
                reads += 1; return (0, 0, 0)
            })
            precondition(matches == expected)
        }
        precondition(reads == 4)
        print("PASS: \(scalarCases) scalar cases, \(rgbCases) RGB updates, \(selectionCases) preset selections, \(eventCount) ordered events; 3 language passes and strict boundary assertions")
    }
}
