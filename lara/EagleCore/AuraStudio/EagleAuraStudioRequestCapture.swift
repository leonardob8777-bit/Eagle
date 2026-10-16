import Foundation
import CoreGraphics

/// One request's captured identity and environment; no access or session objects.
nonisolated struct EagleAuraStudioRequestContext: Sendable {
    let springBoardPID: Int32
    let version: OperatingSystemVersion
    let operationID: String
    let mode: Int
    let requestedProfileMode: EagleAuraStudioMode
    let requestedFlags: UInt32
    let requestedTarget: EagleAuraStudioTarget?
    let display: EagleAuraStudioDisplayGeometry
}

/// Preserves reconciliation, capture and diagnostic ordering before request admission.
@MainActor
struct EagleAuraStudioRequestCapture {
    let supportedFlags: UInt32
    let islandFlag: UInt32
    let dockFlag: UInt32
    let currentPID: () -> Int32
    let reconcile: (Int32) -> Void
    let readVersion: () -> OperatingSystemVersion
    let makeUUID: () -> UUID
    let targetTitle: (EagleAuraStudioTarget) -> String
    let readDisplay: () -> EagleAuraStudioDisplayGeometry
    let islandFrame: (EagleAuraStudioDisplayGeometry) -> CGRect
    let dockFrame: (EagleAuraStudioDisplayGeometry) -> CGRect
    let engineBuild: () -> String
    let deviceModel: () -> String
    let hardwareToken: () -> String
    let log: (String, String) -> Void

    func capture(
        operation: EagleAuraStudioOperation,
        flags: UInt32
    ) -> EagleAuraStudioRequestContext {
        // Reconcile before reading request metadata or consulting admission.
        let operationSpringBoardPID = currentPID()
        reconcile(operationSpringBoardPID)
        let version = readVersion()
        let operationID = String(makeUUID().uuidString.prefix(8))
        let mode = operation.nativeMode
        let requestedProfileMode = operation.requestedProfileMode
        let requestedFlags = flags & supportedFlags
        let requestedTarget = EagleAuraStudioNativeContract.target(
            for: requestedFlags,
            islandFlag: islandFlag,
            dockFlag: dockFlag
        )
        let requestedTargetTitle = requestedTarget.map(targetTitle) ?? "Invalid selection"
        let display = readDisplay()
        let islandFrame = islandFrame(display)
        let dockFrame = dockFrame(display)
        log(
            "request",
            "op=\(operationID) engine=\(engineBuild()) " +
            "action=\(operation.isRemoving ? "remove" : "apply") mode=\(mode) " +
            "target=\(requestedTargetTitle) flags=0x\(String(requestedFlags, radix: 16)) " +
            "device=\(deviceModel()) " +
            "islandHardware={\(hardwareToken())} " +
            "ios=\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) " +
            "display=\(display.isDisplayZoomed ? "zoomed" : "standard") " +
            "factor=\(String(format: "%.4f", display.xFactor))," +
            "\(String(format: "%.4f", display.yFactor)) " +
            "island=\(String(format: "%.2f,%.2f,%.2f,%.2f", islandFrame.minX, islandFrame.minY, islandFrame.width, islandFrame.height)) " +
            "dock=\(String(format: "%.2f,%.2f,%.2f,%.2f", dockFrame.minX, dockFrame.minY, dockFrame.width, dockFrame.height))"
        )
        return EagleAuraStudioRequestContext(
            springBoardPID: operationSpringBoardPID,
            version: version,
            operationID: operationID,
            mode: mode,
            requestedProfileMode: requestedProfileMode,
            requestedFlags: requestedFlags,
            requestedTarget: requestedTarget,
            display: display
        )
    }
}
