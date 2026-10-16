import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
typealias Color = PreviewColor

@MainActor final class Context {
    var rgb: [Double]
    var events: [String] = []
    var date = Date(timeIntervalSinceReferenceDate: 0)
    init(_ rgb: [Double] = [0, 0, 0]) { self.rgb = rgb }
}

struct PreviewColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

@MainActor protocol PreviewHost {
    var context: Context { get }
    var previewTintFillColor: Color { get }
    func previewSpectrumHue(for mode: AuraStudioMode) -> Double
    func auraSpectrumPhase(at date: Date) -> Double
    func auraPulseLevel(at date: Date) -> Double
}

extension PreviewHost {
    var islandRed: Double { context.events.append("read.red"); return context.rgb[0] }
    var islandGreen: Double { context.events.append("read.green"); return context.rgb[1] }
    var islandBlue: Double { context.events.append("read.blue"); return context.rgb[2] }
    func sanitizedChannel(_ value: Double) -> Double {
        context.events.append("sanitize.\(value.bitPattern)")
        return EagleAuraStudioColors.sanitizedChannel(value)
    }
    func fixtureNow() -> Date {
        context.events.append("clock")
        return context.date
    }
}

@main struct PreviewChecks {
    static func same(_ a: Double, _ b: Double) {
        precondition(a.bitPattern == b.bitPattern || (a.isNaN && b.isNaN))
    }

    @MainActor static func main() async {
        let threshold = 112.0 / 255.0
        let channels: [Double] = [-Double.infinity, -.greatestFiniteMagnitude, -1, -0.0, 0,
                                  Double.leastNonzeroMagnitude, 0.1, threshold.nextDown,
                                  threshold, threshold.nextUp, 0.8, 1, 2,
                                  .greatestFiniteMagnitude, .infinity, .nan]
        var colorCases = 0
        var readEvents = 0
        for red in channels {
            for green in channels {
                for blue in channels {
                    let oldContext = Context([red, green, blue])
                    let newContext = Context([red, green, blue])
                    let old = PublicHost(context: oldContext).previewTintFillColor
                    let new = OwnedHost(context: newContext).previewTintFillColor
                    same(old.red, new.red); same(old.green, new.green); same(old.blue, new.blue)
                    precondition(oldContext.events == newContext.events)
                    precondition(oldContext.events.count == 6)
                    precondition(oldContext.events[0] == "read.red")
                    precondition(oldContext.events[2] == "read.green")
                    precondition(oldContext.events[4] == "read.blue")
                    for value in [new.red, new.green, new.blue] {
                        precondition(value.isFinite && value >= 0 && value <= threshold + 1e-15)
                    }
                    colorCases += 1
                    readEvents += oldContext.events.count
                }
            }
        }

        var seconds = stride(from: -130.0, through: 130.0, by: 1.0 / 30.0).map { $0 }
        for period in [2.3, 5.2] {
            for multiplier in [-1000.0, -1, 0, 1, 1000] {
                let boundary = period * multiplier
                seconds += [boundary.nextDown, boundary, boundary.nextUp]
            }
        }
        seconds += [-1e12, -1e9, 1e9, 1e12, Double.greatestFiniteMagnitude]
        let oldContext = Context()
        let newContext = Context()
        let old = PublicHost(context: oldContext)
        let new = OwnedHost(context: newContext)
        var motionCases = 0
        var hueCases = 0
        var clockEvents = 0
        for time in seconds {
            let date = Date(timeIntervalSinceReferenceDate: time)
            same(old.auraSpectrumPhase(at: date), new.auraSpectrumPhase(at: date))
            same(old.auraPulseLevel(at: date), new.auraPulseLevel(at: date))
            let phase = new.auraSpectrumPhase(at: date)
            // A negative subnormal time can round the original fractional phase to 1.
            // Preserve that public numerical behavior, rather than silently clamp it.
            precondition(phase >= 0 && phase <= 1)
            precondition((0.58...1.0).contains(new.auraPulseLevel(at: date)))
            motionCases += 2
            oldContext.date = date; newContext.date = date
            for mode in AuraStudioMode.allCases {
                oldContext.events = []; newContext.events = []
                let oldHue = old.previewSpectrumHue(for: mode)
                let newHue = new.previewSpectrumHue(for: mode)
                same(oldHue, newHue)
                precondition(oldContext.events == newContext.events)
                precondition(newContext.events == (mode == .rainbow ? ["clock"] : []))
                if mode == .rainbow { same(newHue, phase) }
                else if mode.photoAssetName != nil { same(newHue, 0.73) }
                else { same(newHue, 0) }
                clockEvents += newContext.events.count
                hueCases += 1
            }
        }

        // Independent seam and breathing checks, in addition to exact old/new parity.
        for cycle in -50...50 {
            let seam = Double(cycle) * 5.2
            let before = EagleAuraStudioPreview.spectrumPhase(at: Date(timeIntervalSinceReferenceDate: seam - 1e-6))
            let after = EagleAuraStudioPreview.spectrumPhase(at: Date(timeIntervalSinceReferenceDate: seam + 1e-6))
            let circularDistance = min(abs(after - before), 1 - abs(after - before))
            precondition(circularDistance < 1e-5)
            let pulseSeam = Double(cycle) * 2.3
            let low = EagleAuraStudioPreview.pulseLevel(at: Date(timeIntervalSinceReferenceDate: pulseSeam))
            let high = EagleAuraStudioPreview.pulseLevel(at: Date(timeIntervalSinceReferenceDate: pulseSeam + 1.15))
            precondition(abs(low - 0.58) < 1e-12 && abs(high - 1) < 1e-12)
        }
        let detached = await Task.detached {
            seconds.map { time in
                let date = Date(timeIntervalSinceReferenceDate: time)
                return [EagleAuraStudioPreview.spectrumPhase(at: date), EagleAuraStudioPreview.pulseLevel(at: date)]
            }
        }.value
        for (time, values) in zip(seconds, detached) {
            let date = Date(timeIntervalSinceReferenceDate: time)
            same(values[0], new.auraSpectrumPhase(at: date))
            same(values[1], new.auraPulseLevel(at: date))
        }
        var events: [String] = []
        let custom: [Double] = EagleAuraStudioPreview.tintFill(
            readRed: { events.append("red"); return 0.1 },
            readGreen: { events.append("green"); return 0.2 },
            readBlue: { events.append("blue"); return 0.3 },
            makeColor: { events.append("color"); return [$0, $1, $2] }
        )
        precondition(custom == [0.1, 0.2, 0.3] && events == ["red", "green", "blue", "color"])
        print("PASS: \(colorCases) tint cases, \(readEvents) read/sanitize events, \(motionCases) motion samples, \(hueCases) mode/time cases, \(clockEvents) lazy clock reads; seams, detached parity and callback order")
    }
}
