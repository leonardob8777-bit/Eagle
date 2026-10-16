import Foundation

/// Read-only capability messages and button presentation; native authorization remains in the caller.
@MainActor
struct EagleAuraStudioCapability {
    let localSafetyBlocked: () -> Bool
    let remoteSafetyLocked: () -> Bool
    let accessIsReady: () -> Bool
    let operationInProgress: () -> Bool
    let requestedFlags: () -> UInt32
    let selectedTargetTitle: () -> String
    let selectedTargetIsIsland: () -> Bool
    let selectedMode: () -> EagleAuraStudioMode
    let localizedText: (String, String) -> String

    var selectedCapabilityTitle: String {
        if localSafetyBlocked() || remoteSafetyLocked() {
            return localizedText(
                "Safety lock active",
                "Bloqueo de seguridad activo"
            )
        }
        if !accessIsReady() {
            return localizedText(
                "System access required",
                "Se requiere acceso al sistema"
            )
        }
        return localizedText(
            "\(selectedTargetTitle()) ready for live verification",
            "\(selectedTargetTitle()) listo para verificación en vivo"
        )
    }

    var selectedCapabilityDescription: String {
        if localSafetyBlocked() || remoteSafetyLocked() {
            return localizedText(
                "Share the report, then fully close and reopen Eagle. Apply and Restore remain blocked so no second private call can start.",
                "Comparte el informe y luego cierra y abre Eagle completamente. Aplicar y Restaurar permanecen bloqueados para que no se inicie una segunda llamada privada."
            )
        }
        if !accessIsReady() {
            return localizedText(
                "Prepare Eagle access below before using Apply or Restore. No Aura call will be sent until access is ready.",
                "Prepara el acceso de Eagle abajo antes de usar Aplicar o Restaurar. No se enviará ninguna llamada Aura hasta que el acceso esté listo."
            )
        }
        if selectedTargetIsIsland() {
            if selectedMode() == .tint {
                return localizedText(
                    "Experimental True Tint requires the native adaptive iOS 18 Island background. Eagle verifies it during Apply and preserves the current Island if that host is unavailable.",
                    "True Tint experimental requiere el fondo adaptativo nativo de Island en iOS 18. Eagle lo verifica al aplicar y conserva la Island actual si ese host no está disponible."
                )
            }
            return localizedText(
                "Hardware is recognized. Eagle checks the current compact or expanded SpringBoard host during Apply; Dock is never included in this call.",
                "El hardware fue reconocido. Eagle verifica el host compacto o expandido actual de SpringBoard al aplicar; el Dock nunca se incluye en esta llamada."
            )
        } else {
            return localizedText(
                "Use the Home Screen before Apply so SpringBoard can expose the live Dock. Dynamic Island is never included in this call.",
                "Pasa por la pantalla de Inicio antes de Aplicar para que SpringBoard exponga el Dock activo. Dynamic Island nunca se incluye en esta llamada."
            )
        }
    }

    var isApplyButtonDisabled: Bool {
        operationInProgress() || !accessIsReady() || requestedFlags() == 0 ||
            localSafetyBlocked() || remoteSafetyLocked()
    }
}
