import CryptoKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Guardian

enum EagleGuardianError: LocalizedError {
    case unreadable
    case unsupported
    case integrity
    case unsafeSnapshot

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return LaraL10n.text(
                en: "This recovery point could not be read.",
                es: "No se pudo leer este punto de recuperación."
            )
        case .unsupported:
            return LaraL10n.text(
                en: "This recovery point was created by an unsupported Eagle format.",
                es: "Este punto fue creado con un formato de Eagle no compatible."
            )
        case .integrity:
            return LaraL10n.text(
                en: "Verification failed. Guardian blocked the restore before changing any file.",
                es: "La verificación falló. Guardian bloqueó la restauración antes de cambiar archivos."
            )
        case .unsafeSnapshot:
            return LaraL10n.text(
                en: "The recovery point contains an unsafe or incomplete file record.",
                es: "El punto contiene un registro de archivo inseguro o incompleto."
            )
        }
    }
}

struct EagleGuardianManifestEntry: Codable, Hashable, Identifiable {
    let path: String
    let byteCount: Int
    let digest: String

    var id: String { path }
}

struct EagleGuardianCheckpoint: Codable, Identifiable {
    let formatVersion: Int
    let id: UUID
    let createdAt: Date
    let title: String
    let components: [String]
    let snapshotPayload: Data
    let snapshotDigest: String
    let manifest: [EagleGuardianManifestEntry]

    var verifiedByteCount: Int {
        manifest.reduce(0) { $0 + $1.byteCount }
    }

    var componentTitles: String {
        let values = components.compactMap { raw in
            CompleteStyleComponent(rawValue: raw)?.title
        }
        return values.isEmpty
            ? LaraL10n.text(en: "System state", es: "Estado del sistema")
            : values.joined(separator: " · ")
    }

    func verifiedSnapshot() throws -> CompleteStyleUndoSnapshot {
        guard formatVersion == 1 else { throw EagleGuardianError.unsupported }
        guard EagleIntegrity.digest(snapshotPayload) == snapshotDigest,
              let snapshot = try? PropertyListDecoder().decode(
                CompleteStyleUndoSnapshot.self,
                from: snapshotPayload
              ) else {
            throw EagleGuardianError.integrity
        }

        let files = snapshot.passcodeFiles +
            [snapshot.cardFile].compactMap { $0 } +
            (snapshot.wallpaperFilesToRestore ?? [])
        guard files.count <= 576,
              Set(files.map(\.path)).count == files.count,
              files.allSatisfy({
                  $0.path.hasPrefix("/") &&
                  !$0.path.contains("../") &&
                  !$0.data.isEmpty &&
                  $0.data.count <= 64 * 1024 * 1024
              }) else {
            throw EagleGuardianError.unsafeSnapshot
        }

        let wallpaperRoots = (snapshot.wallpaperDirectoriesToRestore ?? []).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        }
        let wallpaperFiles = snapshot.wallpaperFilesToRestore ?? []
        guard wallpaperRoots.allSatisfy({
            $0.contains("/Library/Application Support/PRBPosterExtensionDataStore/") &&
            $0.contains("/Extensions/") &&
            $0.contains("/descriptors/")
        }), wallpaperFiles.allSatisfy({ file in
            wallpaperRoots.contains(where: { file.path.hasPrefix($0 + "/") })
        }) else {
            throw EagleGuardianError.unsafeSnapshot
        }

        let rebuilt = files.map {
            EagleGuardianManifestEntry(
                path: $0.path,
                byteCount: $0.data.count,
                digest: EagleIntegrity.digest($0.data)
            )
        }.sorted { $0.path < $1.path }

        guard rebuilt == manifest.sorted(by: { $0.path < $1.path }) else {
            throw EagleGuardianError.integrity
        }
        return snapshot
    }
}

enum EagleIntegrity {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class EagleGuardianTransactionContext {
    static let shared = EagleGuardianTransactionContext()
    private var nextTransactionChangesLiveConfiguration = false

    private init() {}

    func markLiveChange() {
        nextTransactionChangesLiveConfiguration = true
    }

    func consumeLiveChange() -> Bool {
        defer { nextTransactionChangesLiveConfiguration = false }
        return nextTransactionChangesLiveConfiguration
    }
}

@MainActor
final class EagleGuardianStore: ObservableObject {
    static let shared = EagleGuardianStore()

    @Published private(set) var checkpoints: [EagleGuardianCheckpoint] = []
    @Published private(set) var invalidCheckpointCount = 0

    private let fm = FileManager.default
    private let directory: URL
    private let maximumCheckpoints = 12

