import Foundation

typealias AuraStudioMode = EagleAuraStudioMode
typealias AuraStudioTarget = EagleAuraStudioTarget
typealias AuraStudioOperation = EagleAuraStudioOperation
typealias GalleryPosition = EagleGalleryPosition
struct Display { let isDisplayZoomed: Bool }
struct AuraStudioNotice { let message: String }

@MainActor final class Context {
    var bits = 0
    var spanish = false
    var selections: [AuraStudioTarget] = [.island]
    var selectionIndex = 0
    var events: [String] = []
    var gateAcquired = false
    var pendingFinish = false
    var noticeMessage: String?
    var finishMessage: String?
    func configure(_ value: Int, _ language: Bool, _ selected: [AuraStudioTarget]) {
        bits = value; spanish = language; selections = selected
        selectionIndex = 0; events = []; gateAcquired = false; pendingFinish = false
        noticeMessage = nil; finishMessage = nil
    }
    func read(_ event: String, _ bit: Int, invert: Bool = false) -> Bool {
        events.append(event)
        let set = bits & (1 << bit) != 0
        return invert ? !set : set
    }
    var rcSafetyLocked: Bool { read("remoteLock", 1) }
    var dsready: Bool { read("access", 6, invert: true) }
    var selected: AuraStudioTarget {
        events.append("selected.\(selectionIndex)")
        defer { selectionIndex += 1 }
        return selections[selectionIndex % selections.count]
    }
    func drainFinish() {
        guard pendingFinish else { return }
        events.append("drainFinish"); gateAcquired = false; pendingFinish = false
    }
}

