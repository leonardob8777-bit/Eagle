import Foundation

/// Status decisions and messages; compatibility, state and localization stay injected.
@MainActor
struct EagleAuraStudioProfileStatus<Target: Equatable> {
    let islandTarget: Target
    let dockTarget: Target
    let islandProfileAvailable: () -> Bool
    let islandModelUnknown: () -> Bool
    let isTargetActive: (Target) -> Bool
    let readDockMode: () -> Int
    let readIslandMode: () -> Int
    let activeMode: (Target) -> EagleAuraStudioMode?
    let draftMatchesActive: (Target) -> Bool
    let modeTitle: (EagleAuraStudioMode) -> String
    let localizedText: (String, String) -> String

    func profileStatusText(for target: Target) -> String {
        if target == islandTarget && !islandProfileAvailable() {
            return islandModelUnknown()
                ? localizedText(
                    "Unknown model · Island disabled safely",
                    "Modelo desconocido · Island desactivada de forma segura"
                )
                : localizedText(
                    "This iPhone has no Dynamic Island",
                    "Este iPhone no tiene Dynamic Island"
                )
        }
        if target == dockTarget,
           isTargetActive(target),
           ((15...31).contains(readDockMode()) || readDockMode() == 35) {
            return localizedText(
                "Dock Gallery artwork active",
                "Arte de Galería Dock activo"
            )
        }
        if target == islandTarget,
           isTargetActive(target),
           ((32...34).contains(readIslandMode()) || readIslandMode() == 36) {
            return localizedText(
                "Island Gallery artwork active",
                "Arte de Galería Island activo"
            )
        }
        guard let appliedMode = activeMode(target), isTargetActive(target) else {
            return localizedText("Not active", "No activo")
        }
        if draftMatchesActive(target) {
            return localizedText(
                "Applied · \(modeTitle(appliedMode))",
                "Aplicado · \(modeTitle(appliedMode))"
            )
        }
        return localizedText(
            "Active: \(modeTitle(appliedMode)) · selected changes not applied",
            "Activo: \(modeTitle(appliedMode)) · cambios seleccionados sin aplicar"
        )
    }
}