    private init() {
        directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Eagle", isDirectory: true)
            .appendingPathComponent("Guardian", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        refresh()
    }

    var pendingCheckpoint: EagleGuardianCheckpoint? {
        guard let snapshot = CompleteStyleUndoStore.shared.loadPending() else { return nil }
        return try? makeCheckpoint(from: snapshot, allowEmptyComponents: true)
    }

    var statusTitle: String {
        if invalidCheckpointCount > 0 {
            return LaraL10n.text(en: "Action needed", es: "Requiere atención")
        }
        return LaraL10n.text(en: "Protection verified", es: "Protección verificada")
    }

    func archive(_ snapshot: CompleteStyleUndoSnapshot) throws {
        guard !snapshot.changedComponents.isEmpty else { return }
        let checkpoint = try makeCheckpoint(from: snapshot, allowEmptyComponents: false)
        let url = fileURL(for: checkpoint.id)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(checkpoint)
        try data.write(to: url, options: .atomic)

        guard let written = try? Data(contentsOf: url),
              let decoded = try? PropertyListDecoder().decode(EagleGuardianCheckpoint.self, from: written) else {
            try? fm.removeItem(at: url)
            throw EagleGuardianError.unreadable
        }
        _ = try decoded.verifiedSnapshot()
        pruneIfNeeded()
        refresh()
    }

    func protectLiveChange(named title: String) throws {
        let styleManager = CompleteStyleManager.shared
        var snapshot = CompleteStyleUndoSnapshot(
            createdAt: Date(),
            previousActiveName: styleManager.activeStyleName,
            previousActivePackID: styleManager.activePackID,
            previousVisualPackID: styleManager.activeVisualPackID,
            passcodeFiles: [],
            cardFile: nil,
            installedWallpaperPaths: [],
            changedComponents: ["homeScreen"]
        )
        snapshot.transactionID = UUID()
        snapshot.displayName = title
        snapshot.previousDockCapacity = UserDefaults.standard.object(
            forKey: "eagle.dock.capacity"
        ) as? Int ?? 4
        snapshot.previousIconThemeNames = IconThemeManager.shared.selectedThemeNames
        snapshot.previousIconShape = IconThemeManager.shared.selectedIconShape.rawValue
        snapshot.changedLiveConfiguration = true
        try CompleteStyleUndoStore.shared.begin(snapshot)
        try CompleteStyleUndoStore.shared.commit(snapshot)
        styleManager.refreshUndoAvailability()
    }

    func refresh() {
        let urls = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var valid: [EagleGuardianCheckpoint] = []
        var invalid = 0
        for url in urls where url.pathExtension == "guardian" {
            guard let data = try? Data(contentsOf: url),
                  let checkpoint = try? PropertyListDecoder().decode(
                    EagleGuardianCheckpoint.self,
                    from: data
                  ) else {
                invalid += 1
                continue
            }
            do {
                _ = try checkpoint.verifiedSnapshot()
                valid.append(checkpoint)
            } catch {
                invalid += 1
            }
        }
        checkpoints = valid.sorted { $0.createdAt > $1.createdAt }
        invalidCheckpointCount = invalid
    }

    func delete(_ checkpoint: EagleGuardianCheckpoint) {
        try? fm.removeItem(at: fileURL(for: checkpoint.id))
        refresh()
    }

    func discardPendingRecovery() {
        CompleteStyleUndoStore.shared.discardPending()
        refresh()
    }

    private func makeCheckpoint(
        from snapshot: CompleteStyleUndoSnapshot,
        allowEmptyComponents: Bool
    ) throws -> EagleGuardianCheckpoint {
        guard allowEmptyComponents || !snapshot.changedComponents.isEmpty else {
            throw EagleGuardianError.unsafeSnapshot
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(snapshot)
        guard payload.count <= 192 * 1024 * 1024 else {
            throw EagleGuardianError.unsafeSnapshot
        }
        let files = snapshot.passcodeFiles +
            [snapshot.cardFile].compactMap { $0 } +
            (snapshot.wallpaperFilesToRestore ?? [])
        let manifest = files.map {
            EagleGuardianManifestEntry(
                path: $0.path,
                byteCount: $0.data.count,
                digest: EagleIntegrity.digest($0.data)
            )
        }
        let checkpoint = EagleGuardianCheckpoint(
            formatVersion: 1,
            id: snapshot.transactionID ?? UUID(),
            createdAt: snapshot.createdAt,
            title: LaraL10n.localized(
                snapshot.displayName ?? LaraL10n.text(en: "Eagle change", es: "Cambio de Eagle")
            ),
            components: snapshot.changedComponents,
            snapshotPayload: payload,
            snapshotDigest: EagleIntegrity.digest(payload),
            manifest: manifest
        )
        _ = try checkpoint.verifiedSnapshot()
        return checkpoint
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("guardian")
    }

    private func pruneIfNeeded() {
        refresh()
        for checkpoint in checkpoints.dropFirst(maximumCheckpoints) {
            try? fm.removeItem(at: fileURL(for: checkpoint.id))
        }
    }
}

// MARK: - Scenes

extension EagleSceneAuraMode {
    var localizedName: String {
        switch self {
        case .glow: return LaraL10n.text(en: "Glow", es: "Brillo")
        case .pulse: return LaraL10n.text(en: "Pulse", es: "Pulso")
        case .tint: return LaraL10n.text(en: "Tint", es: "Color")
        case .rainbow: return LaraL10n.text(en: "Rainbow", es: "Arcoíris")
        }
    }
}

extension EagleSceneComponent {
    var localizedName: String {
        switch self {
        case .wallpaper: return LaraL10n.text(en: "Wallpaper", es: "Fondo")
        case .passcode: return LaraL10n.text(en: "Passcode", es: "Código")
        case .card: return LaraL10n.text(en: "Wallet card", es: "Tarjeta de Wallet")
        case .dockLayout: return LaraL10n.text(en: "Dock layout", es: "Diseño del Dock")
        case .icons: return LaraL10n.text(en: "Icons", es: "Iconos")
        case .islandAura: return "Dynamic Island Aura"
        case .dockAura: return "Dock Aura"
        }
    }
}

extension EagleSceneResultState {
    var localizedName: String {
        switch self {
        case .pending: return LaraL10n.text(en: "Pending", es: "Pendiente")
        case .applied: return LaraL10n.text(en: "Applied", es: "Aplicado")
        case .skipped: return LaraL10n.text(en: "Skipped", es: "Omitido")
        case .failed: return LaraL10n.text(en: "Failed", es: "Falló")
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock.fill"
        case .applied: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .blue
        case .applied: return .green
        case .skipped: return .secondary
        case .failed: return .orange
        }
    }
}

struct EagleScene: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var packID: String
    var wallpaperPackID: String? = nil
    var passcodePackID: String? = nil
    var cardPackID: String? = nil
    var wallpaper: Bool
    var passcode: Bool
    var card: Bool
    var dockCapacity: Int?
    var iconThemeNames: [String]
    var iconShapeRaw: String?
    var islandAura: EagleSceneAuraProfile? = nil
    var dockAura: EagleSceneAuraProfile? = nil
    var isBuiltIn: Bool
    let createdAt: Date

    var pack: CompleteStylePack? {
        CompleteStylePack.all.first { $0.id == packID }
    }

    var wallpaperPack: CompleteStylePack? {
        CompleteStylePack.all.first { $0.id == (wallpaperPackID ?? packID) }
    }

    var passcodePack: CompleteStylePack? {
        CompleteStylePack.all.first { $0.id == (passcodePackID ?? packID) }
    }

    var cardPack: CompleteStylePack? {
        CompleteStylePack.all.first { $0.id == (cardPackID ?? packID) }
    }

    var isFusion: Bool {
        let identifiers = Set([
            wallpaper ? wallpaperPack?.id : nil,
            passcode ? passcodePack?.id : nil,
            card ? cardPack?.id : nil
        ].compactMap { $0 })
        return identifiers.count > 1
    }

    var localizedName: String {
        guard isBuiltIn else { return name }
        switch name {
        case "Focus": return LaraL10n.text(en: "Focus", es: "Enfoque")
        case "Night": return LaraL10n.text(en: "Night", es: "Noche")
        case "Play": return LaraL10n.text(en: "Play", es: "Juego")
        case "Calm": return LaraL10n.text(en: "Calm", es: "Calma")
        default: return name
        }
    }

    var selectedPartCount: Int {
        [wallpaper, passcode, card].filter { $0 }.count
    }

    var requestedComponents: [EagleSceneComponent] {
        var components: [EagleSceneComponent] = []
        if wallpaper { components.append(.wallpaper) }
        if passcode { components.append(.passcode) }
        if card { components.append(.card) }
        if dockCapacity != nil { components.append(.dockLayout) }
        if !iconThemeNames.isEmpty || iconShapeRaw != nil { components.append(.icons) }
        if islandAura != nil { components.append(.islandAura) }
        if dockAura != nil { components.append(.dockAura) }
        return components
    }

    var summary: String {
        var parts: [String] = []
        if isFusion { parts.append("Fusion") }
        if wallpaper {
            parts.append(isFusion
                ? LaraL10n.text(
                    en: "Wallpaper \(wallpaperPack?.localizedName ?? "—")",
                    es: "Fondo \(wallpaperPack?.localizedName ?? "—")"
                )
                : LaraL10n.text(en: "Wallpaper", es: "Fondo"))
        }
        if passcode {
            parts.append(isFusion
                ? LaraL10n.text(
                    en: "Passcode \(passcodePack?.localizedName ?? "—")",
                    es: "Código \(passcodePack?.localizedName ?? "—")"
                )
                : LaraL10n.text(en: "Passcode", es: "Código"))
        }
        if card {
            parts.append(isFusion
                ? LaraL10n.text(
                    en: "Card \(cardPack?.localizedName ?? "—")",
                    es: "Tarjeta \(cardPack?.localizedName ?? "—")"
                )
                : LaraL10n.text(en: "Card", es: "Tarjeta"))
        }
        if let dockCapacity { parts.append("Dock \(dockCapacity)") }
        if !iconThemeNames.isEmpty || iconShapeRaw != nil {
            parts.append(LaraL10n.text(en: "Icons", es: "Iconos"))
        }
        if let islandAura {
            parts.append("Island \(islandAura.mode.localizedName)")
        }
        if let dockAura {
            parts.append("Dock Aura \(dockAura.mode.localizedName)")
        }
        return parts.joined(separator: " · ")
    }

    func importedCopy() -> EagleScene {
        EagleScene(
            id: UUID(),
            name: localizedName,
            symbol: symbol,
            packID: packID,
            wallpaperPackID: wallpaperPackID,
            passcodePackID: passcodePackID,
            cardPackID: cardPackID,
            wallpaper: wallpaper,
            passcode: passcode,
            card: card,
            dockCapacity: dockCapacity,
            iconThemeNames: iconThemeNames,
            iconShapeRaw: iconShapeRaw,
            islandAura: islandAura,
            dockAura: dockAura,
            isBuiltIn: false,
            createdAt: Date()
        )
    }

    static let builtIns: [EagleScene] = [
        EagleScene(
            id: UUID(uuidString: "EAF10000-0000-4000-8000-000000000001")!,
            name: "Focus",
            symbol: "scope",
            packID: "terminal",
            wallpaper: true,
            passcode: true,
            card: true,
            dockCapacity: 4,
            iconThemeNames: [],
            iconShapeRaw: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 1)
        ),
        EagleScene(
            id: UUID(uuidString: "EAF10000-0000-4000-8000-000000000002")!,
            name: "Night",
            symbol: "moon.stars.fill",
            packID: "obsidian",
            wallpaper: true,
            passcode: true,
            card: true,
            dockCapacity: 5,
            iconThemeNames: [],
            iconShapeRaw: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 2)
        ),
        EagleScene(
            id: UUID(uuidString: "EAF10000-0000-4000-8000-000000000003")!,
            name: "Play",
            symbol: "gamecontroller.fill",
            packID: "arcade",
            wallpaper: true,
            passcode: true,
            card: true,
            dockCapacity: 6,
            iconThemeNames: [],
            iconShapeRaw: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 3)
        ),
        EagleScene(
            id: UUID(uuidString: "EAF10000-0000-4000-8000-000000000004")!,
            name: "Calm",
            symbol: "wind",
            packID: "brisa",
            wallpaper: true,
            passcode: true,
            card: true,
            dockCapacity: 5,
            iconThemeNames: [],
            iconShapeRaw: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 4)
        )
    ]
}

struct EagleMomentSuggestion {
    let scene: EagleScene
    let headline: String
    let reason: String
    let factors: [String]
    let accent: Color
}

enum EagleMomentEngine {
    static func suggestion(at date: Date = Date()) -> EagleMomentSuggestion {
        let calendar = Calendar.autoupdatingCurrent
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let weekend = weekday == 1 || weekday == 7
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        if lowPower {
            return build(
                name: LaraL10n.text(en: "Essential", es: "Esencial"),
                symbol: "battery.25percent",
                wallpaper: "terminal",
                passcode: "terminal",
                card: "obsidian",
                dock: 4,
                headline: LaraL10n.text(en: "Less noise, less energy", es: "Menos ruido, menos energía"),
                reason: LaraL10n.text(
                    en: "Low Power Mode is active, so Moment favors a dark, focused combination and a compact Dock.",
                    es: "El modo de bajo consumo está activo, así que Moment prioriza una combinación oscura y un Dock compacto."
                ),
                factors: [
                    LaraL10n.text(en: "Low Power", es: "Bajo consumo"),
                    LaraL10n.text(en: "Dark palette", es: "Paleta oscura"),
                    "Dock 4"
                ],
                accent: .green
            )
        }

        if hour >= 21 || hour < 6 {
            return build(
                name: LaraL10n.text(en: "After Dark", es: "Trasnoche"),
                symbol: "moon.stars.fill",
                wallpaper: "obsidian",
                passcode: "neon",
                card: "obsidian",
                dock: 5,
                headline: LaraL10n.text(en: "Color without nighttime glare", es: "Color sin brillo nocturno"),
                reason: LaraL10n.text(
                    en: "It is late, so Moment keeps the wallpaper and Wallet dark while giving the passcode a controlled neon accent.",
                    es: "Es tarde, así que Moment mantiene oscuros el fondo y Wallet, con un acento neón controlado en el código."
                ),
                factors: [
                    LaraL10n.text(en: "Night", es: "Noche"),
                    LaraL10n.text(en: "High contrast", es: "Alto contraste"),
                    "Dock 5"
                ],
                accent: .indigo
            )
        }

        if weekend && hour >= 10 && hour < 21 {
            return build(
                name: LaraL10n.text(en: "Weekend Energy", es: "Energía de fin de semana"),
                symbol: "sparkles",
                wallpaper: "arcade",
                passcode: "neon",
                card: "aero",
                dock: 6,
                headline: LaraL10n.text(en: "A brighter, playful mix", es: "Una mezcla más viva y divertida"),
                reason: LaraL10n.text(
                    en: "It is daytime on the weekend, so Moment opens the palette and gives the Dock maximum useful space.",
                    es: "Es de día durante el fin de semana, así que Moment abre la paleta y da al Dock el máximo espacio útil."
                ),
                factors: [
                    LaraL10n.text(en: "Weekend", es: "Fin de semana"),
                    LaraL10n.text(en: "Daylight", es: "Luz de día"),
                    "Dock 6"
                ],
                accent: .orange
            )
        }

        if !weekend && hour >= 7 && hour < 18 {
            return build(
                name: LaraL10n.text(en: "Deep Work", es: "Concentración"),
                symbol: "scope",
                wallpaper: "terminal",
                passcode: "terminal",
                card: "obsidian",
                dock: 4,
                headline: LaraL10n.text(en: "Useful information, fewer distractions", es: "Información útil, menos distracciones"),
                reason: LaraL10n.text(
                    en: "It is a weekday work period, so Moment chooses a precise palette and the standard Dock layout.",
                    es: "Es un período de trabajo entre semana, así que Moment elige una paleta precisa y el Dock estándar."
                ),
                factors: [
                    LaraL10n.text(en: "Weekday", es: "Entre semana"),
                    LaraL10n.text(en: "Focus", es: "Enfoque"),
                    "Dock 4"
                ],
                accent: .green
            )
        }

        return build(
            name: LaraL10n.text(en: "Reset", es: "Reinicio"),
            symbol: "wind",
            wallpaper: "brisa",
            passcode: "aero",
            card: "brisa",
            dock: 5,
            headline: LaraL10n.text(en: "A calmer transition", es: "Una transición más tranquila"),
            reason: LaraL10n.text(
                en: "This is a transition period, so Moment uses a balanced blue palette with comfortable Dock spacing.",
                es: "Es un período de transición, así que Moment usa una paleta azul equilibrada y un Dock cómodo."
            ),
            factors: [
                LaraL10n.text(en: "Balanced", es: "Equilibrado"),
                LaraL10n.text(en: "Calm palette", es: "Paleta tranquila"),
                "Dock 5"
            ],
            accent: .cyan
        )
    }