@MainActor enum World { static var context = Context() }
@MainActor enum LaraL10n {
    static func text(en: String, es: String) -> String {
        World.context.events.append("localized")
        return World.context.spanish ? es : en
    }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String = "") {
        World.context.events.append("log.\(stage):\(detail)")
    }
}
@MainActor enum AuraStudioApplyGate {
    static func begin() -> Bool {
        let context = World.context
        context.events.append("beginGate")
        guard context.bits & 8 == 0, !context.gateAcquired else { return false }
        context.gateAcquired = true
        return true
    }
}
@MainActor func isdebugged() -> Bool { World.context.read("debugger", 5) }
@MainActor struct Compatibility {
    let context: Context
    var canAttemptLiveIslandAura: Bool { context.read("hardware", 4, invert: true) }
}
@MainActor struct Channel {
    let context: Context
    var title: String { context.events.append("channel"); return "Stable" }
}
extension EagleAuraStudioMode {
    @MainActor var title: String {
        World.context.events.append("modeTitle.\(rawValue)")
        return title(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
}
extension EagleGalleryPosition {
    @MainActor static func saved(_ surface: String) -> Self {
        World.context.events.append("savedPosition.\(surface)")
        return surface == "island" ? Self(x: 3.125, y: -2.125) : Self(x: -4.125, y: 5.125)
    }
}
@MainActor protocol Host {
    var context: Context { get }
    func evaluate(_ operation: AuraStudioOperation, _ operationID: String,
        _ mode: Int, _ requestedProfileMode: AuraStudioMode, _ requestedFlags: UInt32,
        _ requestedTarget: AuraStudioTarget?, _ version: OperatingSystemVersion,
        _ display: Display) -> AuraStudioTarget?
    func request(_ operation: AuraStudioOperation, _ operationID: String,
        _ mode: Int, _ requestedProfileMode: AuraStudioMode, _ requestedFlags: UInt32,
        _ requestedTarget: AuraStudioTarget?, _ version: OperatingSystemVersion,
        _ display: Display) -> EagleAuraStudioRequestParameters<GalleryPosition>?
}
extension Host {
    var islandRed: Double { context.events.append("rgb.island.red"); return 0.10 }
    var islandGreen: Double { context.events.append("rgb.island.green"); return 0.78 }
    var islandBlue: Double { context.events.append("rgb.island.blue"); return 1 }
    var dockRed: Double { context.events.append("rgb.dock.red"); return 0.62 }
    var dockGreen: Double { context.events.append("rgb.dock.green"); return 0.25 }
    var dockBlue: Double { context.events.append("rgb.dock.blue"); return 1 }
    func sanitizedChannel(_ value: Double) -> Double {
        context.events.append("sanitize.\(value.bitPattern)")
        return EagleAuraStudioColors.sanitizedChannel(value)
    }
    func channel255(_ value: Double) -> Int {
        context.events.append("channel255.\(value.bitPattern)")
        return EagleAuraStudioColors.channel255(value)
    }
    var mgr: Context { context }
    var applySafetyBlocked: Bool { context.read("localLock", 0) }
    var isApplying: Bool { context.read("applying", 2) }
    var islandCompatibility: Compatibility { Compatibility(context: context) }
    var islandHardwareUnavailableMessage: String {
        context.events.append("unavailableMessage"); return "Island unavailable"
    }
    var selectedTarget: AuraStudioTarget { context.selected }
    var releaseChannel: Channel { Channel(context: context) }
    var notice: AuraStudioNotice? {
        get { context.noticeMessage.map(AuraStudioNotice.init) }
        nonmutating set {
            context.noticeMessage = newValue?.message
            context.events.append("notice.\(newValue?.message ?? "nil")")
        }
    }
    func flag(for target: AuraStudioTarget) -> UInt32 {
        context.events.append("flag.\(target.rawValue)")
        return target.flag(islandFlag: 1, dockFlag: 32)
    }
    func policyAllows(_ mode: AuraStudioMode, for target: AuraStudioTarget) -> Bool {
        context.events.append("policy.\(mode.rawValue).\(target.rawValue)")
        return context.bits & 128 == 0
    }
    func message(for result: Int32) -> String {
        context.events.append("errorMessage.\(result)"); return "Error \(result)"
    }
    func finish(message: String) {
        context.events.append("finish.\(message)")
        context.finishMessage = message; context.pendingFinish = true
    }
}

@main struct Runner {
    @MainActor static func main() {
        let old = PublicHost(context: Context()), owned = OwnedHost(context: Context())
        let operations = AuraStudioMode.allCases.map(AuraStudioOperation.apply) + [.remove]
        let targets: [AuraStudioTarget?] = [nil, .island, .dock]
        let versions = [16, 17, 18, 26]
        var scenarios = 0, effects = 0, admitted = 0
        func compare(_ operation: AuraStudioOperation, _ flags: UInt32, _ target: AuraStudioTarget?,
                     _ version: Int, _ zoom: Bool, _ bits: Int, _ spanish: Bool,
                     _ selection: [AuraStudioTarget]) {
            old.context.configure(bits, spanish, selection)
            owned.context.configure(bits, spanish, selection)
            let os = OperatingSystemVersion(majorVersion: version, minorVersion: 0, patchVersion: 1)
            World.context = old.context
            let a = old.evaluate(operation, "TEST0001", operation.nativeMode,
                operation.requestedProfileMode, flags, target, os, Display(isDisplayZoomed: zoom))
            World.context = owned.context
            let b = owned.evaluate(operation, "TEST0001", operation.nativeMode,
                operation.requestedProfileMode, flags, target, os, Display(isDisplayZoomed: zoom))
            precondition(a == b, "Admission mismatch at \(scenarios)")
            precondition(old.context.events == owned.context.events, "Read/effect mismatch at \(scenarios)")
            precondition(old.context.gateAcquired == owned.context.gateAcquired)
            precondition(old.context.noticeMessage == owned.context.noticeMessage)
            precondition(old.context.finishMessage == owned.context.finishMessage)
            precondition(old.context.pendingFinish == owned.context.pendingFinish)
            precondition(owned.context.events.filter { $0 == "beginGate" }.count <= 1)
            if b != nil {
                precondition(owned.context.gateAcquired && !owned.context.pendingFinish)
                precondition(owned.context.noticeMessage == nil && owned.context.finishMessage == nil)
                admitted += 1
            }
            effects += owned.context.events.count
            // Exercise admission and preparation together through the exact production bindings.
            old.context.configure(bits, spanish, selection)
            owned.context.configure(bits, spanish, selection)
            World.context = old.context
            let oldPlan = old.request(operation, "TEST0001", operation.nativeMode,
                operation.requestedProfileMode, flags, target, os, Display(isDisplayZoomed: zoom))
            World.context = owned.context
            let newPlan = owned.request(operation, "TEST0001", operation.nativeMode,
                operation.requestedProfileMode, flags, target, os, Display(isDisplayZoomed: zoom))
            precondition((oldPlan != nil) == (newPlan != nil) && (newPlan != nil) == (b != nil))
            precondition(old.context.events == owned.context.events)
            if let oldPlan, let newPlan {
                precondition(oldPlan.position == newPlan.position && oldPlan.positionSurface == newPlan.positionSurface)
                precondition(oldPlan.red == newPlan.red && oldPlan.green == newPlan.green && oldPlan.blue == newPlan.blue)
                let prefix = b == .island ? "rgb.island." : "rgb.dock."
                precondition(owned.context.events.filter { $0.hasPrefix("rgb.") } == [prefix + "red", prefix + "green", prefix + "blue"])
                precondition(!operation.isRemoving || !owned.context.events.contains { $0.hasPrefix("savedPosition.") })
            } else {
                precondition(!owned.context.events.contains { $0.hasPrefix("rgb.") || $0.hasPrefix("savedPosition.") || $0.hasPrefix("channel255.") })
            }
            old.context.drainFinish(); owned.context.drainFinish()
            precondition(old.context.events == owned.context.events)
            precondition(old.context.gateAcquired == owned.context.gateAcquired)
            scenarios += 1
        }
        for operation in operations {
            for target in targets {
                let flags: UInt32 = target == .island ? 1 : (target == .dock ? 32 : 33)
                for version in versions {
                    for zoom in [false, true] {
                        for bits in 0..<256 {
                            for spanish in [false, true] {
                                compare(operation, flags, target, version, zoom, bits, spanish, [target ?? .dock])
                            }
                        }
                    }
                }
            }
        }
        let selections: [[AuraStudioTarget]] = [
            [.island], [.dock], [.island, .dock], [.dock, .island],
            [.island, .island, .dock], [.dock, .dock, .island],
        ]
        for operation in operations {
            for target in targets {
                for flags: UInt32 in [0, 1, 2, 32, 33, 1 << 30, .max] {
                    for version in versions {
                        for zoom in [false, true] {
                            for selection in selections {
                                for spanish in [false, true] {
                                    compare(operation, flags, target, version, zoom, 0, spanish, selection)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Independent priority anchors: Zoom rejects before locks, and locks reject before gate acquisition.
        compare(.apply(.glow), 1, .island, 18, true, 255, false, [.island])
        precondition(owned.context.events.first?.hasPrefix("log.display-zoom.reject") == true)
        precondition(!owned.context.events.contains("localLock") && !owned.context.gateAcquired)
        compare(.apply(.glow), 1, .island, 18, false, 1, false, [.island])
        precondition(owned.context.events.first == "localLock")
        precondition(!owned.context.events.contains("remoteLock") && !owned.context.events.contains("beginGate"))
        compare(.remove, 1, .island, 17, true, 128, false, [.island])
        precondition(owned.context.gateAcquired && owned.context.finishMessage == nil)
        precondition(!owned.context.events.contains { $0.hasPrefix("policy.") })
        compare(.apply(.glow), 32, .dock, 26, false, 0, false, [.dock])
        precondition(owned.context.finishMessage?.contains("iOS 17 and 18") == true)
        // Reusing a host cannot bypass the shared gate between acceptance and UI begin.
        for context in [old.context, owned.context] { context.configure(0, false, [.dock]) }
        let os = OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)
        for attempt in 0..<3 {
            World.context = old.context
            let a = old.evaluate(.apply(.glow), "REUSE001", 1, .glow, 32, .dock, os, Display(isDisplayZoomed: false))
            World.context = owned.context
            let b = owned.evaluate(.apply(.glow), "REUSE001", 1, .glow, 32, .dock, os, Display(isDisplayZoomed: false))
            precondition(a == b && (b != nil) == (attempt == 0))
            precondition(old.context.events == owned.context.events)
        }
        print("PASS: \(scenarios) public/owned admission scenarios + connected RGB/position requests, \(effects) exact admission reads/effects, \(admitted) accepted; rejected requests read no payload, changing selection, queued finishes and repeated hosts")
    }
}
