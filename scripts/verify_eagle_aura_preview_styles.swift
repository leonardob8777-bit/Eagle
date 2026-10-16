import Foundation

typealias AuraStudioTarget = EagleAuraStudioTarget
typealias AuraStudioMode = EagleAuraStudioMode

protocol RecordedStyle { var record: [String] { get } }
struct Color: RecordedStyle {
    let name: String
    var record: [String] { ["solid", name] }
    static let pink = Color(name: "pink"), orange = Color(name: "orange")
    static let yellow = Color(name: "yellow"), green = Color(name: "green")
    static let cyan = Color(name: "cyan"), blue = Color(name: "blue")
    static let purple = Color(name: "purple"), red = Color(name: "red")
    static let black = Color(name: "black")
}
enum UnitPoint: String { case leading, trailing, center }
struct Angle {
    let value: Double
    static func degrees(_ value: Double) -> Angle { Angle(value: value) }
}
struct LinearGradient: RecordedStyle {
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    var record: [String] { ["linear", startPoint.rawValue, endPoint.rawValue] + colors.map(\.name) }
}
struct AngularGradient: RecordedStyle {
    let colors: [Color]
    let center: UnitPoint
    let angle: Angle
    var record: [String] { ["angular", center.rawValue, String(angle.value.bitPattern)] + colors.map(\.name) }
}
struct AnyShapeStyle: Equatable {
    let record: [String]
    init<S: RecordedStyle>(_ style: S) { record = style.record }
}

@MainActor final class Context {
    var selectedMode: AuraStudioMode
    var seed = 0
    var events: [String] = []
    init(_ mode: AuraStudioMode) { selectedMode = mode }
    func mode(_ target: AuraStudioTarget) -> AuraStudioMode {
        events.append("mode:\(target.rawValue)")
        return selectedMode
    }
    func color(_ target: AuraStudioTarget) -> Color {
        events.append("color:\(target.rawValue):\(seed)")
        return Color(name: "profile:\(target.rawValue):\(seed)")
    }
    func tint() -> Color {
        events.append("tint:\(seed)")
        return Color(name: "tint:\(seed)")
    }
}
@MainActor protocol Host { var context: Context { get } }
extension Host {
    func mode(for target: AuraStudioTarget) -> AuraStudioMode { context.mode(target) }
    func color(for target: AuraStudioTarget) -> Color { context.color(target) }
    var previewTintFillColor: Color { context.tint() }
}

@main struct VerifyPreviewStyles {
    @MainActor static func main() {
        let angles: [Double] = [-720, -360, -1, -0.0, 0, 0.01, 180, 359.99, 360, 720, .nan, .infinity, -.infinity]
        var scenarios = 0
        var calls = 0
        var events = 0
        for mode in AuraStudioMode.allCases {
            for selected in AuraStudioMode.allCases {
                for target in AuraStudioTarget.allCases {
                    for angle in angles {
                        let reference = Context(selected), owned = Context(selected)
                        let a = PublicHost(context: reference), b = OwnedHost(context: owned)
                        precondition(a.previewRingStyle(for: target) == b.previewRingStyle(for: target))
                        precondition(a.islandPreviewFillStyle(for: mode) == b.islandPreviewFillStyle(for: mode))
                        precondition(a.islandRingStyle(for: mode, angle: angle) == b.islandRingStyle(for: mode, angle: angle))
                        precondition(a.islandFillStyle(for: mode, angle: angle) == b.islandFillStyle(for: mode, angle: angle))
                        precondition(reference.events == owned.events)
                        var expected = ["mode:\(target.rawValue)"]
                        if selected != .rainbow { expected.append("color:\(target.rawValue):0") }
                        if mode == .tint { expected.append("tint:0") }
                        if [.glow, .pulse, .tint].contains(mode) { expected.append("color:1:0") }
                        if mode == .tint { expected.append("tint:0") }
                        precondition(owned.events == expected)
                        scenarios += 1; calls += 4; events += owned.events.count
                    }
                }
            }
        }
        let reference = Context(.glow), owned = Context(.glow)
        let a = PublicHost(context: reference)
        let styles = OwnedHost(context: owned).previewStyles
        precondition(owned.events.isEmpty)
        for i in 0..<132 {
            let mode = AuraStudioMode.allCases[i % AuraStudioMode.allCases.count]
            let target: AuraStudioTarget = i % 2 == 0 ? .dock : .island
            reference.selectedMode = mode; owned.selectedMode = mode
            reference.seed = i; owned.seed = i
            let angle = Double(i) * 2.75
            precondition(a.previewRingStyle(for: target) == styles.previewRingStyle(for: target))
            precondition(a.islandPreviewFillStyle(for: mode) == styles.islandPreviewFillStyle(for: mode))
            precondition(a.islandRingStyle(for: mode, angle: angle) == styles.islandRingStyle(for: mode, angle: angle))
            precondition(a.islandFillStyle(for: mode, angle: angle) == styles.islandFillStyle(for: mode, angle: angle))
            precondition(reference.events == owned.events)
            calls += 4
        }
        events += owned.events.count
        // Independent palette/direction/angle goldens, not just old/new equality.
        owned.selectedMode = .rainbow
        precondition(styles.previewRingStyle(for: .dock).record == ["linear", "leading", "trailing", "pink", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"])
        precondition(styles.islandPreviewFillStyle(for: .rainbow).record == ["linear", "leading", "trailing", "pink", "orange", "cyan", "purple"])
        precondition(styles.islandFillStyle(for: .rainbow, angle: 90).record == ["angular", "center", String(90.0.bitPattern), "red", "orange", "yellow", "green", "cyan", "blue", "purple", "red"])
        precondition(styles.islandRingStyle(for: .photo, angle: 0).record == ["solid", "purple"])
        precondition(styles.islandPreviewFillStyle(for: .glow).record == ["solid", "black"])
        print("PASS: \(scenarios) style scenarios, \(calls) style calls, \(events) exact lazy reads, 132 reused-controller sequences and five independent palette/geometry goldens; recording styles, not pixel rendering")
    }
}