    private static func build(
        name: String,
        symbol: String,
        wallpaper: String,
        passcode: String,
        card: String,
        dock: Int,
        headline: String,
        reason: String,
        factors: [String],
        accent: Color
    ) -> EagleMomentSuggestion {
        let stableID = UUID(uuidString: "EAF20000-0000-4000-8000-000000000001")!
        let scene = EagleScene(
            id: stableID,
            name: name,
            symbol: symbol,
            packID: wallpaper,
            wallpaperPackID: wallpaper,
            passcodePackID: passcode,
            cardPackID: card,
            wallpaper: true,
            passcode: true,
            card: true,
            dockCapacity: dock,
            iconThemeNames: [],
            iconShapeRaw: nil,
            isBuiltIn: false,
            createdAt: Date()
        )
        return EagleMomentSuggestion(
            scene: scene,
            headline: headline,
            reason: reason,
            factors: factors,
            accent: accent
        )
    }
}

@MainActor
final class EagleLiveConfigurationController {
    static let shared = EagleLiveConfigurationController()

    private init() {}

    func applyForScene(
        dockCapacity: Int?,
        iconThemeNames: [String]?,
        iconShapeRaw: String?,
        applyIcons: Bool
    ) async -> [EagleSceneComponentResult] {
        let iconManager = IconThemeManager.shared
        let availableNames = Set(iconManager.themes.map(\.name))
        let requestedNames = iconThemeNames ?? []
        let validNames = requestedNames.filter { availableNames.contains($0) }
        var results: [EagleSceneComponentResult] = []
        let validDockCapacity = dockCapacity.flatMap { (4...6).contains($0) ? $0 : nil }
        let requestedShape = iconShapeRaw.flatMap(EagleIconShape.init(rawValue:))

        if let validDockCapacity {
            UserDefaults.standard.set(validDockCapacity, forKey: "eagle.dock.capacity")
        } else if dockCapacity != nil {
            results.append(.init(
                component: .dockLayout,
                state: .failed,
                detail: LaraL10n.text(
                    en: "The saved Dock capacity is outside the supported 4–6 range.",
                    es: "La capacidad guardada del Dock está fuera del rango compatible de 4 a 6."
                )
            ))
        }
        if iconThemeNames != nil {
            iconManager.selectedThemeNames = validNames
            iconManager.saveSelection()
        }
        if let shape = requestedShape {
            iconManager.selectedIconShape = shape
        } else if iconShapeRaw != nil {
            results.append(.init(
                component: .icons,
                state: .failed,
                detail: LaraL10n.text(
                    en: "The saved icon shape is no longer recognized.",
                    es: "La forma de iconos guardada ya no se reconoce."
                )
            ))
        }

        let shouldApplyDock = validDockCapacity != nil
        let shouldApplyIcons = applyIcons && (iconShapeRaw == nil || requestedShape != nil)
        guard shouldApplyDock || shouldApplyIcons else {
            return results
        }
        guard laramgr.shared.dsready else {
            if shouldApplyDock {
                results.append(.init(
                    component: .dockLayout,
                    state: .pending,
                    detail: LaraL10n.text(en: "Waiting for Prepare access.", es: "Esperando que prepares el acceso.")
                ))
            }
            if shouldApplyIcons {
                results.append(.init(
                    component: .icons,
                    state: .pending,
                    detail: LaraL10n.text(en: "Waiting for Prepare access.", es: "Esperando que prepares el acceso.")
                ))
            }
            return results
        }
        guard await prepareSpringBoardSession(), let process = laramgr.shared.sbProc else {
            let detail = LaraL10n.text(
                en: "SpringBoard was unavailable; no live value was reported as applied.",
                es: "SpringBoard no estuvo disponible; ningún valor en vivo se marcó como aplicado."
            )
            if shouldApplyDock {
                results.append(.init(component: .dockLayout, state: .failed, detail: detail))
            }
            if shouldApplyIcons {
                results.append(.init(component: .icons, state: .failed, detail: detail))
            }
            return results
        }

        if let validDockCapacity {
            let processBox = EagleRemoteCallBox(process)
            let result: Int32 = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: set_dock_icon_count(processBox.value, Int32(validDockCapacity)))
                }
            }
            results.append(.init(
                component: .dockLayout,
                state: result == 0 ? .applied : .failed,
                detail: result == 0
                    ? LaraL10n.text(en: "Dock verified with \(validDockCapacity) icons.", es: "Dock verificado con \(validDockCapacity) iconos.")
                    : LaraL10n.text(en: "Dock returned result \(result) and was not verified.", es: "El Dock devolvió el resultado \(result) y no fue verificado.")
            ))
        }

        if shouldApplyIcons {
            if !requestedNames.isEmpty, validNames.isEmpty, iconShapeRaw == nil {
                results.append(.init(
                    component: .icons,
                    state: .skipped,
                    detail: LaraL10n.text(
                        en: "None of the Scene's icon themes are installed.",
                        es: "Ninguno de los temas de iconos de la Scene está instalado."
                    )
                ))
                return results
            }
            let result: Result<EagleLiveIconResult, Error> = await withCheckedContinuation { continuation in
                iconManager.applyLiveIcons { continuation.resume(returning: $0) }
            }
            switch result {
            case .success(let value):
                let verifiedRequestedTheme = requestedNames.isEmpty || value.themedIconCount > 0
                let missingSuffix = requestedNames.count == validNames.count
                    ? ""
                    : LaraL10n.text(en: " Some referenced themes were not installed.", es: " Algunos temas referenciados no estaban instalados.")
                results.append(.init(
                    component: .icons,
                    state: verifiedRequestedTheme ? .applied : .failed,
                    detail: verifiedRequestedTheme
                        ? LaraL10n.text(
                            en: "\(value.shapedIconCount) Home Screen icons were verified; \(value.themedIconCount) received theme artwork.",
                            es: "Se verificaron \(value.shapedIconCount) iconos de inicio; \(value.themedIconCount) recibieron el tema."
                        ) + missingSuffix
                        : LaraL10n.text(
                            en: "The icon shape was verified, but no requested theme artwork was applied.",
                            es: "La forma de los iconos se verificó, pero no se aplicó el tema solicitado."
                        )
                ))
            case .failure(let error):
                results.append(.init(
                    component: .icons,
                    state: .failed,
                    detail: error.localizedDescription
                ))
            }
        }
        return results
    }

    /// Compatibility adapter for Complete Styles while Scenes consumes the
    /// structured component results directly.
    func apply(
        dockCapacity: Int?,
        iconThemeNames: [String]?,
        iconShapeRaw: String?,
        applyIcons: Bool
    ) async -> String {
        let results = await applyForScene(
            dockCapacity: dockCapacity,
            iconThemeNames: iconThemeNames,
            iconShapeRaw: iconShapeRaw,
            applyIcons: applyIcons
        )
        return results.map {
            "\($0.component.localizedName): \($0.state.localizedName) — \($0.detail)"
        }.joined(separator: ". ")
    }

    private func prepareSpringBoardSession() async -> Bool {
        let mgr = laramgr.shared
        if mgr.rcready, mgr.sbProc != nil { return true }
        return await withCheckedContinuation { continuation in
            mgr.rcinit(process: "SpringBoard") { success in
                continuation.resume(returning: success || (mgr.rcready && mgr.sbProc != nil))
            }
        }
    }
}

private final class EagleRemoteCallBox: @unchecked Sendable {
    let value: RemoteCall

    init(_ value: RemoteCall) {
        self.value = value
    }
}

@MainActor
final class EagleSceneManager: ObservableObject {
    static let shared = EagleSceneManager()

    @Published private(set) var customScenes: [EagleScene] = []
    @Published private(set) var activeSceneID: UUID?
    @Published private(set) var activeTransientScene: EagleScene?
    @Published private(set) var isApplying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastRun: EagleSceneRunReport?
    @Published private(set) var pendingScene: EagleScene?
    @Published var notice: EagleNotice?

