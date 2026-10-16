import Foundation

/// Result wording only. Native verification and result classification remain at the caller.
@MainActor
struct EagleAuraStudioResultFeedback {
    let islandFlag: UInt32
    let screenFlag: UInt32
    let batteryFlag: UInt32
    let dockFlag: UInt32
    let lockFlag: UInt32
    let modeTitle: (EagleAuraStudioMode) -> String
    let localizedText: (String, String) -> String

    func successMessage(
        appliedFlags: UInt32,
        requestedFlags: UInt32,
        restoring: Bool,
        motionDegraded: Bool,
        appliedMode: EagleAuraStudioMode?
    ) -> String {
        if restoring {
            let removed = names(for: appliedFlags)
            let missing = names(for: requestedFlags & ~appliedFlags)
            let removedText = removed.isEmpty
                ? localizedText("No aura", "Ningún aura")
                : removed.joined(separator: ", ")
            if !missing.isEmpty {
                return localizedText(
                    "Removed and verified: \(removedText). Not verified: \(missing.joined(separator: ", ")).",
                    "Eliminado y verificado: \(removedText). Sin verificar: \(missing.joined(separator: ", "))."
                )
            }
            return localizedText(
                "Removed and verified: \(removedText). The original system appearance is restored.",
                "Eliminado y verificado: \(removedText). Se restauró la apariencia original del sistema."
            )
        }
        let applied = names(for: appliedFlags)
        let missing = names(for: requestedFlags & ~appliedFlags)
        if motionDegraded {
            let unavailable = missing.isEmpty
                ? ""
                : localizedText(
                    " Unavailable: \(missing.joined(separator: ", ")).",
                    " No disponible: \(missing.joined(separator: ", "))."
                )
            return localizedText(
                "Applied and verified: \(applied.joined(separator: ", ")). The neon cores are active, but SpringBoard did not retain every moving color phase; no valid light was removed.",
                "Aplicado y verificado: \(applied.joined(separator: ", ")). Los núcleos de neón están activos, pero SpringBoard no conservó todas las fases móviles de color; no se eliminó ninguna luz válida."
            ) + unavailable
        }
        if missing.isEmpty {
            let style: String
            if appliedFlags != 0, let appliedMode {
                style = " · \(modeTitle(appliedMode))"
            } else {
                style = ""
            }
            return localizedText(
                "Applied and verified: \(applied.joined(separator: ", "))\(style).",
                "Aplicado y verificado: \(applied.joined(separator: ", "))\(style)."
            )
        }
        return localizedText(
            "Applied: \(applied.joined(separator: ", ")). Unavailable on the current SpringBoard state: \(missing.joined(separator: ", ")). No unavailable surface was reported as active.",
            "Aplicado: \(applied.joined(separator: ", ")). No disponible en el estado actual de SpringBoard: \(missing.joined(separator: ", ")). Ninguna superficie ausente se marcó como activa."
        )
    }

