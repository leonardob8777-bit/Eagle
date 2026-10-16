import Foundation

/// Existing request checks, in their original order. Access reads and effects are supplied by the app.
@MainActor
struct EagleAuraStudioRequestAdmission {
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let operationInProgress: () -> Bool
    let beginGate: () -> Bool
    let islandCanAttempt: () -> Bool
    let islandUnavailableMessage: () -> String
    let debuggerAttached: () -> Bool
    let accessReady: () -> Bool
    let readSelectedTarget: () -> EagleAuraStudioTarget
    let flagForTarget: (EagleAuraStudioTarget) -> UInt32
    let allowsMode: (EagleAuraStudioMode, EagleAuraStudioTarget) -> Bool
    let modeTitle: (EagleAuraStudioMode) -> String
    let channelTitle: () -> String
    let errorMessage: (Int32) -> String
    let localizedText: (String, String) -> String
    let log: (String, String) -> Void
    let showNotice: (String) -> Void
    let finish: (String) -> Void

    func admit(
        operation: EagleAuraStudioOperation,
        operationID: String,
        mode: Int,
        requestedProfileMode: EagleAuraStudioMode,
        requestedFlags: UInt32,
        requestedTarget: EagleAuraStudioTarget?,
        majorVersion: Int,
        displayIsZoomed: Bool
    ) -> EagleAuraStudioTarget? {
        // The camera aperture is fixed hardware, while Display Zoom changes
        // SpringBoard's private window coordinate space between device
        // families and iOS builds. Do not send an Island mutation from that
        // ambiguous geometry. Removal remains available, and Dock is
        // independent of the physical aperture.
        if !operation.isRemoving,
           requestedTarget == .island,
           displayIsZoomed {
            log(
                "display-zoom.reject",
                "op=\(operationID) target=Island noMutation=1"
            )
            showNotice(localizedText(
                "Dynamic Island requires Standard display size. Open Settings → Display & Brightness → Display Zoom, select Standard, then return to Eagle. Nothing was changed.",
                "Dynamic Island requiere el tamaño de pantalla Estándar. Abre Ajustes → Pantalla y brillo → Zoom de pantalla, selecciona Estándar y vuelve a Eagle. No se cambió nada."
            ))
            return nil
        }

        guard !localSafetyBlocked(), !remoteSafetyLocked() else {
            showNotice(localizedText(
                "Aura Studio is safety locked after the previous unverified attempt. Export the report, fully close Eagle, and reopen it before testing again.",
                "Aura Studio está bloqueado por seguridad después del intento anterior no verificado. Exporta el informe, cierra Eagle completamente y vuelve a abrirlo antes de probar otra vez."
            ))
            return nil
        }
        guard !operationInProgress(), beginGate() else {
            showNotice(localizedText(
                "Aura Studio is still finishing the previous system update.",
                "Aura Studio todavía está terminando la actualización anterior."
            ))
            return nil
        }
        if requestedTarget == .island,
           !islandCanAttempt() {
            finish(islandUnavailableMessage())
            return nil
        }
        guard !debuggerAttached() else {
            finish(localizedText(
                "Stop the Xcode run and open Eagle manually from the Home Screen before changing SpringBoard.",
                "Detén la ejecución en Xcode y abre Eagle manualmente desde Inicio antes de modificar SpringBoard."
            ))
            return nil
        }
        guard majorVersion == 17 || majorVersion == 18 else {
            finish(localizedText(
                "Aura Studio currently targets the verified iOS 17 and 18 SpringBoard surfaces.",
                "Aura Studio utiliza actualmente las superficies verificadas de SpringBoard en iOS 17 y 18."
            ))
            return nil
        }
        guard operation.isRemoving ||
                mode != EagleAuraStudioMode.tint.rawValue ||
                majorVersion == 18 else {
            finish(errorMessage(-17))
            return nil
        }
        guard accessReady(), requestedFlags != 0 else {
            finish(localizedText(
                "Prepare Eagle access and select at least one verified surface before applying.",
                "Prepara el acceso de Eagle y selecciona al menos una superficie verificada antes de aplicar."
            ))
            return nil
        }
        guard requestedFlags.nonzeroBitCount == 1,
              let operationTarget = requestedTarget else {
            finish(localizedText(
                "Choose exactly one Aura surface. Island and Dock are applied independently.",
                "Elige exactamente una superficie Aura. Island y Dock se aplican de forma independiente."
            ))
            return nil
        }
        guard requestedFlags == flagForTarget(readSelectedTarget()),
              operationTarget == readSelectedTarget() else {
            let reason = "Aura target contract mismatch selected=\(readSelectedTarget().title) " +
                "flags=0x\(String(requestedFlags, radix: 16)) resolved=\(operationTarget.title)"
            log("preflight.contract-failed", "op=\(operationID) \(reason)")
            finish(localizedText(
                "Aura Studio detected a stale surface selection and sent nothing to SpringBoard. Reopen Aura Studio and choose Dock again.",
                "Aura Studio detectó una selección de superficie obsoleta y no envió nada a SpringBoard. Vuelve a abrir Aura Studio y elige Dock otra vez."
            ))
            return nil
        }
        guard operation.isRemoving ||
                allowsMode(requestedProfileMode, operationTarget) else {
            finish(localizedText(
                "\(modeTitle(requestedProfileMode)) is not available for \(operationTarget.title) in the \(channelTitle()) channel. Nothing was sent to SpringBoard.",
                "\(modeTitle(requestedProfileMode)) no está disponible para \(operationTarget.title) en el canal \(channelTitle()). No se envió nada a SpringBoard."
            ))
            return nil
        }
        return operationTarget
    }
}
