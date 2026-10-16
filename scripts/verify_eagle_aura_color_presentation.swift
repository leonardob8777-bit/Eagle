import Foundation

typealias AuraStudioTarget = EagleAuraStudioTarget
typealias AuraStudioMode = EagleAuraStudioMode

// Record constructor arguments bit-for-bit; this does not emulate SwiftUI rendering.
struct Color: Equatable {
    let kind: String
    let channels: [UInt64]
    init(red: Double, green: Double, blue: Double) {
        kind = "rgb"; channels = [red.bitPattern, green.bitPattern, blue.bitPattern]
    }
    init(hue: Double, saturation: Double, brightness: Double) {
        kind = "hsb"; channels = [hue.bitPattern, saturation.bitPattern, brightness.bitPattern]
    }
}

@MainActor final class Context {
    var seed: Int
    var selectedMode: AuraStudioMode
    var changing: Bool
    var events: [String] = []
    var reads = 0
    init(_ seed: Int, _ mode: AuraStudioMode, changing: Bool) {
        self.seed = seed; selectedMode = mode; self.changing = changing
    }
    func index(_ field: String) -> Int {
        let channel = field.hasSuffix("Red") ? 0 : (field.hasSuffix("Green") ? 1 : 2)
        let dock = field.lowercased().contains("dock") ? 3 : 0
        reads += 1
        return seed + channel + dock + (changing ? reads : 0)
    }
    func readDouble(_ field: String) -> Double {
        let values: [Double] = [.nan, .infinity, -.infinity, -2, -0.0, 0, 0.002, 0.25, 0.5, 1, 1.1, 4]
        let value = values[index(field) % values.count]
        events.append(field + "=" + String(value.bitPattern))
        return value
    }
    func readInt(_ field: String) -> Int {
        let values = [Int.min, -256, -1, 0, 1, 127, 254, 255, 256, Int.max]
        let value = values[index(field) % values.count]
        events.append(field + "=" + String(value))
        return value
    }
    func sanitize(_ value: Double) -> Double {
        events.append("sanitize=" + String(value.bitPattern))
        return EagleAuraStudioColors.sanitizedChannel(value)
    }
    func mode(_ target: AuraStudioTarget) -> AuraStudioMode {
        events.append("mode=" + String(target.rawValue) + ":" + String(selectedMode.rawValue))
        return selectedMode
    }
    func hue(_ mode: AuraStudioMode) -> Double {
        events.append("hue=" + String(mode.rawValue))
        return Double(seed % 256) / 255.0
    }
}

@MainActor protocol Host { var context: Context { get } }
extension Host {
    func sanitizedChannel(_ value: Double) -> Double { context.sanitize(value) }
    func mode(for target: AuraStudioTarget) -> AuraStudioMode { context.mode(target) }
    func previewSpectrumHue(for mode: AuraStudioMode) -> Double { context.hue(mode) }
}

@main struct VerifyColorPresentation {
    @MainActor static func main() {
        var scenarios = 0
        var actions = 0
        var events = 0
        for seed in 0..<64 {
            for mode in AuraStudioMode.allCases {
                for target in AuraStudioTarget.allCases {
                    for flag: UInt32 in [0, Flag.island, Flag.dock, Flag.supported, UInt32.max] {
                        let reference = Context(seed, mode, changing: seed % 2 == 1)
                        let owned = Context(seed, mode, changing: seed % 2 == 1)
                        let a = PublicHost(context: reference)
                        let b = OwnedHost(context: owned)
                        precondition(a.color(for: target) == b.color(for: target))
                        precondition(a.previewLightColor(for: target) == b.previewLightColor(for: target))
                        precondition(a.activeColor(for: flag) == b.activeColor(for: flag))
                        precondition(reference.events == owned.events)
                        precondition(owned.events.count == (mode.usesFixedPalette ? 11 : 16))
                        precondition(owned.events.filter { $0.hasPrefix("hue=") }.count == (mode.usesFixedPalette ? 1 : 0))
                        let activePrefix = flag == Flag.island ? "activeIsland" : "activeDock"
                        precondition(owned.events.suffix(3).allSatisfy { $0.hasPrefix(activePrefix) })
                        events += owned.events.count; actions += 3; scenarios += 1
                    }
                }
            }
        }
        let reference = Context(0, .glow, changing: true)
        let owned = Context(0, .glow, changing: true)
        let a = PublicHost(context: reference)
        let controller = OwnedHost(context: owned).colorPresentation
        precondition(owned.events.isEmpty && owned.reads == 0)
        for i in 0..<96 {
            reference.seed = i; owned.seed = i
            reference.selectedMode = AuraStudioMode.allCases[i % AuraStudioMode.allCases.count]
            owned.selectedMode = reference.selectedMode
            let target: AuraStudioTarget = i % 2 == 0 ? .island : .dock
            precondition(a.previewLightColor(for: target) == controller.previewLightColor(for: target))
            precondition(a.color(for: target) == controller.color(for: target))
            precondition(a.activeColor(for: UInt32(i % 4)) == controller.activeColor(for: UInt32(i % 4)))
            precondition(reference.events == owned.events)
            actions += 3
        }
        events += owned.events.count
        print("PASS: \(scenarios) color scenarios, \(actions) actions, \(events) exact read/sanitize/hue events; both profiles/all modes/unknown flags/nonfinite drafts/extreme stored RGB and 96 reused-controller sequences")
    }
}