    func message(for result: Int32) -> String {
        switch result {
        case -2:
            return localizedText(
                "SpringBoard did not expose a safe, visible Dynamic Island host in its current state. Nothing was changed; unlock the iPhone, visit the Home or Lock Screen once, and try again.",
                "SpringBoard no expuso un host seguro y visible de Dynamic Island en su estado actual. No se cambió nada; desbloquea el iPhone, visita una vez la pantalla de Inicio o Bloqueo y vuelve a intentarlo."
            )
        case -3:
            return localizedText("The selected aura style is invalid.", "El estilo de aura seleccionado no es válido.")
        case -4:
            return localizedText(
                "The SpringBoard session did not provide an isolated call thread.",
                "La sesión de SpringBoard no proporcionó un hilo aislado de llamadas."
            )
        case -5:
            return localizedText(
                "This iOS version is outside Aura Studio's verified range.",
                "Esta versión de iOS está fuera del rango verificado de Aura Studio."
            )
        case -6:
            return localizedText(
                "SpringBoard could not create the selected aura color.",
                "SpringBoard no pudo crear el color de aura seleccionado."
            )
        case -7:
            return localizedText(
                "Aura Studio caught a system exception and stopped without reporting success.",
                "Aura Studio detectó una excepción del sistema y se detuvo sin mostrar un éxito falso."
            )
        case -8:
            return localizedText(
                "Eagle could not resolve the safe Dynamic Island window.",
                "Eagle no pudo resolver la ventana segura de Dynamic Island."
            )
        case -9:
            return localizedText(
                "SpringBoard did not provide the UIKit classes required for Island Aura.",
                "SpringBoard no proporcionó las clases de UIKit necesarias para Island Aura."
            )
        case -10:
            return localizedText(
                "SpringBoard could not create or position the Island Aura view.",
                "SpringBoard no pudo crear o posicionar la vista de Island Aura."
            )
        case -11:
            return localizedText(
                "SpringBoard created the Island host but rejected its light layer.",
                "SpringBoard creó el host de Island, pero rechazó su capa luminosa."
            )
        case -12:
            return localizedText(
                "The new Island candidate could not be read back safely, so Eagle rejected and removed it instead of reporting a partial effect as applied. Any previously verified Island was preserved.",
                "El nuevo candidato de Island no pudo verificarse de forma segura, por lo que Eagle lo rechazó y eliminó en vez de marcar un efecto parcial como aplicado. Se conservó cualquier Island verificada anteriormente."
            )
        case -13:
            return localizedText(
                "The SpringBoard session is missing its isolated call thread.",
                "La sesión de SpringBoard no tiene su hilo aislado de llamadas."
            )
        case -14:
            return localizedText(
                "Island Aura caught a SpringBoard exception. The resulting system state could not be verified, so Eagle cleared the verified badge.",
                "Island Aura detectó una excepción de SpringBoard. No se pudo verificar el estado resultante del sistema, por lo que Eagle eliminó el indicador de verificación."
            )
        case -15:
            return localizedText(
                "The thick Island glow is active, but SpringBoard did not retain the moving Rainbow animation. The static core was preserved; choose Glow if you want the verified style.",
                "El brillo grueso de Island está activo, pero SpringBoard no conservó la animación Rainbow. El núcleo estático se mantuvo; elige Brillo para usar el estilo verificado."
            )
        case -16:
            return localizedText(
                "SpringBoard did not retain the native Tint background or its gain-map change. Eagle restored and verified the black Glow center; no color layer was left over.",
                "SpringBoard no conservó el fondo nativo de Color o el cambio de su mapa de ganancia. Eagle restauró y verificó el centro negro de Brillo; no quedó ninguna capa de color."
            )
        case -17:
            return localizedText(
                "True Tint needs the native adaptive Island background available on this iOS 18 SpringBoard state. Eagle preserved the current aura instead of placing color over music or timer controls.",
                "Color real necesita el fondo adaptativo nativo de Island disponible en este estado de SpringBoard de iOS 18. Eagle conservó el aura actual en vez de poner color sobre los controles de música o temporizador."
            )
        case -18:
            return localizedText(
                "Eagle could not verify the complete return to the black system center. The verified badge was cleared. Reopen Eagle on the Home Screen and choose Glow or Remove again.",
                "Eagle no pudo verificar el regreso completo al centro negro del sistema. Se eliminó el indicador de verificación. Abre Eagle de nuevo desde Inicio y elige Brillo o Eliminar otra vez."
            )
        case -19:
            return localizedText(
                "SpringBoard did not expose the Home Screen Dock for a verified removal. The Dock badge was cleared and Island was not touched. Return to the Home Screen, reopen Eagle, and choose Remove Dock again.",
                "SpringBoard no mostró el Dock de Inicio para verificar su eliminación. Se borró el indicador del Dock y no se modificó Island. Vuelve a Inicio, abre Eagle y elige Eliminar Dock nuevamente."
            )
        case -20:
            return localizedText(
                "SpringBoard did not expose the live Home Screen Dock. Island was not reported as the Dock. Return to the Home Screen once, reopen Aura Studio, and try Dock again.",
                "SpringBoard no mostró el Dock activo de Inicio. Island no se marcó como Dock. Vuelve una vez a Inicio, abre Aura Studio y prueba el Dock nuevamente."
            )
        case -21:
            return localizedText(
                "The live Dock was found, but its neon core could not be read back safely. Eagle removed only the unverified Dock layer.",
                "Se encontró el Dock activo, pero su núcleo de neón no pudo verificarse de forma segura. Eagle eliminó únicamente la capa del Dock no verificada."
            )
        case -22:
            return localizedText(
                "Aura Studio refused a combined Island and Dock request before changing SpringBoard. Select one profile and apply it separately.",
                "Aura Studio rechazó una solicitud combinada de Island y Dock antes de cambiar SpringBoard. Selecciona un perfil y aplícalo por separado."
            )
        case -23:
            return localizedText(
                "The protected SpringBoard session became unavailable before this surface could be changed. Nothing was reported as applied. Export the report, fully close Eagle, and reopen it before retrying.",
                "La sesión protegida de SpringBoard dejó de estar disponible antes de cambiar esta superficie. No se indicó nada como aplicado. Exporta el informe, cierra Eagle completamente y vuelve a abrirlo antes de intentarlo de nuevo."
            )
        case -24:
            return localizedText(
                "Island rejected the new candidate, but SpringBoard did not provide enough read-back to verify the previous appearance. Eagle stopped and safety locked this run; export the report, then fully close and reopen Eagle.",
                "Island rechazó el nuevo candidato, pero SpringBoard no proporcionó suficiente lectura para verificar la apariencia anterior. Eagle se detuvo y bloqueó esta ejecución por seguridad; exporta el informe y luego cierra y vuelve a abrir Eagle."
            )
        default:
            return localizedText(
                "SpringBoard rejected the Aura Studio update.",
                "SpringBoard rechazó la actualización de Aura Studio."
            )
        }
    }

    func names(for flags: UInt32) -> [String] {
        var names: [String] = []
        if flags & islandFlag != 0 {
            names.append(localizedText("Island", "Isla"))
        }
        if flags & screenFlag != 0 {
            names.append(localizedText("Screen", "Pantalla"))
        }
        if flags & batteryFlag != 0 {
            names.append(localizedText("Battery Halo", "Halo de batería"))
        }
        if flags & dockFlag != 0 { names.append("Dock") }
        if flags & lockFlag != 0 {
            names.append(localizedText("Lock", "Bloqueo"))
        }
        return names
    }
}