    private let fm = FileManager.default
    private let fileURL: URL
    private let lastRunURL: URL
    private let pendingSceneURL: URL
    private let activeKey = "eagle.scenes.active"

    private init() {
        let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Eagle", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("Scenes.plist")
        lastRunURL = directory.appendingPathComponent("LastSceneRun.plist")
        pendingSceneURL = directory.appendingPathComponent("PendingScene.plist")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? PropertyListDecoder().decode([EagleScene].self, from: data) {
            customScenes = decoded.filter { !$0.isBuiltIn }
        }
        if let data = try? Data(contentsOf: lastRunURL) {
            lastRun = try? PropertyListDecoder().decode(EagleSceneRunReport.self, from: data)
        }
        if let data = try? Data(contentsOf: pendingSceneURL) {
            pendingScene = try? PropertyListDecoder().decode(EagleScene.self, from: data)
        }
        if let raw = UserDefaults.standard.string(forKey: activeKey) {
            activeSceneID = UUID(uuidString: raw)
        }
    }

    var allScenes: [EagleScene] { EagleScene.builtIns + customScenes }

    var activeScene: EagleScene? {
        allScenes.first { $0.id == activeSceneID }
            ?? (activeTransientScene?.id == activeSceneID ? activeTransientScene : nil)
    }

    var hasPendingShortcut: Bool {
        guard EagleFeaturePolicy.allows(.scenes) else { return false }
        return UserDefaults.standard.string(forKey: EagleSceneShortcutBridge.pendingSceneKey) != nil ||
            UserDefaults.standard.bool(forKey: EagleSceneShortcutBridge.pendingMomentKey)
    }

    var hasPendingPreparation: Bool {
        pendingScene != nil
    }

    func save(_ scene: EagleScene) {
        var value = scene
        value.isBuiltIn = false
        if let index = customScenes.firstIndex(where: { $0.id == value.id }) {
            customScenes[index] = value
        } else {
            customScenes.append(value)
        }
        persist()
    }

