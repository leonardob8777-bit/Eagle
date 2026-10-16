import Foundation
import CoreGraphics

typealias AuraStudioMode = EagleAuraStudioMode
typealias AuraStudioTarget = EagleAuraStudioTarget
enum Flag {
    static let island: UInt32 = 1
    static let dock: UInt32 = 32
    static let supported: UInt32 = 33
}
@MainActor final class State {
    var events: [String] = []
    var pid: Int32 = 101
    var version = OperatingSystemVersion(majorVersion: 18, minorVersion: 6, patchVersion: 2)
    var uuid = UUID(uuidString: "ABCDEF12-3456-7890-ABCD-1234567890EF")!
    var zoomed = false
    var model = "iPhone17,1"
    var hardware = "supported"
    var deviceFlags: UInt32 = 33
    var stored = [33, 4, 4, 2, 77, 101]
    var mutateOnReconcile = false
    var engine = "existing-engine"
    func read(_ field: EagleAuraStudioReconciliation.Field) -> Int {
        let index = EagleAuraStudioReconciliation.Field.allCases.firstIndex(of: field)!
        events.append("read.\(field)")
        return stored[index]
    }
    func write(_ field: EagleAuraStudioReconciliation.Field, _ value: Int) {
        events.append("write.\(field)=\(value)")
        stored[EagleAuraStudioReconciliation.Field.allCases.firstIndex(of: field)!] = value
    }
    var display: EagleAuraStudioDisplayGeometry {
        EagleAuraStudioDisplayGeometry(
            logicalSize: CGSize(width: 393, height: 852),
            nativePixelSize: CGSize(width: 1179, height: 2556),
            standardLogicalSize: CGSize(width: 393, height: 852),
            renderScale: 3, nativeScale: 3,
            xFactor: zoomed ? 0.9 : 1, yFactor: zoomed ? 0.85 : 1,
            isDisplayZoomed: zoomed
        )
    }
}
@MainActor enum World { static var state = State() }
@MainActor func find_process_pid(_ name: UnsafePointer<CChar>) -> Int32 {
    let state = World.state
    state.events.append("pid.\(String(cString: name))=\(state.pid)")
    return state.pid
}
@MainActor func devicemachine() -> String {
    World.state.events.append("device.\(World.state.model)")
    return World.state.model
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ key: String, _ text: String) {
        World.state.events.append("log.\(key).\(text)")
    }
}
@MainActor struct Hardware {
    var diagnosticsToken: String {
        World.state.events.append("hardware.\(World.state.hardware)")
        return World.state.hardware
    }
}
extension EagleAuraStudioDisplayGeometry {
    @MainActor var compactIslandFrame: CGRect {
        World.state.events.append("island.frame")
        return compactIslandFrame(readModel: { devicemachine() })
    }
    @MainActor var dockAuraFrame: CGRect {
        World.state.events.append("dock.frame")
        return dockAuraFrame(readModel: { devicemachine() })
    }
}
@MainActor protocol Host {
    var state: State { get }
    func capture(operation: EagleAuraStudioOperation, flags: UInt32) -> EagleAuraStudioRequestContext
}
extension Host {
    var displayGeometry: EagleAuraStudioDisplayGeometry {
        state.events.append("display.\(state.zoomed)")
        return state.display
    }
    var auraEngineBuild: String {
        state.events.append("engine.\(state.engine)")
        return state.engine
    }
    var islandCompatibility: Hardware {
        state.events.append("compatibility")
        return Hardware()
    }
    func readVersion() -> OperatingSystemVersion {
        state.events.append("version.\(state.version.majorVersion)")
        return state.version
    }
    func makeUUID() -> UUID {
        state.events.append("uuid.\(state.uuid.uuidString)")
        return state.uuid
    }
    func reconcilePersistedActiveState(currentPID: Int32) {
        state.events.append("reconcile.\(currentPID)")
        EagleAuraStudioReconciliation(
            lookupCurrentPID: { preconditionFailure("Capture must supply its PID") },
            decodeFlags: { UInt32(clamping: $0) },
            supportedFlags: Flag.supported,
            deviceSupportedFlags: { state.events.append("deviceFlags"); return state.deviceFlags },
            islandFlag: Flag.island,
            dockFlag: Flag.dock,
            read: { state.read($0) },
            write: { state.write($0, $1) },
            diagnosticsToken: { islandCompatibility.diagnosticsToken },
            log: { AuraStudioDiagnostics.log($0, $1) }
        ).reconcilePersistedActiveState(currentPID: currentPID)
        // Simulates a synchronous host observer. Subsequent reads must be current,
        // while the operation must retain the PID captured before reconciliation.
        if state.mutateOnReconcile {
            state.pid = 303
            state.version = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
            state.uuid = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
            state.zoomed.toggle()
            state.model = "iPhone15,2"
            state.engine = "observed-engine"
        }
        state.events.append("reconcile.end")
    }
}
func fingerprint(_ context: EagleAuraStudioRequestContext) -> [String] {
    [
        "pid=\(context.springBoardPID)",
        "version=\(context.version.majorVersion).\(context.version.minorVersion).\(context.version.patchVersion)",
        "id=\(context.operationID)", "mode=\(context.mode)",
        "profile=\(context.requestedProfileMode.rawValue)", "flags=\(context.requestedFlags)",
        "target=\(String(describing: context.requestedTarget))",
        "display=\(context.display)"
    ]
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
@main struct Tests {
    @MainActor static func main() {
        var cases = 0
        var eventCount = 0
        let operations = EagleAuraStudioMode.allCases.map(EagleAuraStudioOperation.apply) + [.remove]
        let masks: [UInt32] = [0, 1, 32, 33, 2, 3, 34, 35, 1 << 30, .max]
        func pair(_ configure: (State) -> Void, operation: EagleAuraStudioOperation, flags: UInt32) -> (EagleAuraStudioRequestContext, State) {
            let reference = State(), owned = State()
            configure(reference); configure(owned)
            World.state = reference
            let expected = PublicHost(state: reference).capture(operation: operation, flags: flags)
            World.state = owned
            let actual = OwnedHost(state: owned).capture(operation: operation, flags: flags)
            require(fingerprint(expected) == fingerprint(actual), "Captured request differs")
            require(reference.events == owned.events, "Read/effect order differs\n\(reference.events)\n\(owned.events)")
            require(reference.stored == owned.stored && reference.pid == owned.pid, "Reconciliation effects differ")
            require(owned.events.filter { $0.hasPrefix("pid.") }.count == 1, "PID was queried again")
            require(owned.events.filter { $0 == "reconcile.end" }.count == 1, "Reconciliation repeated")
            require(owned.events.filter { $0.hasPrefix("log.request.") }.count == 1, "Request report missing/duplicated")
            require(owned.events.firstIndex(of: "reconcile.end")! <
                    owned.events.firstIndex(where: { $0.hasPrefix("version.") })!, "Environment read before reconciliation")
            require(owned.events.firstIndex(of: "island.frame")! < owned.events.firstIndex(of: "dock.frame")!, "Frame ordering changed")
            cases += 1; eventCount += owned.events.count
            return (actual, owned)
        }
        for operation in operations {
            for mask in masks {
                for pid: Int32 in [0, 101, 202] {
                    for zoomed in [false, true] {
                        for observer in [false, true] {
                            for deviceFlags: UInt32 in [0, 32, 33] {
                                _ = pair({
                                    $0.pid = pid; $0.zoomed = zoomed
                                    $0.mutateOnReconcile = observer; $0.deviceFlags = deviceFlags
                                }, operation: operation, flags: mask)
                            }
                        }
                    }
                }
            }
        }
        let (fresh, afterFresh) = pair({ $0.pid = 202 }, operation: .apply(.pulse), flags: 32)
        require(afterFresh.stored == [0, 0, 0, 0, 0, 0], "Changed PID must clear stale profiles")
        require(fresh.springBoardPID == 202 && fresh.requestedTarget == .dock, "Wrong fresh target/PID")
        let (unknown, _) = pair({ _ in }, operation: .apply(.rainbow), flags: .max)
        require(unknown.requestedFlags == 33 && unknown.requestedTarget == nil, "Combined selection must stay invalid")
        let (removed, _) = pair({ _ in }, operation: .remove, flags: 1)
        require(removed.mode == 0 && removed.requestedProfileMode == .glow, "Removal contract changed")
        let (captured, observed) = pair({ $0.mutateOnReconcile = true }, operation: .apply(.tint), flags: 1)
        require(captured.springBoardPID == 101 && observed.pid == 303, "Captured PID drifted")
        require(captured.version.majorVersion == 26 && captured.operationID == "12345678" &&
                captured.display.isDisplayZoomed, "Post-reconciliation values were snapshotted too soon")
        let saved = fingerprint(captured)
        observed.pid = 404; observed.zoomed = false; observed.engine = "later"
        observed.uuid = UUID()
        require(fingerprint(captured) == saved, "Request context is not immutable")
        let (_, current) = pair({ _ in }, operation: .apply(.glow), flags: 1)
        require(current.stored == [33, 4, 4, 2, 77, 101], "Valid independent profiles changed")
        require(current.events.last ==
            "log.request.op=ABCDEF12 engine=existing-engine action=apply mode=1 target=Dynamic Island flags=0x1 device=iPhone17,1 islandHardware={supported} ios=18.6.2 display=standard factor=1.0000,1.0000 island=129.50,13.00,134.00,39.00 dock=15.00,1.00,363.00,94.00",
            "Exact public request text changed")
        // A new request, not an old captured context, must observe the latest process.
        World.state = current
        let host = OwnedHost(state: current)
        current.pid = 505
        let second = host.capture(operation: .apply(.pulse), flags: 32)
        require(second.springBoardPID == 505 && current.stored == [0, 0, 0, 0, 0, 0], "Repeated request reused stale process")
        print("PASS: \(cases) request/reconciliation cases, \(eventCount) ordered reads/effects; immutable context, invalid masks, respring, synchronous observers and repeated requests")
    }
}
