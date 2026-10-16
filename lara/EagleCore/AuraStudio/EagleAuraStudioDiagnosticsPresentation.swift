import Foundation

/// Read-only diagnostic wording/formatting; hardware classification, flag decoding and storage stay injected.
@MainActor
struct EagleAuraStudioDiagnosticsPresentation<Availability: Equatable> {
    let supportedAvailability: Availability
    let unsupportedAvailability: Availability
    let isSimulator: () -> Bool
    let availability: () -> Availability
    let readActiveFlags: () -> UInt32
    let readSupportedFlags: () -> UInt32
    let channel255: (Double) -> Int
    let localizedText: (String, String) -> String

    var islandHardwareUnavailableMessage: String {
        if isSimulator() {
            return localizedText(
                "Simulator can preview this model, but it cannot apply Island Aura to SpringBoard. Build for a supported physical iPhone. Dock remains unchanged.",
                "El simulador puede previsualizar este modelo, pero no puede aplicar el aura de Island a SpringBoard. Compila para un iPhone físico compatible. El Dock no cambió."
            )
        }
        switch availability() {
        case supportedAvailability:
            return localizedText(
                "Dynamic Island hardware is recognized, but this device is not available for a live SpringBoard change. Nothing was changed.",
                "El hardware de Dynamic Island fue reconocido, pero este dispositivo no está disponible para cambiar SpringBoard en vivo. No se cambió nada."
            )
        case unsupportedAvailability:
            return localizedText(
                "This iPhone model does not have Dynamic Island. Island Aura was not sent to SpringBoard, and Dock remains available.",
                "Este modelo de iPhone no tiene Dynamic Island. El aura de Island no se envió a SpringBoard y el Dock sigue disponible."
            )
        default:
            return localizedText(
                "This iPhone model has not been verified for Dynamic Island. Eagle stopped before contacting SpringBoard; Dock remains available.",
                "Este modelo de iPhone no ha sido verificado para Dynamic Island. Eagle se detuvo antes de contactar SpringBoard; el Dock sigue disponible."
            )
        }
    }

    func rgb255String(_ red: Double, _ green: Double, _ blue: Double) -> String {
        [red, green, blue]
            .map { String(channel255($0)) }
            .joined(separator: ",")
    }

    var activeModuleCount: Int {
        (readActiveFlags() & readSupportedFlags()).nonzeroBitCount
    }

    var verifiedSurfaceSummary: String {
        if activeModuleCount == 1 {
            return localizedText(
                "1 verified aura active in this SpringBoard session",
                "1 aura verificada activa en esta sesión de SpringBoard"
            )
        }
        return localizedText(
            "\(activeModuleCount) verified auras active in this SpringBoard session",
            "\(activeModuleCount) auras verificadas activas en esta sesión de SpringBoard"
        )
    }
}