    func delete(_ scene: EagleScene) {
        guard !scene.isBuiltIn else { return }
        customScenes.removeAll { $0.id == scene.id }
        if activeSceneID == scene.id {
            activeSceneID = nil
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
        persist()
    }

    func applyPendingShortcutIfNeeded() {
        guard !isApplying else { return }
        guard EagleFeaturePolicy.allows(.scenes) else {
            let hadPendingShortcut = UserDefaults.standard.string(
                forKey: EagleSceneShortcutBridge.pendingSceneKey
            ) != nil || UserDefaults.standard.bool(
                forKey: EagleSceneShortcutBridge.pendingMomentKey
            )
            guard hadPendingShortcut else { return }
            UserDefaults.standard.removeObject(forKey: EagleSceneShortcutBridge.pendingSceneKey)
            UserDefaults.standard.removeObject(forKey: EagleSceneShortcutBridge.pendingMomentKey)
            notice = EagleNotice(LaraL10n.text(
                en: "Scenes require the Advanced or Laboratory feature channel. Nothing was applied.",
                es: "Escenas requiere el canal Avanzado o Laboratorio. No se aplicó ningún cambio."
            ))
            return
        }
        if pendingScene != nil {
            resumePendingIfReady()
            if isApplying || pendingScene != nil { return }
        }
        let scene: EagleScene
        if UserDefaults.standard.bool(forKey: EagleSceneShortcutBridge.pendingMomentKey) {
            scene = EagleMomentEngine.suggestion().scene
        } else if let raw = UserDefaults.standard.string(
                    forKey: EagleSceneShortcutBridge.pendingSceneKey
                  ),
                  let id = UUID(uuidString: raw),
                  let saved = allScenes.first(where: { $0.id == id }) {
            scene = saved
        } else {
            return
        }
        UserDefaults.standard.removeObject(forKey: EagleSceneShortcutBridge.pendingSceneKey)
        UserDefaults.standard.removeObject(forKey: EagleSceneShortcutBridge.pendingMomentKey)
        apply(scene)
    }

    func resumePendingIfReady() {
        guard EagleFeaturePolicy.allows(.scenes) else { return }
        guard let pendingScene, !isApplying else { return }
        guard hasRequiredAccess(for: pendingScene) else { return }
        apply(pendingScene)
    }

    func apply(_ scene: EagleScene) {
        guard EagleFeaturePolicy.allows(.scenes) else {
            notice = EagleNotice(LaraL10n.text(
                en: "Scenes are unavailable on the Stable channel. Choose Advanced in Compatibility first.",
                es: "Escenas no está disponible en el canal Estable. Elige Avanzado en Compatibilidad primero."
            ))
            return
        }
        guard !isApplying, !CompleteStyleManager.shared.isWorking else { return }
        let wallpaperPack = scene.wallpaper ? scene.wallpaperPack : nil
        let passcodePack = scene.passcode ? scene.passcodePack : nil
        let cardPack = scene.card ? scene.cardPack : nil
        let requestedComponents = scene.requestedComponents
        guard !requestedComponents.isEmpty else {
            notice = EagleNotice(LaraL10n.text(
                en: "This Scene does not contain any changes.",
                es: "Esta Scene no contiene cambios."
            ))
            return
        }

        guard hasRequiredAccess(for: scene) else {
            queuePending(scene, components: requestedComponents)
            notice = EagleNotice(LaraL10n.text(
                en: "This Scene is saved as pending. Prepare Eagle once and it will continue in order from the first component.",
                es: "Esta Scene quedó pendiente. Prepara Eagle una vez y continuará en orden desde el primer componente."
            ))
            return
        }

        let changesLiveConfiguration = scene.dockCapacity != nil ||
            !scene.iconThemeNames.isEmpty || scene.iconShapeRaw != nil
        if changesLiveConfiguration {
            if scene.selectedPartCount > 0 {
                EagleGuardianTransactionContext.shared.markLiveChange()
            } else {
                do {
                    try EagleGuardianStore.shared.protectLiveChange(named: scene.localizedName)
                } catch {
                    notice = EagleNotice(LaraL10n.text(
                        en: "Guardian could not protect the current Home Screen state, so this Scene was not applied.",
                        es: "Guardian no pudo proteger el estado actual de inicio, así que no aplicó esta Scene."
                    ))
                    return
                }
            }
        }

        isApplying = true
        progress = 0
        clearPendingScene()
        let startedAt = Date()
        lastRun = EagleSceneRunReport(
            id: UUID(),
            sceneID: scene.id,
            sceneName: scene.localizedName,
            startedAt: startedAt,
            finishedAt: nil,
            results: []
        )
        persistLastRun()

        Task {
            var results: [EagleSceneComponentResult] = []

            let hasValidStylePart = wallpaperPack != nil || passcodePack != nil || cardPack != nil
            if hasValidStylePart {
                CompleteStyleManager.shared.apply(selection: CompleteStyleSelection(
                    title: scene.localizedName,
                    wallpaperPack: wallpaperPack,
                    passcodePack: passcodePack,
                    cardPack: cardPack
                ))
                while CompleteStyleManager.shared.isWorking {
                    let styleWeight = Double(scene.selectedPartCount) / Double(requestedComponents.count)
                    progress = max(progress, CompleteStyleManager.shared.progress * styleWeight)
                    try? await Task.sleep(nanoseconds: 180_000_000)
                }
            }

            let completedStyleComponents = hasValidStylePart
                ? (CompleteStyleManager.shared.lastResult?.components ?? [])
                : []
            let styleResults = Dictionary(
                uniqueKeysWithValues: completedStyleComponents.map {
                    (sceneComponent(for: $0.component), EagleSceneComponentResult(
                        component: sceneComponent(for: $0.component),
                        state: sceneState(for: $0.state),
                        detail: $0.detail
                    ))
                }
            )
            for component in [EagleSceneComponent.wallpaper, .passcode, .card]
                where requestedComponents.contains(component) {
                if let value = styleResults[component] {
                    results.append(value)
                } else {
                    results.append(.init(
                        component: component,
                        state: .failed,
                        detail: LaraL10n.text(
                            en: "The referenced Style pack is unavailable; this component was not applied.",
                            es: "El paquete de Estilo referenciado no está disponible; este componente no se aplicó."
                        )
                    ))
                }
                updateProgress(results.count, total: requestedComponents.count)
            }

            if scene.dockCapacity != nil || !scene.iconThemeNames.isEmpty || scene.iconShapeRaw != nil {
                let liveResults = await EagleLiveConfigurationController.shared.applyForScene(
                    dockCapacity: scene.dockCapacity,
                    iconThemeNames: scene.iconThemeNames,
                    iconShapeRaw: scene.iconShapeRaw,
                    applyIcons: !scene.iconThemeNames.isEmpty || scene.iconShapeRaw != nil
                )
                results.append(contentsOf: liveResults)
                updateProgress(results.count, total: requestedComponents.count)
            }

            if let islandAura = scene.islandAura {
                results.append(await EagleSceneAuraExecutor.shared.apply(islandAura, to: .island))
                updateProgress(results.count, total: requestedComponents.count)
            }
            if let dockAura = scene.dockAura {
                results.append(await EagleSceneAuraExecutor.shared.apply(dockAura, to: .dock))
                updateProgress(results.count, total: requestedComponents.count)
            }

            let remainsPending = results.contains { $0.state == .pending }
            lastRun = EagleSceneRunReport(
                id: lastRun?.id ?? UUID(),
                sceneID: scene.id,
                sceneName: scene.localizedName,
                startedAt: startedAt,
                finishedAt: remainsPending ? nil : Date(),
                results: results
            )
            if remainsPending {
                persistPendingScene(scene)
            } else {
                clearPendingScene()
            }
            persistLastRun()

            if lastRun?.hasAppliedChanges == true {
                activeSceneID = scene.id
                activeTransientScene = allScenes.contains(where: { $0.id == scene.id }) ? nil : scene
                UserDefaults.standard.set(scene.id.uuidString, forKey: activeKey)
            }
            progress = 1
            isApplying = false
            notice = EagleNotice(runSummary(for: scene, results: results))
            EagleGuardianStore.shared.refresh()
        }
    }

    private func hasRequiredAccess(for scene: EagleScene) -> Bool {
        if scene.selectedPartCount > 0, !laramgr.shared.sbxready { return false }
        let needsProtectedLiveAccess = scene.dockCapacity != nil ||
            !scene.iconThemeNames.isEmpty || scene.iconShapeRaw != nil ||
            scene.islandAura != nil || scene.dockAura != nil
        if needsProtectedLiveAccess, !laramgr.shared.dsready { return false }
        return true
    }

    private func queuePending(_ scene: EagleScene, components: [EagleSceneComponent]) {
        persistPendingScene(scene)
        lastRun = EagleSceneRunReport(
            id: UUID(),
            sceneID: scene.id,
            sceneName: scene.localizedName,
            startedAt: Date(),
            finishedAt: nil,
            results: components.map {
                EagleSceneComponentResult(
                    component: $0,
                    state: .pending,
                    detail: LaraL10n.text(
                        en: "Waiting for one explicit Prepare attempt.",
                        es: "Esperando un intento explícito de Preparar."
                    )
                )
            }
        )
        persistLastRun()
    }

    private func persistPendingScene(_ scene: EagleScene) {
        pendingScene = scene
        if let data = try? PropertyListEncoder().encode(scene) {
            try? data.write(to: pendingSceneURL, options: .atomic)
        }
    }

    private func clearPendingScene() {
        pendingScene = nil
        try? fm.removeItem(at: pendingSceneURL)
    }

    private func persistLastRun() {
        guard let lastRun,
              let data = try? PropertyListEncoder().encode(lastRun) else { return }
        try? data.write(to: lastRunURL, options: .atomic)
    }

    private func sceneComponent(for component: CompleteStyleComponent) -> EagleSceneComponent {
        switch component {
        case .wallpaper: return .wallpaper
        case .passcode: return .passcode
        case .card: return .card
        }
    }

    private func sceneState(for state: CompleteStyleResultState) -> EagleSceneResultState {
        switch state {
        case .applied: return .applied
        case .skipped: return .skipped
        case .failed: return .failed
        }
    }

    private func updateProgress(_ completed: Int, total: Int) {
        progress = Double(min(completed, total)) / Double(max(total, 1))
    }

    private func runSummary(
        for scene: EagleScene,
        results: [EagleSceneComponentResult]
    ) -> String {
        let applied = results.filter { $0.state == .applied }.count
        let skipped = results.filter { $0.state == .skipped }.count
        let failed = results.filter { $0.state == .failed }.count
        let pending = results.filter { $0.state == .pending }.count
        return LaraL10n.text(
            en: "\(scene.localizedName): \(applied) applied, \(skipped) skipped, \(failed) failed, \(pending) pending. Review the component report below.",
            es: "\(scene.localizedName): \(applied) aplicado(s), \(skipped) omitido(s), \(failed) fallido(s), \(pending) pendiente(s). Revisa el informe por componente."
        )
    }

    private func persist() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(customScenes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

struct EagleNotice: Identifiable {
    let id = UUID()
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

// MARK: - Capsules

enum EagleCapsuleError: LocalizedError {
    case tooLarge
    case unreadable
    case wrongType
    case integrity
    case invalidScene

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return LaraL10n.text(en: "This Capsule is larger than the safe limit.", es: "Esta Capsule supera el límite seguro.")
        case .unreadable:
            return LaraL10n.text(en: "This file is not a readable Eagle Capsule.", es: "Este archivo no es una Eagle Capsule legible.")
        case .wrongType:
            return LaraL10n.text(en: "This Capsule type or version is not supported.", es: "Este tipo o versión de Capsule no es compatible.")
        case .integrity:
            return LaraL10n.text(en: "The Capsule checksum does not match. Import was blocked.", es: "El checksum de la Capsule no coincide. Se bloqueó la importación.")
        case .invalidScene:
            return LaraL10n.text(en: "The Capsule contains an invalid Scene recipe.", es: "La Capsule contiene una receta de Scene no válida.")
        }
    }
}

private struct EagleCapsulePayload: Codable {
    let formatVersion: Int
    let capsuleID: UUID
    let name: String
    let creator: String
    let createdAt: Date
    let scene: EagleScene
}

private struct EagleCapsuleEnvelope: Codable {
    let type: String
    let formatVersion: Int
    let payload: Data
    let checksum: String
}

enum EagleCapsuleCodec {
    static let maximumSize = 512 * 1024

    static func encode(_ scene: EagleScene) throws -> Data {
        let payload = EagleCapsulePayload(
            formatVersion: 1,
            capsuleID: UUID(),
            name: scene.localizedName,
            creator: "Eagle",
            createdAt: Date(),
            scene: scene
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payloadData = try encoder.encode(payload)
        let envelope = EagleCapsuleEnvelope(
            type: "com.eagle.scene",
            formatVersion: 1,
            payload: payloadData,
            checksum: EagleIntegrity.digest(payloadData)
        )
        let data = try encoder.encode(envelope)
        guard data.count <= maximumSize else { throw EagleCapsuleError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> EagleScene {
        guard data.count <= maximumSize else { throw EagleCapsuleError.tooLarge }
        guard let envelope = try? PropertyListDecoder().decode(EagleCapsuleEnvelope.self, from: data) else {
            throw EagleCapsuleError.unreadable
        }
        guard envelope.type == "com.eagle.scene", envelope.formatVersion == 1 else {
            throw EagleCapsuleError.wrongType
        }
        guard EagleIntegrity.digest(envelope.payload) == envelope.checksum else {
            throw EagleCapsuleError.integrity
        }
        guard let payload = try? PropertyListDecoder().decode(EagleCapsulePayload.self, from: envelope.payload),
              payload.formatVersion == 1 else {
            throw EagleCapsuleError.unreadable
        }
        let scene = payload.scene
        let availablePackIDs = Set(CompleteStylePack.all.map(\.id))
        let referencedPackIDs = [
            scene.packID,
            scene.wallpaperPackID,
            scene.passcodePackID,
            scene.cardPackID
        ].compactMap { $0 }
        guard scene.name.count <= 40,
              !scene.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              referencedPackIDs.allSatisfy({ availablePackIDs.contains($0) }),
              scene.dockCapacity.map({ (4...6).contains($0) }) ?? true,
              scene.iconThemeNames.count <= 8,
              scene.iconThemeNames.allSatisfy({ $0.count <= 80 && !$0.contains("/") && !$0.contains("\\") }),
              scene.iconShapeRaw.map({ EagleIconShape(rawValue: $0) != nil }) ?? true,
              scene.dockAura?.mode != .tint else {
            throw EagleCapsuleError.invalidScene
        }
        return scene.importedCopy()
    }
}

extension UTType {
    static let eagleCapsule = UTType(
        exportedAs: "com.leonardobaptiste.eagle.scene-capsule",
        conformingTo: .data
    )
}

struct EagleCapsuleDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.eagleCapsule, .data] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw EagleCapsuleError.unreadable
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - System hub

struct EagleSystemView: View {
    @ObservedObject private var guardian = EagleGuardianStore.shared
    @ObservedObject private var scenes = EagleSceneManager.shared
    @AppStorage(EagleReleaseChannel.storageKey)
    private var channelRaw = EagleReleaseChannel.stable.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scenesAllowed: Bool {
        EagleFeaturePolicy.allows(
            .scenes,
            channel: EagleFeaturePolicy.channel(from: channelRaw)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                systemHero

                NavigationLink(destination: EagleGuardianView()) {
                    systemRow(
                        title: "Guardian",
                        subtitle: guardian.checkpoints.isEmpty
                            ? LaraL10n.text(en: "Verified recovery begins with your next change", es: "La recuperación verificada comienza con tu próximo cambio")
                            : LaraL10n.text(en: "\(guardian.checkpoints.count) verified recovery points", es: "\(guardian.checkpoints.count) puntos de recuperación verificados"),
                        symbol: "checkmark.shield.fill",
                        color: .green
                    )
                }

                if scenesAllowed {
                    NavigationLink(destination: EagleScenesView()) {
                        systemRow(
                            title: LaraL10n.text(en: "Scenes", es: "Escenas"),
                            subtitle: scenes.activeScene.map {
                                LaraL10n.text(en: "\($0.localizedName) is active", es: "\($0.localizedName) está activa")
                            } ?? LaraL10n.text(en: "Change the whole mood in one action", es: "Cambia todo el ambiente en una acción"),
                            symbol: "rectangle.3.group.fill",
                            color: .indigo
                        )
                    }

                    NavigationLink(destination: EagleCapsulesView()) {
                        systemRow(
                            title: "Capsules",
                            subtitle: LaraL10n.text(en: "Share safe, checksum-verified Scenes", es: "Comparte Escenas seguras y verificadas"),
                            symbol: "shippingbox.fill",
                            color: .orange
                        )
                    }
                } else {
                    NavigationLink(destination: EagleCompatibilityCenterView()) {
                        systemRow(
                            title: LaraL10n.text(en: "Scenes require Advanced", es: "Escenas requiere Avanzado"),
                            subtitle: LaraL10n.text(
                                en: "Open Compatibility to choose the Advanced channel",
                                es: "Abre Compatibilidad para elegir el canal Avanzado"
                            ),
                            symbol: "lock.shield.fill",
                            color: .secondary
                        )
                    }
                    .accessibilityHint(LaraL10n.text(
                        en: "Opens feature channel settings",
                        es: "Abre los ajustes del canal de funciones"
                    ))
                }

                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "lock.doc.fill")
                        .foregroundStyle(.blue)
                    Text(LaraL10n.text(
                        en: scenesAllowed
                            ? "One engine connects all three: every Scene uses Guardian, and every Capsule can contain only a validated Scene recipe."
                            : "Guardian remains available on Stable. Scenes and Capsules appear only when the Advanced or Laboratory channel is selected.",
                        es: scenesAllowed
                            ? "Un solo motor conecta las tres: cada Escena usa Guardian y cada Capsule solo puede contener una receta validada."
                            : "Guardian permanece disponible en Estable. Escenas y Capsules aparecen solo al elegir Avanzado o Laboratorio."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
        .eagleScreenBackdrop()
        .navigationTitle("Eagle System")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guardian.refresh()
        }
    }

    private var systemHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: "bird.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                Spacer()
                Label(
                    guardian.invalidCheckpointCount == 0
                        ? LaraL10n.text(en: "Verified", es: "Verificado")
                        : LaraL10n.text(en: "Review", es: "Revisar"),
                    systemImage: guardian.invalidCheckpointCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(LaraL10n.text(en: "One tap. One safe way back.", es: "Un toque. Una forma segura de volver."))
                    .font(.title2.bold())
                Text(LaraL10n.text(
                    en: "Scenes for speed, Guardian for confidence, Capsules for sharing.",
                    es: "Scenes para velocidad, Guardian para confianza y Capsules para compartir."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.18, blue: 0.42), .indigo, Color(red: 0.36, green: 0.18, blue: 0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                heroSheen
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // A soft light that drifts slowly across the hero so the header feels alive;
    // it holds still when Reduce Motion is on.
    private var heroSheen: some View {
        EagleAmbientTimeline(paused: reduceMotion) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let a = reduceMotion
                ? 0.6
                : (seconds / 9).truncatingRemainder(dividingBy: 1) * 2 * Double.pi

            Circle()
                .fill(Color.white.opacity(0.13))
                .frame(width: 190, height: 190)
                .blur(radius: 55)
                .offset(x: CGFloat(cos(a)) * 120, y: CGFloat(sin(a)) * 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func systemRow(title: String, subtitle: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }
}

// MARK: - Guardian UI

struct EagleGuardianView: View {
    @ObservedObject private var guardian = EagleGuardianStore.shared
    @ObservedObject private var styleManager = CompleteStyleManager.shared
    @State private var restoreCandidate: EagleGuardianCheckpoint?
    @State private var deleteCandidate: EagleGuardianCheckpoint?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                guardianHero

                if let pending = guardian.pendingCheckpoint {
                    pendingCard(pending)
                }

                if guardian.checkpoints.isEmpty {
                    emptyTimeline
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LaraL10n.text(en: "Recovery timeline", es: "Línea de recuperación"))
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(guardian.checkpoints) { checkpoint in
                            checkpointRow(checkpoint)
                        }
                    }
                }

                guardianRules
            }
            .padding(20)
        }
        .eagleScreenBackdrop()
        .navigationTitle("Guardian")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { guardian.refresh() }
        .refreshable { guardian.refresh() }
        .confirmationDialog(
            LaraL10n.text(en: "Restore this recovery point?", es: "¿Restaurar este punto?"),
            isPresented: Binding(
                get: { restoreCandidate != nil },
                set: { if !$0 { restoreCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LaraL10n.text(en: "Restore verified state", es: "Restaurar estado verificado")) {
                if let restoreCandidate {
                    styleManager.restoreGuardianCheckpoint(restoreCandidate)
                }
                self.restoreCandidate = nil
            }
            Button(LaraL10n.text(en: "Cancel", es: "Cancelar"), role: .cancel) {
                restoreCandidate = nil
            }
        } message: {
            Text(LaraL10n.text(
                en: "Guardian will create a new recovery point first, verify every stored file, and then restore.",
                es: "Guardian creará primero un punto nuevo, verificará cada archivo guardado y luego restaurará."
            ))
        }
        .confirmationDialog(
            LaraL10n.text(en: "Delete recovery point?", es: "¿Eliminar punto de recuperación?"),
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LaraL10n.text(en: "Delete", es: "Eliminar"), role: .destructive) {
                if let deleteCandidate { guardian.delete(deleteCandidate) }
                self.deleteCandidate = nil
            }
            Button(LaraL10n.text(en: "Cancel", es: "Cancelar"), role: .cancel) {
                deleteCandidate = nil
            }
        }
        .eagleNotice(item: $styleManager.lastResult, title: "Eagle Styles") { $0.message }
        .overlay {
            if styleManager.isWorking {
                EagleBlockingProgress(
                    title: styleManager.stage,
                    progress: styleManager.progress
                )
            }
        }
    }

    private var guardianHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: guardian.invalidCheckpointCount == 0
                      ? "checkmark.shield.fill"
                      : "exclamationmark.shield.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(guardian.invalidCheckpointCount == 0 ? .green : .orange)
                Spacer()
                Text(guardian.invalidCheckpointCount == 0 ? "SHA-256" : "BLOCKED")
                    .font(.caption2.monospaced().bold())
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .background(.primary.opacity(0.06), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(guardian.statusTitle).font(.title2.bold())
                Text(guardian.invalidCheckpointCount == 0
                     ? LaraL10n.text(
                        en: "Every visible recovery point passed payload and per-file verification.",
                        es: "Cada punto visible pasó la verificación del paquete y de cada archivo."
                     )
                     : LaraL10n.text(
                        en: "\(guardian.invalidCheckpointCount) damaged point(s) are hidden and can never be restored.",
                        es: "\(guardian.invalidCheckpointCount) punto(s) dañados están ocultos y nunca se podrán restaurar."
                     ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                guardianMetric(value: "\(guardian.checkpoints.count)", label: LaraL10n.text(en: "Points", es: "Puntos"))
                guardianMetric(value: "12", label: LaraL10n.text(en: "Rolling limit", es: "Límite"))
                guardianMetric(value: "2×", label: LaraL10n.text(en: "Verified", es: "Verificado"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func guardianMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pendingCard(_ checkpoint: EagleGuardianCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                LaraL10n.text(en: "Interrupted change detected", es: "Se detectó un cambio interrumpido"),
                systemImage: "bolt.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text(LaraL10n.text(
                en: "Eagle found a protected state from an operation that did not finish. You can recover it or discard it after checking your phone.",
                es: "Eagle encontró un estado protegido de una operación que no terminó. Puedes recuperarlo o descartarlo después de revisar tu iPhone."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button(LaraL10n.text(en: "Recover", es: "Recuperar")) {
                    restoreCandidate = checkpoint
                }
                .buttonStyle(.borderedProminent)
                // The contrasting colour on the black/white fill, grey while disabled.
                .eagleProminentLabel()
                Button(LaraL10n.text(en: "Discard", es: "Descartar"), role: .destructive) {
                    guardian.discardPendingRecovery()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(17)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyTimeline: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(LaraL10n.text(en: "Your timeline starts automatically", es: "Tu línea comienza automáticamente"))
                .font(.headline)
            Text(LaraL10n.text(
                en: "Apply a Style or Scene. Eagle will protect the files it is about to touch—there is no backup button to remember.",
                es: "Aplica un Estilo o Scene. Eagle protegerá los archivos que va a tocar; no hay un botón de respaldo que recordar."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func checkpointRow(_ checkpoint: EagleGuardianCheckpoint) -> some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(.green)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.green.opacity(0.22), lineWidth: 6))
                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(width: 2, height: 62)
            }
            .padding(.top, 7)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(checkpoint.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(checkpoint.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(checkpoint.componentTitles)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(checkpoint.manifest.count)", systemImage: "doc.fill")
                    Label(ByteCountFormatter.string(fromByteCount: Int64(checkpoint.verifiedByteCount), countStyle: .file), systemImage: "externaldrive.fill")
                    Label(LaraL10n.text(en: "Verified", es: "Verificado"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .font(.caption2)

                HStack {
                    Button(LaraL10n.text(en: "Restore", es: "Restaurar")) {
                        restoreCandidate = checkpoint
                    }
                    .buttonStyle(.bordered)
                    .disabled(styleManager.isWorking)

                    Spacer()
                    Button(role: .destructive) {
                        deleteCandidate = checkpoint
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(15)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
    }

    private var guardianRules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LaraL10n.text(en: "Guardian rules", es: "Reglas de Guardian"), systemImage: "lock.fill")
                .font(.headline)
            Text(LaraL10n.text(
                en: "• A new restore never starts until the current files are protected.\n• A damaged checksum is blocked, not ignored.\n• Only Eagle-owned wallpaper additions are removed.\n• The newest 12 points are kept automatically.",
                es: "• Una restauración no comienza hasta proteger los archivos actuales.\n• Un checksum dañado se bloquea, no se ignora.\n• Solo se retiran fondos agregados por Eagle.\n• Se conservan automáticamente los 12 puntos más recientes."
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Scenes UI

struct EagleScenesView: View {
    @ObservedObject private var manager = EagleSceneManager.shared
    @State private var showingEditor = false
    @State private var previewScene: EagleScene?
    @State private var moment = EagleMomentEngine.suggestion()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sceneHero

                if manager.hasPendingPreparation {
                    LaraAccessView(compact: true) {
                        manager.resumePendingIfReady()
                    }
                }

                if let report = manager.lastRun {
                    sceneRunReport(report)
                }

                momentCard

                Text(LaraL10n.text(en: "Ready-made Scenes", es: "Scenes listas"))
                    .font(.title3.bold())

                ForEach(EagleScene.builtIns) { scene in
                    sceneCard(scene)
                }

                HStack {
                    Text(LaraL10n.text(en: "Your Scenes", es: "Tus Scenes"))
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        showingEditor = true
                    } label: {
                        Label(LaraL10n.text(en: "New", es: "Nueva"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if manager.customScenes.isEmpty {
                    Button {
                        showingEditor = true
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.title)
                            Text(LaraL10n.text(en: "Create your first Scene", es: "Crea tu primera Scene"))
                                .font(.headline)
                            Text(LaraL10n.text(
                                en: "Choose one look, the parts you want, and your Dock. Eagle handles the order and recovery.",
                                es: "Elige un estilo, las partes que quieres y tu Dock. Eagle controla el orden y la recuperación."
                            ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(25)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    }
                    .buttonStyle(EaglePressableStyle(kind: .card))
                } else {
                    ForEach(manager.customScenes) { scene in
                        sceneCard(scene)
                            .contextMenu {
                                Button(role: .destructive) { manager.delete(scene) } label: {
                                    Label(LaraL10n.text(en: "Delete Scene", es: "Eliminar Scene"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(20)
        }
        .eagleScreenBackdrop()
        .navigationTitle("Scenes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            moment = EagleMomentEngine.suggestion()
            manager.resumePendingIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            moment = EagleMomentEngine.suggestion()
        }
        .sheet(isPresented: $showingEditor) {
            EagleSceneEditorView()
        }
        .sheet(item: $previewScene) { scene in
            CompleteStyleLivePreviewView(
                title: scene.localizedName,
                wallpaperPack: scene.wallpaper ? scene.wallpaperPack : nil,
                passcodePack: scene.passcode ? scene.passcodePack : nil,
                cardPack: scene.card ? scene.cardPack : nil
            ) {
                manager.apply(scene)
            }
        }
        .eagleNotice(item: $manager.notice, title: "Scenes") { $0.message }
        .overlay {
            if manager.isApplying {
                EagleBlockingProgress(
                    title: LaraL10n.text(en: "Applying Scene safely", es: "Aplicando Scene de forma segura"),
                    progress: manager.progress
                )
            }
        }
    }

    private func sceneRunReport(_ report: EagleSceneRunReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    report.isPending
                        ? LaraL10n.text(en: "Scene pending", es: "Scene pendiente")
                        : LaraL10n.text(en: "Last Scene result", es: "Último resultado de Scene"),
                    systemImage: report.isPending ? "clock.badge.exclamationmark" : "checklist"
                )
                .font(.headline)
                Spacer()
                Text(report.sceneName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ForEach(report.results) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.state.systemImage)
                        .foregroundStyle(item.state.color)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.component.localizedName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(item.state.localizedName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.state.color)
                        }
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var sceneHero: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: manager.activeScene?.symbol ?? "rectangle.3.group.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Spacer()
                Text(manager.activeScene == nil
                     ? LaraL10n.text(en: "ONE TAP", es: "UN TOQUE")
                     : LaraL10n.text(en: "ACTIVE", es: "ACTIVA"))
                    .font(.caption.monospaced().bold())
            }
            Text(manager.activeScene?.localizedName ?? LaraL10n.text(en: "Your phone, by moment", es: "Tu iPhone, según el momento"))
                .font(.title2.bold())
            Text(manager.activeScene?.summary ?? LaraL10n.text(
                en: "A Scene coordinates Style, Dock, and optional icons as one protected transaction.",
                es: "Una Scene coordina Estilo, Dock e iconos opcionales como una transacción protegida."
            ))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private var momentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: moment.scene.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(moment.accent)
                    .frame(width: 46, height: 46)
                    .background(moment.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Eagle Moment")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(moment.accent)
                    Text(moment.scene.localizedName)
                        .font(.title3.bold())
                    Text(moment.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(moment.accent)
            }

            Text(moment.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                ForEach(moment.factors, id: \.self) { factor in
                    Text(factor)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(moment.accent.opacity(0.09), in: Capsule())
                }
            }

            HStack(spacing: 9) {
                Button {
                    previewScene = moment.scene
                } label: {
                    Label(LaraL10n.text(en: "Preview", es: "Vista previa"), systemImage: "eye.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    manager.apply(moment.scene)
                } label: {
                    Label(LaraL10n.text(en: "Use Moment", es: "Usar Moment"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(EagleVisualTheme.actionFill)
                .eagleProminentLabel()

                Menu {
                    Button {
                        let saved = moment.scene.importedCopy()
                        manager.save(saved)
                        manager.notice = EagleNotice(LaraL10n.text(
                            en: "\(saved.localizedName) was saved to Your Scenes.",
                            es: "\(saved.localizedName) se guardó en Tus Scenes."
                        ))
                    } label: {
                        Label(LaraL10n.text(en: "Save as Scene", es: "Guardar como Scene"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
            }
            .disabled(manager.isApplying)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(moment.accent.opacity(0.18), lineWidth: 1)
        }
    }

    private func sceneCard(_ scene: EagleScene) -> some View {
        let pack = scene.pack
        return HStack(spacing: 14) {
            ZStack {
                LinearGradient(
                    colors: [pack?.primary.color ?? .indigo, pack?.tertiary.color ?? .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: scene.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scene.localizedName).font(.headline)
                    if manager.activeSceneID == scene.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text(scene.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            HStack(spacing: 7) {
                Button {
                    previewScene = scene
                } label: {
                    Image(systemName: "eye.fill")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(LaraL10n.text(en: "Preview Scene", es: "Vista previa de Scene"))

                Button(LaraL10n.text(en: "Apply", es: "Aplicar")) {
                    manager.apply(scene)
                }
                .buttonStyle(EagleApplyButtonStyle(busy: manager.isApplying, compact: true))
            }
            .disabled(manager.isApplying)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private enum EagleSceneAuraColorPreset: String, CaseIterable, Identifiable {
    case cyan
    case violet
    case pink
    case amber

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .cyan: return LaraL10n.text(en: "Electric cyan", es: "Cian eléctrico")
        case .violet: return LaraL10n.text(en: "Deep violet", es: "Violeta intenso")
        case .pink: return LaraL10n.text(en: "Neon pink", es: "Rosa neón")
        case .amber: return LaraL10n.text(en: "Warm amber", es: "Ámbar cálido")
        }
    }

    var color: Color {
        let rgb = components
        return Color(
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }

    var components: (red: Int, green: Int, blue: Int) {
        switch self {
        case .cyan: return (26, 199, 255)
        case .violet: return (158, 64, 255)
        case .pink: return (255, 54, 174)
        case .amber: return (255, 174, 46)
        }
    }

    func profile(mode: EagleSceneAuraMode) -> EagleSceneAuraProfile {
        let rgb = components
        return EagleSceneAuraProfile(
            mode: mode,
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )
    }
}

private struct EagleSceneEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iconManager = IconThemeManager.shared
    @AppStorage(EagleReleaseChannel.storageKey)
    private var channelRaw = EagleReleaseChannel.stable.rawValue
    @State private var name = ""
    @State private var symbol = "sparkles"
    @State private var packID = CompleteStylePack.all.first?.id ?? "obsidian"
    @State private var fusion = false
    @State private var wallpaperPackID = CompleteStylePack.all.first?.id ?? "obsidian"
    @State private var passcodePackID = CompleteStylePack.all.first?.id ?? "obsidian"
    @State private var cardPackID = CompleteStylePack.all.first?.id ?? "obsidian"
    @State private var wallpaper = true
    @State private var passcode = true
    @State private var card = true
    @State private var dockCapacity = 5
    @State private var includeCurrentIcons = false
    @State private var includeIslandAura = false
    @State private var islandAuraMode = EagleSceneAuraMode.glow
    @State private var islandAuraColor = EagleSceneAuraColorPreset.cyan
    @State private var includeDockAura = false
    @State private var dockAuraMode = EagleSceneAuraMode.glow
    @State private var dockAuraColor = EagleSceneAuraColorPreset.violet

    private var channel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: channelRaw)
    }

    private var islandAuraModes: [EagleSceneAuraMode] {
        EagleSceneAuraMode.allCases.filter {
            EagleFeaturePolicy.allowsSceneAura($0, target: .island, channel: channel)
        }
    }

    private var dockAuraModes: [EagleSceneAuraMode] {
        EagleSceneAuraMode.allCases.filter {
            EagleFeaturePolicy.allowsSceneAura($0, target: .dock, channel: channel)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LaraL10n.text(en: "Scene name", es: "Nombre de la Scene"), text: $name)
                        .textInputAutocapitalization(.words)
                    Picker(LaraL10n.text(en: "Look", es: "Estilo"), selection: $packID) {
                        ForEach(CompleteStylePack.all) { pack in
                            Label(pack.localizedName, systemImage: pack.symbol).tag(pack.id)
                        }
                    }
                } header: {
                    Text(LaraL10n.text(en: "Identity", es: "Identidad"))
                }

                Section {
                    Toggle(LaraL10n.text(en: "Wallpaper", es: "Fondo"), isOn: $wallpaper)
                    Toggle(LaraL10n.text(en: "Passcode", es: "Código"), isOn: $passcode)
                    Toggle(LaraL10n.text(en: "Wallet card", es: "Tarjeta de Wallet"), isOn: $card)
                } header: {
                    Text(LaraL10n.text(en: "Style parts", es: "Partes del estilo"))
                } footer: {
                    Text(LaraL10n.text(
                        en: "Unavailable parts are skipped without stopping compatible ones.",
                        es: "Las partes no disponibles se omiten sin detener las compatibles."
                    ))
                }

                Section {
                    Toggle(
                        LaraL10n.text(en: "Mix a different Style for each part", es: "Mezclar un Estilo diferente en cada parte"),
                        isOn: $fusion
                    )

                    if fusion {
                        if wallpaper {
                            Picker(LaraL10n.text(en: "Wallpaper look", es: "Estilo del fondo"), selection: $wallpaperPackID) {
                                ForEach(CompleteStylePack.all) { pack in
                                    Text(pack.localizedName).tag(pack.id)
                                }
                            }
                        }
                        if passcode {
                            Picker(LaraL10n.text(en: "Passcode look", es: "Estilo del código"), selection: $passcodePackID) {
                                ForEach(CompleteStylePack.all) { pack in
                                    Text(pack.localizedName).tag(pack.id)
                                }
                            }
                        }
                        if card {
                            Picker(LaraL10n.text(en: "Card look", es: "Estilo de tarjeta"), selection: $cardPackID) {
                                ForEach(CompleteStylePack.all) { pack in
                                    Text(pack.localizedName).tag(pack.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Scene Fusion")
                } footer: {
                    Text(fusion
                         ? LaraL10n.text(
                            en: "Fusion creates one protected Scene from several Eagle Styles.",
                            es: "Fusion crea una Scene protegida desde varios Estilos de Eagle."
                         )
                         : LaraL10n.text(
                            en: "Optional. Leave this off to keep one consistent look.",
                            es: "Opcional. Déjalo apagado para conservar un solo estilo."
                         ))
                }

                Section {
                    Picker("Dock", selection: $dockCapacity) {
                        Text("4").tag(4)
                        Text("5").tag(5)
                        Text("6").tag(6)
                    }
                    .pickerStyle(.segmented)
                    Toggle(
                        LaraL10n.text(en: "Include current icon setup", es: "Incluir configuración actual de iconos"),
                        isOn: $includeCurrentIcons
                    )
                    .disabled(iconManager.selectedThemeNames.isEmpty && iconManager.selectedIconShape == .original)
                } header: {
                    Text(LaraL10n.text(en: "Home Screen", es: "Pantalla de inicio"))
                } footer: {
                    Text(LaraL10n.text(
                        en: "Eagle stores theme names, never third-party icon files, inside a Scene.",
                        es: "Eagle guarda nombres de temas, nunca archivos de iconos de terceros, dentro de una Scene."
                    ))
                }

                Section {
                    Toggle("Dynamic Island Aura", isOn: $includeIslandAura)
                    if includeIslandAura {
                        Picker(LaraL10n.text(en: "Island effect", es: "Efecto de Island"), selection: $islandAuraMode) {
                            ForEach(islandAuraModes) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        Picker(LaraL10n.text(en: "Island color", es: "Color de Island"), selection: $islandAuraColor) {
                            ForEach(EagleSceneAuraColorPreset.allCases) { preset in
                                Label(preset.localizedName, systemImage: "circle.fill")
                                    .foregroundStyle(preset.color)
                                    .tag(preset)
                            }
                        }
                    }

                    Toggle("Dock Aura", isOn: $includeDockAura)
                    if includeDockAura {
                        Picker(LaraL10n.text(en: "Dock effect", es: "Efecto del Dock"), selection: $dockAuraMode) {
                            ForEach(dockAuraModes) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        Picker(LaraL10n.text(en: "Dock color", es: "Color del Dock"), selection: $dockAuraColor) {
                            ForEach(EagleSceneAuraColorPreset.allCases) { preset in
                                Label(preset.localizedName, systemImage: "circle.fill")
                                    .foregroundStyle(preset.color)
                                    .tag(preset)
                            }
                        }
                    }
                } header: {
                    Text("Aura profiles")
                } footer: {
                    Text(LaraL10n.text(
                        en: "Island and Dock keep separate modes and RGB colors. Eagle applies them one at a time and never restarts the iPhone automatically.",
                        es: "Island y Dock conservan modos y colores RGB separados. Eagle los aplica uno por uno y nunca reinicia el iPhone automáticamente."
                    ))
                }
            }
            .onChange(of: fusion) { enabled in
                if enabled {
                    wallpaperPackID = packID
                    passcodePackID = packID
                    cardPackID = packID
                }
            }
            .navigationTitle(LaraL10n.text(en: "New Scene", es: "Nueva Scene"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LaraL10n.text(en: "Cancel", es: "Cancelar")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LaraL10n.text(en: "Save", es: "Guardar")) { save() }
                        .disabled(trimmedName.isEmpty || (![wallpaper, passcode, card].contains(true) && dockCapacity == 4 && !includeCurrentIcons))
                }
            }
        }
    }

    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    private func save() {
        let pack = CompleteStylePack.all.first { $0.id == packID }
        let newScene = EagleScene(
            id: UUID(),
            name: trimmedName,
            symbol: pack?.symbol ?? symbol,
            packID: packID,
            wallpaperPackID: fusion && wallpaper ? wallpaperPackID : nil,
            passcodePackID: fusion && passcode ? passcodePackID : nil,
            cardPackID: fusion && card ? cardPackID : nil,
            wallpaper: wallpaper,
            passcode: passcode,
            card: card,
            dockCapacity: dockCapacity,
            iconThemeNames: includeCurrentIcons ? iconManager.selectedThemeNames : [],
            iconShapeRaw: includeCurrentIcons ? iconManager.selectedIconShape.rawValue : nil,
            islandAura: includeIslandAura ? islandAuraColor.profile(mode: islandAuraMode) : nil,
            dockAura: includeDockAura ? dockAuraColor.profile(mode: dockAuraMode) : nil,
            isBuiltIn: false,
            createdAt: Date()
        )
        EagleSceneManager.shared.save(newScene)
        dismiss()
    }
}

// MARK: - Capsules UI

struct EagleCapsulesView: View {
    @ObservedObject private var scenes = EagleSceneManager.shared
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: EagleCapsuleDocument?
    @State private var exportFilename = "Eagle-Scene"
    @State private var notice: EagleNotice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                capsuleHero

                Button {
                    importing = true
                } label: {
                    Label(LaraL10n.text(en: "Import Eagle Capsule", es: "Importar Eagle Capsule"), systemImage: "square.and.arrow.down.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                // The contrasting colour on the black/white fill, grey while disabled.
                .eagleProminentLabel()

                VStack(alignment: .leading, spacing: 5) {
                    Text(LaraL10n.text(en: "Share a Scene", es: "Compartir una Scene"))
                        .font(.title3.bold())
                    Text(LaraL10n.text(
                        en: "The Capsule contains settings only. The recipient chooses when to apply them.",
                        es: "La Capsule solo contiene ajustes. La persona decide cuándo aplicarlos."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(scenes.allScenes) { scene in
                    HStack(spacing: 13) {
                        Image(systemName: scene.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(scene.pack?.secondary.color ?? .indigo)
                            .frame(width: 45, height: 45)
                            .background((scene.pack?.secondary.color ?? .indigo).opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scene.localizedName).font(.headline)
                            Text(scene.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            prepareExport(scene)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                capsuleSafety
            }
            .padding(20)
        }
        .eagleScreenBackdrop()
        .navigationTitle("Capsules")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.eagleCapsule, .data],
            allowsMultipleSelection: false
        ) { result in
            importCapsule(result)
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .eagleCapsule,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                notice = EagleNotice(error.localizedDescription)
            }
            exportDocument = nil
        }
        .eagleNotice(item: $notice, title: "Capsules") { $0.message }
    }

    private var capsuleHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Spacer()
                Text(".EAGLE")
                    .font(.caption.monospaced().bold())
            }
            Text(LaraL10n.text(en: "Share the recipe, not the risk.", es: "Comparte la receta, no el riesgo."))
                .font(.title2.bold())
            Text(LaraL10n.text(
                en: "A Capsule is a tiny, versioned Scene with a SHA-256 checksum. It cannot carry executable code or system paths.",
                es: "Una Capsule es una Scene pequeña y versionada con checksum SHA-256. No puede llevar código ejecutable ni rutas del sistema."
            ))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private var capsuleSafety: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(LaraL10n.text(en: "Import firewall", es: "Firewall de importación"), systemImage: "firewall.fill")
                .font(.headline)
            capsuleRule("512 KB", LaraL10n.text(en: "Hard size limit", es: "Límite rígido"))
            capsuleRule("SHA-256", LaraL10n.text(en: "Payload must match", es: "El paquete debe coincidir"))
            capsuleRule("v1", LaraL10n.text(en: "Known schema only", es: "Solo esquema conocido"))
            capsuleRule("0", LaraL10n.text(en: "Executable files and paths", es: "Ejecutables y rutas"))
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func capsuleRule(_ value: String, _ label: String) -> some View {
        HStack {
            Text(value).font(.subheadline.monospaced().bold())
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func prepareExport(_ scene: EagleScene) {
        do {
            exportDocument = EagleCapsuleDocument(data: try EagleCapsuleCodec.encode(scene))
            let safeName = scene.localizedName
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
            exportFilename = (safeName.isEmpty ? "Eagle-Scene" : safeName) + ".eagle"
            exporting = true
        } catch {
            notice = EagleNotice(error.localizedDescription)
        }
    }

    private func importCapsule(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { throw EagleCapsuleError.unreadable }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw EagleCapsuleError.unreadable }
            guard (values.fileSize ?? 0) <= EagleCapsuleCodec.maximumSize else {
                throw EagleCapsuleError.tooLarge
            }
            let scene = try EagleCapsuleCodec.decode(Data(contentsOf: url, options: .mappedIfSafe))
            scenes.save(scene)
            notice = EagleNotice(LaraL10n.text(
                en: "\(scene.localizedName) was verified and added to Your Scenes. Nothing was applied automatically.",
                es: "\(scene.localizedName) fue verificada y añadida a Tus Scenes. Nada se aplicó automáticamente."
            ))
        } catch {
            notice = EagleNotice(error.localizedDescription)
        }
    }
}

/// Full-screen "working" card while Eagle applies something. Visual only: it shows the same title and
/// progress it is given. Eagle's rainbow activity mark, a monochrome bar (like Prepare's) that glides
/// to each new value, the percentage rolling, and a soft entrance and exit wherever it is shown.
struct EagleBlockingProgress: View {
    let title: String
    let progress: Double

    @Environment(\.colorScheme) private var colorScheme

    private var clamped: Double { max(0, min(progress, 1)) }
    private var percent: Int { Int(clamped * 100) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                EagleRainbowSpinner(size: 26)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: max(6, geometry.size.width * clamped))
                    }
                }
                .frame(width: 200, height: 6)
                .animation(.spring(response: 0.55, dampingFraction: 0.9), value: clamped)
                Text("\(percent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: percent)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.14), radius: 24, y: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(percent)%")
        }
        // Carries its own animation, so it eases in and out even where it is shown without one.
        .transition(.eagleWorking)
    }
}
