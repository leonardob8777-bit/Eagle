import SwiftUI
import UIKit
import Darwin
import Combine

private struct AuraStudioNotice: Identifiable {
    let id = UUID()
    let message: String
    let offersRespring: Bool

    init(message: String, offersRespring: Bool = false) {
        self.message = message
        self.offersRespring = offersRespring
    }
}

typealias AuraStudioDisplayGeometry = EagleAuraStudioDisplayGeometry

@MainActor
extension EagleAuraStudioDisplayGeometry {
    var compactIslandFrame: CGRect {
        compactIslandFrame(readModel: { devicemachine() })
    }

    var dockAuraFrame: CGRect {
        dockAuraFrame(readModel: { devicemachine() })
    }

    static var current: AuraStudioDisplayGeometry {
        EagleAuraStudioDisplayMetrics.current
    }
}

private enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String = "") {
        EagleAuraStudioDiagnosticLog.log(
            stage, detail,
            now: { Date() },
            makeDelivery: { globallogger.log }
        )
    }
}

private typealias AuraStudioApplyGate = EagleAuraStudioApplyGate

private typealias AuraStudioMode = EagleAuraStudioMode

private extension EagleAuraStudioMode {
    var title: String {
        title(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }

    var summary: String {
        summary(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
}

private typealias AuraStudioTarget = EagleAuraStudioTarget

private typealias AuraStudioOperationStep = EagleAuraStudioOperationStep

private extension EagleAuraStudioOperationStep {
    var localizedName: String {
        localizedName(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
}

private typealias AuraStudioOperation = EagleAuraStudioOperation

/// Pure validation for the one-surface native boundary. Keep these rules in
/// Swift as well as Objective-C so a mismatched native result can never update
/// the wrong profile badge or be presented as a successful fallback.
private typealias AuraStudioNativeContract = EagleAuraStudioNativeContract

struct AuraStudioView: View {
    private enum Flag {
        static let island: UInt32 = 1 << 0
        static let screen: UInt32 = 1 << 1
        static let battery: UInt32 = 1 << 2
        // Bits 3 and 4 remain reserved so existing installs keep the stable
        // Dock and Lock flag values after Volume/Notification Aura removal.
        static let dock: UInt32 = 1 << 5
        static let lock: UInt32 = 1 << 6
        static let motionDegraded: UInt32 = 1 << 30
        // Aura Studio now exposes only device-verified surfaces. The reserved
        // values stay intact so future rebuilt modules remain migration-safe.
        static let supported = island | dock
    }

    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // Island and Dock intentionally own separate draft profiles. Reusing the
    // original Island RGB keys preserves existing user choices while Dock
    // starts with its own independent color and style.
    @AppStorage("eagle.islandAura.red") private var islandRed = 0.10
    @AppStorage("eagle.islandAura.green") private var islandGreen = 0.78
    @AppStorage("eagle.islandAura.blue") private var islandBlue = 1.0
    @AppStorage("eagle.auraStudio.island.mode") private var islandModeRaw = AuraStudioMode.glow.rawValue
    @AppStorage("eagle.dockAura.red") private var dockRed = 0.62
    @AppStorage("eagle.dockAura.green") private var dockGreen = 0.25
    @AppStorage("eagle.dockAura.blue") private var dockBlue = 1.0
    @AppStorage("eagle.auraStudio.dock.mode") private var dockModeRaw = AuraStudioMode.glow.rawValue
    @AppStorage("eagle.islandGallery.positionX") private var islandPositionX = 0.0
    @AppStorage("eagle.islandGallery.positionY") private var islandPositionY = 0.0
    @AppStorage("eagle.dockGallery.positionX") private var dockPositionX = 0.0
    @AppStorage("eagle.dockGallery.positionY") private var dockPositionY = 0.0
    @AppStorage("eagle.auraStudio.editingTarget") private var selectedTargetRaw = AuraStudioTarget.island.rawValue
    @AppStorage("eagle.auraStudio.editingIcons") private var editingIcons = false
    @AppStorage("eagle.auraStudio.mode") private var legacySelectedModeRaw = AuraStudioMode.glow.rawValue
    @AppStorage("eagle.auraStudio.independentProfilesMigrated") private var independentProfilesMigrated = false
    @AppStorage("eagle.auraStudio.activeFlags") private var activeFlagsRaw = 0
    @AppStorage("eagle.auraStudio.activeMode") private var activeModeRaw = 0
    @AppStorage("eagle.auraStudio.activeIslandMode") private var activeIslandModeRaw = 0
    @AppStorage("eagle.auraStudio.activeDockMode") private var activeDockModeRaw = 0
    @AppStorage("eagle.auraStudio.activeSpringBoardPID") private var activeSpringBoardPID = 0
    @AppStorage("eagle.auraStudio.activeIslandRed") private var activeIslandRed = 26
    @AppStorage("eagle.auraStudio.activeIslandGreen") private var activeIslandGreen = 199
    @AppStorage("eagle.auraStudio.activeIslandBlue") private var activeIslandBlue = 255
    @AppStorage("eagle.auraStudio.activeDockRed") private var activeDockRed = 158
    @AppStorage("eagle.auraStudio.activeDockGreen") private var activeDockGreen = 64
    @AppStorage("eagle.auraStudio.activeDockBlue") private var activeDockBlue = 255
    @AppStorage("eagle.dockGallery.activeStyle") private var activeDockGalleryStyleRaw = 0
    @AppStorage(EagleReleaseChannel.storageKey) private var releaseChannelRaw =
        EagleReleaseChannel.stable.rawValue
    @State private var isApplying = false
    @State private var notice: AuraStudioNotice?
    @State private var applyStage = ""
    @State private var applySafetyBlocked = false
    @State private var activeOperationID: String?
    @State private var diagnosticsURL: URL?
    @State private var operationStepIndex = 0
    @State private var operationStepCount = 0
    @State private var operationIsRemoval = false


    private let auraEngineBuild = "2026.08.31-r57-trimmed-styles"

    private var islandCompatibility: EagleDynamicIslandCompatibility {
        .current
    }

    private var islandProfileAvailable: Bool {
        islandCompatibility.availability == .supported
    }

    private var deviceSupportedFlags: UInt32 {
        islandProfileAvailable ? Flag.supported : Flag.dock
    }

    private var islandHardwareUnavailableMessage: String {
        diagnosticsPresentation.islandHardwareUnavailableMessage
    }

    private var selectedTarget: AuraStudioTarget {
        get {
            EagleAuraStudioTarget.storedSelection(
                rawValue: selectedTargetRaw,
                islandProfileAvailable: { islandProfileAvailable }
            )
        }
        nonmutating set { selectedTargetRaw = newValue.rawValue }
    }

    private var releaseChannel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: releaseChannelRaw)
    }

    private func policyAllows(
        _ mode: AuraStudioMode,
        for target: AuraStudioTarget
    ) -> Bool {
        EagleAuraStudioModePolicy.allows(
            mode,
            isIsland: target == .island,
            pulseAllowed: { EagleFeaturePolicy.allows(.auraPulse, channel: releaseChannel) },
            rainbowAllowed: { EagleFeaturePolicy.allows(.auraRainbow, channel: releaseChannel) }
        )
    }

    private func normalizedMode(
        rawValue: Int,
        for target: AuraStudioTarget
    ) -> AuraStudioMode {
        EagleAuraStudioModePolicy.normalizedMode(
            rawValue: rawValue,
            allows: { policyAllows($0, for: target) }
        )
    }

    private func normalizeDraftModesForPolicy() {
        draftModes.normalizeDraftModesForPolicy()
    }

    private var selectedMode: AuraStudioMode {
        get { draftModes.selectedMode }
        nonmutating set { draftModes.selectedMode = newValue }
    }

    private var availableModes: [AuraStudioMode] {
        draftModes.availableModes
    }

    private var draftModes: EagleAuraStudioDraftModes<AuraStudioTarget> {
        EagleAuraStudioDraftModes(
            islandTarget: .island,
            dockTarget: .dock,
            readTarget: { selectedTarget },
            readIsland: { islandModeRaw },
            writeIsland: { islandModeRaw = $0 },
            readDock: { dockModeRaw },
            writeDock: { dockModeRaw = $0 },
            normalize: { normalizedMode(rawValue: $0, for: $1) },
            allows: { policyAllows($0, for: $1) }
        )
    }

    private var auraColor: Color {
        color(for: selectedTarget)
    }

    private var displayGeometry: AuraStudioDisplayGeometry {
        .current
    }

    private var compactIslandPreviewSize: CGSize {
        EagleAuraStudioPreview.compactIslandSize(
            readLogicalWidth: { displayGeometry.logicalSize.width },
            readCompactWidth: { displayGeometry.compactIslandFrame.width },
            readCompactHeight: { displayGeometry.compactIslandFrame.height }
        )
    }

    private var selectedCapabilityTitle: String {
        capabilityPresentation.selectedCapabilityTitle
    }

    private var selectedCapabilityDescription: String {
        capabilityPresentation.selectedCapabilityDescription
    }

    private var capabilityPresentation: EagleAuraStudioCapability {
        EagleAuraStudioCapability(
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            accessIsReady: { mgr.dsready },
            operationInProgress: { isApplying },
            requestedFlags: { selectedFlags },
            selectedTargetTitle: { selectedTarget.title },
            selectedTargetIsIsland: { selectedTarget == .island },
            selectedMode: { selectedMode },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        )
    }

    private var previewLightColor: Color {
        previewLightColor(for: selectedTarget)
    }

    private var previewTintFillColor: Color {
        EagleAuraStudioPreview.tintFill(
            readRed: { sanitizedChannel(islandRed) },
            readGreen: { sanitizedChannel(islandGreen) },
            readBlue: { sanitizedChannel(islandBlue) },
            makeColor: { Color(red: $0, green: $1, blue: $2) }
        )
    }

    private func previewRingStyle(for target: AuraStudioTarget) -> AnyShapeStyle {
        previewStyles.previewRingStyle(for: target)
    }

    private func islandPreviewFillStyle(for mode: AuraStudioMode) -> AnyShapeStyle {
        previewStyles.islandPreviewFillStyle(for: mode)
    }

    private func previewSpectrumHue(for mode: AuraStudioMode) -> Double {
        EagleAuraStudioPreview.spectrumHue(for: mode, now: { Date() })
    }

    /// Wall-clock rainbow phase (0…1) for the live preview. Driven by a
    /// TimelineView instead of a repeating `withAnimation`, so the hue only
    /// moves while Rainbow is selected and can never leak onto Glow or Pulse.
    private func auraSpectrumPhase(at date: Date) -> Double {
        EagleAuraStudioPreview.spectrumPhase(at: date)
    }

    /// Smooth breathing level (0.58…1.0) for Pulse, from wall-clock time.
    private func auraPulseLevel(at date: Date) -> Double {
        EagleAuraStudioPreview.pulseLevel(at: date)
    }

    /// Full-spectrum ring that circles the loop seamlessly (red → red). Rotating
    /// its `angle` makes the neon travel around the island for Rainbow; other
    /// modes keep the steady solid surface colour.
    private func islandRingStyle(for mode: AuraStudioMode, angle: Double) -> AnyShapeStyle {
        previewStyles.islandRingStyle(for: mode, angle: angle)
    }

    /// Interior fill: the same rotating spectrum for Rainbow so the aura turns
    /// as one piece; the existing black/tint fill for every other mode.
    private func islandFillStyle(for mode: AuraStudioMode, angle: Double) -> AnyShapeStyle {
        previewStyles.islandFillStyle(for: mode, angle: angle)
    }

    private var previewStyles: EagleAuraStudioPreviewStyles {
        EagleAuraStudioPreviewStyles(
            mode: { mode(for: $0) },
            color: { color(for: $0) },
            tintFillColor: { previewTintFillColor }
        )
    }

    private var selectedFlags: UInt32 {
        selectedTarget.flag(islandFlag: Flag.island, dockFlag: Flag.dock)
    }

    private var auraColorBinding: Binding<Color> {
        EagleAuraStudioColorBinding(
            readColor: { auraColor },
            readMode: { selectedMode },
            writeMode: { selectedMode = $0 },
            writeRGB: { setSelectedRGB(red: $0, green: $1, blue: $2) }
        ).binding
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                surfaceProfilesCard
                if editingIcons {
                    HomeIconNeonView(embedded: true)
                } else {
                    previewCard
                    GalleryPositionControl(
                        x: selectedTarget == .island ? $islandPositionX : $dockPositionX,
                        y: selectedTarget == .island ? $islandPositionY : $dockPositionY,
                        disabled: isApplying
                    )
                    appearanceCard
                }

                if applySafetyBlocked || mgr.rcSafetyLocked {
                    diagnosticsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !editingIcons || !mgr.dsready {
                auraActionBar
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("Aura Studio")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isApplying)
        .onChange(of: notice?.id) { _ in
            guard let value = notice, !value.offersRespring else { return }
            EagleNotifications.shared.show(title: "Aura Studio", message: value.message)
            notice = nil
        }
        .alert(item: Binding(get: { notice?.offersRespring == true ? notice : nil }, set: { notice = $0 })) { notice in
            if notice.offersRespring {
                return Alert(
                    title: Text("Aura Studio"),
                    message: Text(notice.message),
                    primaryButton: .default(Text(LaraL10n.text(
                        en: "Respring now",
                        es: "Respring ahora"
                    ))) {
                        mgr.respring()
                    },
                    secondaryButton: .cancel(Text(LaraL10n.text(
                        en: "Later",
                        es: "Después"
                    )))
                )
            }
            return Alert(
                title: Text("Aura Studio"),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isApplying {
                ZStack {
                    Color.black.opacity(0.14).ignoresSafeArea()
                VStack(spacing: 12) {
                    EagleRainbowSpinner(size: 28)
                        Text(applyStage.isEmpty
                             ? LaraL10n.text(
                                en: "Preparing a safe system update…",
                                es: "Preparando una actualización segura…"
                             )
                             : applyStage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if operationStepCount > 0 {
                        Text(LaraL10n.text(
                            en: "Step \(min(operationStepIndex, operationStepCount)) of \(operationStepCount)",
                            es: "Paso \(min(operationStepIndex, operationStepCount)) de \(operationStepCount)"
                        ))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                    .padding(22)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .transition(.eagleWorking)
            }
        }
        .onAppear {
            entryFlow.prepareForAppearance()
#if DEBUG
            if !AuraStudioNativeContract.invariantsHold {
                AuraStudioDiagnostics.log(
                    "contract.self-test",
                    "result=failed engine=\(auraEngineBuild)"
                )
            }
#endif
        }
        .onChange(of: releaseChannelRaw) { _ in
            entryFlow.releaseChannelChanged()
        }

    }

    private var entryFlow: EagleAuraStudioEntryFlow {
        EagleAuraStudioEntryFlow(
            readMigrated: { independentProfilesMigrated },
            readLegacyMode: { legacySelectedModeRaw },
            writeIslandMode: { islandModeRaw = $0 },
            writeDockMode: { dockModeRaw = $0 },
            markMigrated: { independentProfilesMigrated = true },
            normalizeDraftModes: { normalizeDraftModesForPolicy() },
            islandAvailable: { islandProfileAvailable },
            readSelectedTarget: { selectedTargetRaw },
            writeSelectedTarget: { selectedTargetRaw = $0 },
            islandTargetRaw: AuraStudioTarget.island.rawValue,
            dockTargetRaw: AuraStudioTarget.dock.rawValue,
            reconcileActiveState: { reconcilePersistedActiveState() },
            safetyLocked: { mgr.rcSafetyLocked },
            markSafetyBlocked: { applySafetyBlocked = true },
            isApplying: { isApplying }
        )
    }

    private var previewCard: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: selectedTarget == .island ? "capsule.fill" : "dock.rectangle")
                    .foregroundStyle(.primary)
                Text(selectedTarget.title)
                    .font(.headline)
                Spacer()
                Text(selectedMode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.04, blue: 0.065),
                            Color(red: 0.012, green: 0.014, blue: 0.025),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RadialGradient(
                        colors: [
                            previewLightColor.opacity(0.30),
                            previewLightColor.opacity(0.08),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 165
                    ))
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                // 60 fps while the preview animates: the turning ring stepped visibly at 30.
                TimelineView(.animation(
                    minimumInterval: 1.0 / 60.0,
                    paused: reduceMotion ||
                        ![.pulse, .rainbow]
                            .contains(selectedMode)
                )) { context in
                    let now = context.date
                    if selectedTarget == .island {
                        let islandMode = mode(for: .island)
                        // Every animated palette uses the same proven rotating
                        // ring preview; only its restricted colors differ.
                        let angle = islandMode.usesFixedPalette
                            ? auraSpectrumPhase(at: now) * 360
                            : 0
                        let level = islandMode == .pulse ? auraPulseLevel(at: now) : 1
                        let ring = islandRingStyle(for: islandMode, angle: angle)
                        let fill = islandFillStyle(for: islandMode, angle: angle)

                        if let photoAssetName = islandMode.photoAssetName {
                            Image(photoAssetName)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 220, height: 92)
                                .offset(x: GalleryPosition.component(islandPositionX),
                                        y: GalleryPosition.component(islandPositionY))
                        } else {
                            ZStack {
                                Capsule()
                                    .stroke(ring, lineWidth: 12)
                                    .blur(radius: 10)
                                    .opacity(0.48)
                                Capsule()
                                    .fill(fill)
                                Capsule()
                                    .stroke(ring, lineWidth: 4)
                                if islandMode.fillsIslandBackground {
                                    HStack(spacing: 6) {
                                        Capsule()
                                            .fill(.black)
                                            .frame(width: 58, height: 17)
                                        Circle()
                                            .fill(.black)
                                            .frame(width: 17, height: 17)
                                    }
                                    .offset(x: 4)
                                }
                            }
                            .frame(width: 190, height: 55)
                            .shadow(
                                color: islandMode == .rainbow
                                    ? .clear
                                    : previewLightColor,
                                radius: 14
                            )
                            .opacity(level)
                            .offset(x: GalleryPosition.component(islandPositionX),
                                    y: GalleryPosition.component(islandPositionY))
                        }
                    } else {
                        let dockMode = mode(for: .dock)
                        let hue = dockMode == .rainbow ? auraSpectrumPhase(at: now) : 0
                        let level = dockMode == .pulse ? auraPulseLevel(at: now) : 1

                        ZStack {
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .fill(Color.white.opacity(0.075))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                                        .fill(previewLightColor.opacity(0.09))
                                }
                            HStack(spacing: 13) {
                                ForEach(0..<4, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.82 - Double(index) * 0.08))
                                        .frame(width: 40, height: 40)
                                }
                            }
                        }
                        .frame(width: 286, height: 78)
                        .overlay {
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .stroke(previewRingStyle(for: .dock), lineWidth: 3)
                        }
                        .shadow(color: previewLightColor.opacity(0.85), radius: 13)
                        .hueRotation(.degrees(hue * 360))
                        .opacity(level)
                        .offset(x: GalleryPosition.component(dockPositionX),
                                y: GalleryPosition.component(dockPositionY))
                    }
                }
            }
            .frame(height: 145)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .padding(8)
            .background(
                colorScheme == .dark
                    ? Color.black.opacity(0.28)
                    : Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(EagleVisualTheme.surfaceBorder(for: colorScheme), lineWidth: 1)
            }
            .eagleSurfaceShadow(cornerRadius: 28, radius: 12, y: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LaraL10n.text(
                en: "\(selectedTarget.title) preview, \(selectedMode.title)",
                es: "Vista previa de \(selectedTarget.title), \(selectedMode.title)"
            ))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableModes.count > 1 {
                Picker(
                    LaraL10n.text(en: "Light Style", es: "Estilo de luz"),
                    selection: Binding(get: { selectedMode }, set: { selectedMode = $0 })
                ) {
                    ForEach(availableModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Label(AuraStudioMode.glow.title, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(previewLightColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(
                        previewLightColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
            }

            Divider()

            HStack {
                Text(LaraL10n.text(en: "Color", es: "Color"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ColorPicker(
                    LaraL10n.text(en: "Custom color", es: "Color personalizado"),
                    selection: auraColorBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
            }

            HStack(spacing: 9) {
                ForEach(presets, id: \.name) { preset in
                    Button {
                        if selectedMode.usesFixedPalette {
                            selectedMode = .glow
                        }
                        setSelectedRGB(
                            red: preset.red,
                            green: preset.green,
                            blue: preset.blue
                        )
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(red: preset.red, green: preset.green, blue: preset.blue))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1)
                                    if presetIsSelected(preset) && !selectedMode.usesFixedPalette {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.75), radius: 2)
                                            .transition(.eagleCheck)
                                    }
                                }
                                .shadow(
                                    color: Color(red: preset.red, green: preset.green, blue: preset.blue).opacity(0.6),
                                    radius: 6
                                )
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .accessibilityLabel(preset.name)
                    .accessibilityValue(
                        presetIsSelected(preset) && !selectedMode.usesFixedPalette
                            ? LaraL10n.text(en: "Selected", es: "Seleccionado")
                            : ""
                    )
                }

                if policyAllows(.rainbow, for: selectedTarget) {
                    Button {
                        selectedMode = .rainbow
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    AngularGradient(
                                        colors: [
                                            .red, .orange, .yellow, .green, .cyan,
                                            .blue, .purple, .pink, .red,
                                        ],
                                        center: .center
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.72), lineWidth: 1.2)
                                    if selectedMode == .rainbow {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.75), radius: 2)
                                            .transition(.eagleCheck)
                                    }
                                }
                                .shadow(color: previewLightColor.opacity(0.9), radius: 8)
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .accessibilityLabel(
                        LaraL10n.text(en: "Animated rainbow", es: "Arcoíris animado")
                    )
                    .accessibilityValue(
                        selectedMode == .rainbow
                            ? LaraL10n.text(en: "Selected", es: "Seleccionado")
                            : ""
                    )
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .disabled(isApplying)
    }

    /// Apply and Restore stay fixed at the bottom, in reach of the thumb, while the screen scrolls.
    /// Until Eagle is prepared, Prepare takes their place there, so it is always at hand.
    private var auraActionBar: some View {
        EagleApplyBar(ready: mgr.dsready) {
            VStack(spacing: 8) {
                applyButton
                restoreButton
            }
            .disabled(isApplying)
        }
    }

    private var surfaceProfilesCard: some View {
        EagleAuraStudioSurfacePicker(
            readEditingIcons: { editingIcons },
            writeEditingIcons: { editingIcons = $0 },
            readTarget: { selectedTarget },
            writeTarget: { selectedTarget = $0 },
            islandAvailable: { islandProfileAvailable },
            operationInProgress: { isApplying },
            modeTitle: { mode(for: $0).title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).surfaceProfilesCard
    }

    private var adaptiveNote: some View {
        EagleAuraStudioAccessNote(
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            accessReady: { mgr.dsready },
            lightColor: { previewLightColor },
            capabilityTitle: { selectedCapabilityTitle },
            capabilityDescription: { selectedCapabilityDescription },
            engineBuild: { auraEngineBuild },
            channelTitle: { releaseChannel.title },
            displayZoomed: { displayGeometry.isDisplayZoomed }
        ).note
    }

    private var isApplyButtonDisabled: Bool {
        capabilityPresentation.isApplyButtonDisabled
    }

    private var applyButtonForeground: Color {
        buttonStyles.applyButtonForeground
    }

    private var applyButtonBackground: Color {
        buttonStyles.applyButtonBackground
    }

    private var buttonStyles: EagleAuraStudioButtonStyles {
        EagleAuraStudioButtonStyles(
            isDisabled: { isApplyButtonDisabled },
            isDark: { colorScheme == .dark },
            accessReady: { mgr.dsready },
            actionText: { EagleVisualTheme.actionText },
            actionFill: { EagleVisualTheme.actionFill }
        )
    }

    private var applyButton: some View {
        EagleAuraStudioApplyButton(
            apply: { runAuraOperation(.apply(selectedMode), flags: selectedFlags) },
            accessReady: { mgr.dsready },
            modeTitle: { selectedMode.title },
            foreground: { applyButtonForeground },
            background: { applyButtonBackground },
            isDark: { colorScheme == .dark },
            surfaceBorder: { EagleVisualTheme.surfaceBorder(for: colorScheme) },
            isDisabled: { isApplyButtonDisabled },
            targetTitle: { selectedTarget.title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).button
    }

    private var restoreButton: some View {
        EagleAuraStudioRestoreButton(
            restore: { runAuraOperation(.remove, flags: selectedFlags) },
            operationInProgress: { isApplying },
            accessReady: { mgr.dsready },
            selectedFlags: { selectedFlags },
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            targetTitle: { selectedTarget.title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).button
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if applySafetyBlocked || mgr.rcSafetyLocked {
                Label(
                    LaraL10n.text(
                        en: "Safety lock active for this Eagle run",
                        es: "Bloqueo de seguridad activo durante esta ejecución de Eagle"
                    ),
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

                Text(LaraL10n.text(
                    en: "Aura Studio will not retry after an unverified call, timeout, SpringBoard restart, or main-thread error. Export the report, then fully close and reopen Eagle before another test.",
                    es: "Aura Studio no volverá a intentarlo después de una llamada no verificada, un tiempo agotado, un reinicio de SpringBoard o un error del hilo principal. Exporta el informe y luego cierra y abre Eagle completamente antes de otra prueba."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    diagnosticsURL = makeDiagnosticsReport(
                        summary: mgr.rcSafetyReason ?? "Manual Aura Studio export"
                    )
                } label: {
                    Label(
                        LaraL10n.text(en: "Build Report", es: "Crear informe"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
                .buttonStyle(.bordered)

                if let diagnosticsURL {
                    ShareLink(item: diagnosticsURL) {
                        Label(
                            LaraL10n.text(en: "Share", es: "Compartir"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    // The app tint is white in dark appearance: the label takes the contrasting colour.
                    .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var presets: [(name: String, red: Double, green: Double, blue: Double)] {
        EagleAuraStudioColors.presets(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }

    private func presetIsSelected(
        _ preset: (name: String, red: Double, green: Double, blue: Double)
    ) -> Bool {
        EagleAuraStudioColors.presetIsSelected(preset, selectedRGB: {
            selectedTarget == .island
                ? (sanitizedChannel(islandRed), sanitizedChannel(islandGreen), sanitizedChannel(islandBlue))
                : (sanitizedChannel(dockRed), sanitizedChannel(dockGreen), sanitizedChannel(dockBlue))
        })
    }

    private func mode(for target: AuraStudioTarget) -> AuraStudioMode {
        draftModes.mode(for: target)
    }

    private func color(for target: AuraStudioTarget) -> Color {
        colorPresentation.color(for: target)
    }

    private func previewLightColor(for target: AuraStudioTarget) -> Color {
        colorPresentation.previewLightColor(for: target)
    }

    private func setSelectedRGB(red: Double, green: Double, blue: Double) {
        EagleAuraStudioColors.setSelectedRGB(
            red: red, green: green, blue: blue,
            isIsland: selectedTarget == .island,
            writeIsland: { islandRed = $0; islandGreen = $1; islandBlue = $2 },
            writeDock: { dockRed = $0; dockGreen = $1; dockBlue = $2 }
        )
    }

    private func activeColor(for flag: UInt32) -> Color {
        colorPresentation.activeColor(for: flag)
    }

    private var colorPresentation: EagleAuraStudioColorPresentation<Color> {
        EagleAuraStudioColorPresentation(
            readDraftRed: { $0 == .island ? islandRed : dockRed },
            readDraftGreen: { $0 == .island ? islandGreen : dockGreen },
            readDraftBlue: { $0 == .island ? islandBlue : dockBlue },
            readActiveRGB: { $0 == .island
                ? (activeIslandRed, activeIslandGreen, activeIslandBlue)
                : (activeDockRed, activeDockGreen, activeDockBlue)
            },
            islandFlag: Flag.island,
            mode: { mode(for: $0) },
            spectrumHue: { previewSpectrumHue(for: $0) },
            sanitize: { sanitizedChannel($0) },
            makeRGB: { Color(red: $0, green: $1, blue: $2) },
            makeHSB: { Color(hue: $0, saturation: $1, brightness: $2) }
        )
    }

    private func flag(for target: AuraStudioTarget) -> UInt32 {
        target.flag(islandFlag: Flag.island, dockFlag: Flag.dock)
    }

    private func isTargetActive(_ target: AuraStudioTarget) -> Bool {
        profileState.isTargetActive(target)
    }

    private func activeMode(for target: AuraStudioTarget) -> AuraStudioMode? {
        profileState.activeMode(for: target)
    }

    private func draftMatchesActive(_ target: AuraStudioTarget) -> Bool {
        profileState.draftMatchesActive(target)
    }

    private var profileState: EagleAuraStudioProfileState<AuraStudioTarget> {
        EagleAuraStudioProfileState(
            readActiveFlags: { EagleStoredThemeValues.flags(activeFlagsRaw) },
            flag: { flag(for: $0) },
            readActiveMode: { $0 == .island ? activeIslandModeRaw : activeDockModeRaw },
            mode: { mode(for: $0) },
            readDraftRGB: { target in
                if target == .island {
                    return (
                        Int((islandRed * 255).rounded()),
                        Int((islandGreen * 255).rounded()),
                        Int((islandBlue * 255).rounded())
                    )
                } else {
                    return (
                        Int((dockRed * 255).rounded()),
                        Int((dockGreen * 255).rounded()),
                        Int((dockBlue * 255).rounded())
                    )
                }
            },
            readActiveRGB: { $0 == .island
                ? (activeIslandRed, activeIslandGreen, activeIslandBlue)
                : (activeDockRed, activeDockGreen, activeDockBlue)
            }
        )
    }

    private func profileStatusText(for target: AuraStudioTarget) -> String {
        EagleAuraStudioProfileStatus(
            islandTarget: AuraStudioTarget.island,
            dockTarget: AuraStudioTarget.dock,
            islandProfileAvailable: { islandProfileAvailable },
            islandModelUnknown: { islandCompatibility.availability == .unknown },
            isTargetActive: { isTargetActive($0) },
            readDockMode: { activeDockModeRaw },
            readIslandMode: { activeIslandModeRaw },
            activeMode: { activeMode(for: $0) },
            draftMatchesActive: { draftMatchesActive($0) },
            modeTitle: { $0.title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        ).profileStatusText(for: target)
    }

    private func rgb255String(_ red: Double, _ green: Double, _ blue: Double) -> String {
        diagnosticsPresentation.rgb255String(red, green, blue)
    }

    /// UserDefaults can contain stale or externally-written floating-point
    /// values. Never pass NaN/∞ (or an out-of-range channel) into Color or the
    /// native C bridge: converting NaN to Int would trap the Eagle process.
    private func sanitizedChannel(_ value: Double, fallback: Double = 0) -> Double {
        EagleAuraStudioColors.sanitizedChannel(value, fallback: fallback)
    }

    private func channel255(_ value: Double) -> Int {
        EagleAuraStudioColors.channel255(value)
    }

    private var activeModuleCount: Int {
        diagnosticsPresentation.activeModuleCount
    }

    private var verifiedSurfaceSummary: String {
        diagnosticsPresentation.verifiedSurfaceSummary
    }

    private var diagnosticsPresentation: EagleAuraStudioDiagnosticsPresentation<EagleDynamicIslandCompatibility.Availability> {
        EagleAuraStudioDiagnosticsPresentation(
            supportedAvailability: .supported,
            unsupportedAvailability: .unsupported,
            isSimulator: { islandCompatibility.isSimulator },
            availability: { islandCompatibility.availability },
            readActiveFlags: { EagleStoredThemeValues.flags(activeFlagsRaw) },
            readSupportedFlags: { deviceSupportedFlags },
            channel255: { channel255($0) },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        )
    }

    private func reconcilePersistedActiveState(currentPID providedPID: Int32? = nil) {
        EagleAuraStudioReconciliation(
            lookupCurrentPID: {
                "SpringBoard".withCString { find_process_pid($0) }
            },
            decodeFlags: { EagleStoredThemeValues.flags($0) },
            supportedFlags: Flag.supported,
            deviceSupportedFlags: { deviceSupportedFlags },
            islandFlag: Flag.island,
            dockFlag: Flag.dock,
            read: { field in
                switch field {
                case .flags: return activeFlagsRaw
                case .legacyMode: return activeModeRaw
                case .islandMode: return activeIslandModeRaw
                case .dockMode: return activeDockModeRaw
                case .dockGalleryStyle: return activeDockGalleryStyleRaw
                case .springBoardPID: return activeSpringBoardPID
                }
            },
            write: { field, value in
                switch field {
                case .flags: activeFlagsRaw = value
                case .legacyMode: activeModeRaw = value
                case .islandMode: activeIslandModeRaw = value
                case .dockMode: activeDockModeRaw = value
                case .dockGalleryStyle: activeDockGalleryStyleRaw = value
                case .springBoardPID: activeSpringBoardPID = value
                }
            },
            diagnosticsToken: { islandCompatibility.diagnosticsToken },
            log: { AuraStudioDiagnostics.log($0, $1) }
        ).reconcilePersistedActiveState(currentPID: providedPID)
    }

    private func runAuraOperation(
        _ operation: AuraStudioOperation,
        flags: UInt32
    ) {
        // The visual objects live inside one SpringBoard process. Reconcile
        // again at the moment of the request (not only onAppear) so a respring
        // while this screen remains open cannot carry stale badges or modes
        // into a fresh process.
        let context = EagleAuraStudioRequestCapture(
            supportedFlags: Flag.supported,
            islandFlag: Flag.island,
            dockFlag: Flag.dock,
            currentPID: { "SpringBoard".withCString { find_process_pid($0) } },
            reconcile: { reconcilePersistedActiveState(currentPID: $0) },
            readVersion: { ProcessInfo.processInfo.operatingSystemVersion },
            makeUUID: { UUID() },
            targetTitle: { $0.title },
            readDisplay: { displayGeometry },
            islandFrame: { $0.compactIslandFrame },
            dockFrame: { $0.dockAuraFrame },
            engineBuild: { auraEngineBuild },
            deviceModel: { devicemachine() },
            hardwareToken: { islandCompatibility.diagnosticsToken },
            log: { AuraStudioDiagnostics.log($0, $1) }
        ).capture(operation: operation, flags: flags)
        let operationSpringBoardPID = context.springBoardPID
        let version = context.version
        let operationID = context.operationID
        let mode = context.mode
        let requestedProfileMode = context.requestedProfileMode
        let requestedFlags = context.requestedFlags
        let requestedTarget = context.requestedTarget
        let display = context.display

        guard let operationTarget = requestAdmission.admit(
            operation: operation,
            operationID: operationID,
            mode: mode,
            requestedProfileMode: requestedProfileMode,
            requestedFlags: requestedFlags,
            requestedTarget: requestedTarget,
            majorVersion: version.majorVersion,
            displayIsZoomed: display.isDisplayZoomed
        ) else { return }

        let steps = EagleAuraStudioOperation.steps(
            for: requestedFlags,
            islandFlag: Flag.island,
            dockFlag: Flag.dock
        )

        let parameters = EagleAuraStudioRequestPreparation.prepare(
            target: operationTarget,
            isRemoving: operation.isRemoving,
            readIslandRed: { islandRed },
            readIslandGreen: { islandGreen },
            readIslandBlue: { islandBlue },
            readDockRed: { dockRed },
            readDockGreen: { dockGreen },
            readDockBlue: { dockBlue },
            sanitize: { sanitizedChannel($0) },
            makeZeroPosition: { GalleryPosition(x: 0, y: 0) },
            savedPosition: { GalleryPosition.saved($0) },
            channel255: { channel255($0) }
        )
        let requestedPosition = parameters.position
        let positionSurface = parameters.positionSurface
        let redValue = parameters.red
        let greenValue = parameters.green
        let blueValue = parameters.blue
        AuraStudioDiagnostics.log(
            "preflight.contract",
            "op=\(operationID) target=\(operationTarget.title) " +
                "flags=0x\(String(requestedFlags, radix: 16)) " +
                "mode=\(requestedProfileMode.rawValue) " +
                "rgb=\(redValue),\(greenValue),\(blueValue)"
        )
        let previouslyVerified = EagleStoredThemeValues.flags(activeFlagsRaw) & deviceSupportedFlags
        var retainedVerified = previouslyVerified
        var newlyApplied: UInt32 = 0
        var removedFlags: UInt32 = 0
        var motionDegraded = false
        var firstUnavailableResult: Int32?
        var verifiedFallbackResult: Int32?

        operationUI.begin(
            operationID: operationID,
            isRemoving: operation.isRemoving,
            stepCount: steps.count
        )

        func resetOperationUI() {
            operationUI.reset()
        }

        func failBeforeNativeCall(_ reason: String) {
            EagleAuraStudioPreflightFailure(
                operationID: operationID,
                targetTitle: { operationTarget.title },
                log: { AuraStudioDiagnostics.log($0, $1) },
                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },
                resetOperationUI: { resetOperationUI() },
                endGate: { AuraStudioApplyGate.end() },
                localizedText: { LaraL10n.text(en: $0, es: $1) },
                showNotice: { notice = AuraStudioNotice(message: $0) }
            ).failBeforeNativeCall(reason)
        }

        func failAfterNativeCall(
            _ reason: String,
            result: Int32? = nil,
            userDetail: String? = nil
        ) {
            EagleAuraStudioUnverifiedFailure(
                operationID: operationID,
                retainedVerified: retainedVerified,
                newlyApplied: newlyApplied,
                removedFlags: removedFlags,
                islandFlag: Flag.island,
                dockFlag: Flag.dock,
                targetTitle: { operationTarget.title },
                writeActiveFlags: { activeFlagsRaw = $0 },
                readActiveFlags: { activeFlagsRaw },
                writeActiveMode: { activeModeRaw = $0 },
                writeIslandMode: { activeIslandModeRaw = $0 },
                writeDockMode: { activeDockModeRaw = $0 },
                writeSpringBoardPID: { activeSpringBoardPID = $0 },
                currentSpringBoardPID: { "SpringBoard".withCString { find_process_pid($0) } },
                quarantine: { mgr.quarantineRemoteCall(reason: $0) },
                writeSafetyBlocked: { applySafetyBlocked = $0 },
                lockGate: { AuraStudioApplyGate.lock() },
                log: { AuraStudioDiagnostics.log($0, $1) },
                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },
                resetOperationUI: { resetOperationUI() },
                localizedText: { LaraL10n.text(en: $0, es: $1) },
                showNotice: { notice = AuraStudioNotice(message: $0) }
            ).failAfterNativeCall(reason, result: result, userDetail: userDetail)
        }

        func finishVerifiedRollback(
            _ result: Int32,
            step: AuraStudioOperationStep,
            reason: String
        ) {
            EagleAuraStudioVerifiedRollback(
                previouslyVerified: previouslyVerified,
                newlyApplied: newlyApplied,
                operationSpringBoardPID: operationSpringBoardPID,
                operationID: operationID,
                readRetained: { retainedVerified },
                writeRetained: { retainedVerified = $0 },
                writeActiveFlags: { activeFlagsRaw = $0 },
                writeSpringBoardPID: { activeSpringBoardPID = $0 },
                log: { AuraStudioDiagnostics.log($0, $1) },
                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },
                resetOperationUI: { resetOperationUI() },
                endGate: { AuraStudioApplyGate.end() },
                errorMessage: { message(for: $0) },
                localizedText: { LaraL10n.text(en: $0, es: $1) },
                showNotice: { notice = AuraStudioNotice(message: $0) }
            ).finishVerifiedRollback(
                result,
                stepFlag: step.flag,
                stepEnglishName: step.englishName,
                reason: reason
            )
        }

        func completeSuccess(deadlineWarning: Bool = false) {
            EagleAuraStudioCompletion(
                retainedVerified: retainedVerified,
                newlyApplied: newlyApplied,
                removedFlags: removedFlags,
                requestedFlags: requestedFlags,
                operationIsRemoving: operation.isRemoving,
                operationSpringBoardPID: operationSpringBoardPID,
                operationID: operationID,
                mode: mode,
                motionDegraded: motionDegraded,
                firstUnavailableResult: firstUnavailableResult,
                verifiedFallbackResult: verifiedFallbackResult,
                writeActiveFlags: { activeFlagsRaw = $0 },
                readIslandMode: { activeIslandModeRaw },
                writeActiveMode: { activeModeRaw = $0 },
                writeIslandMode: { activeIslandModeRaw = $0 },
                writeDockMode: { activeDockModeRaw = $0 },
                writeSpringBoardPID: { activeSpringBoardPID = $0 },
                log: { AuraStudioDiagnostics.log($0, $1) },
                recordDiagnostics: { diagnosticsURL = makeDiagnosticsReport(summary: $0) },
                resetOperationUI: { resetOperationUI() },
                endGate: { AuraStudioApplyGate.end() },
                errorMessage: { message(for: $0) },
                successMessage: {
                    successMessage(
                        appliedFlags: $0, requestedFlags: $1, restoring: $2,
                        motionDegraded: $3, appliedMode: $4
                    )
                },
                localizedText: { LaraL10n.text(en: $0, es: $1) },
                informationKind: EagleNoticeKind.information,
                errorKind: EagleNoticeKind.error,
                successKind: EagleNoticeKind.success,
                showNotification: { EagleNotifications.shared.show(title: $0, message: $1, kind: $2) }
            ).completeSuccess(deadlineWarning: deadlineWarning)
        }

        func runStep(_ index: Int) {
            guard let step = EagleAuraStudioStepFlow.begin(
                index: index,
                steps: steps,
                operationID: operationID,
                readOperationID: { activeOperationID },
                readApplying: { isApplying },
                writeStepIndex: { operationStepIndex = $0 },
                writeStage: { applyStage = $0 },
                localizedText: { LaraL10n.text(en: $0, es: $1) },
                log: { AuraStudioDiagnostics.log($0, $1) },
                complete: { completeSuccess() }
            ) else { return }
            mgr.prepareFreshRemoteCall(
                process: "SpringBoard",
                timeout: 20
            ) { process, sessionError in
                guard let admitted = EagleAuraStudioSessionAdmission(
                    readOperationID: { activeOperationID },
                    readApplying: { isApplying },
                    readPID: { $0.pid },
                    readIsolated: { $0.creatingExtraThread },
                    currentPID: { "SpringBoard".withCString { find_process_pid($0) } },
                    beginExclusive: { mgr.beginExclusiveRemoteCall(label: $0, expectedSession: $1) },
                    readRetained: { retainedVerified },
                    writeRetained: { retainedVerified = $0 },
                    writeNewlyApplied: { newlyApplied = $0 },
                    writeActiveFlags: { activeFlagsRaw = $0 },
                    writeActiveMode: { activeModeRaw = $0 },
                    writeIslandMode: { activeIslandModeRaw = $0 },
                    writeDockMode: { activeDockModeRaw = $0 },
                    writeSpringBoardPID: { activeSpringBoardPID = $0 },
                    failBefore: { failBeforeNativeCall($0) },
                    failAfter: { failAfterNativeCall($0) }
                ).admit(
                    process: process,
                    sessionError: sessionError,
                    operationID: operationID,
                    operationSpringBoardPID: operationSpringBoardPID,
                    stepFlag: step.flag,
                    stepEnglishName: step.englishName
                ) else { return }
                let process = admitted.process
                let targetPID = admitted.targetPID

                EagleAuraStudioStepFlow.nativeStarted(
                    operationID: operationID,
                    step: step,
                    operation: operation,
                    targetPID: targetPID,
                    writeStage: { applyStage = $0 },
                    localizedText: { LaraL10n.text(en: $0, es: $1) },
                    log: { AuraStudioDiagnostics.log($0, $1) }
                )
                let started = Date()
                var nativeFinished = false
                var hardDeadlineExceeded = false
                let progress = EagleAuraStudioStepProgress(
                    operationID: operationID,
                    step: step,
                    readOperationID: { activeOperationID },
                    readApplying: { isApplying },
                    readFinished: { nativeFinished },
                    writeStage: { applyStage = $0 },
                    writeDeadlineExceeded: { hardDeadlineExceeded = $0 },
                    localizedText: { LaraL10n.text(en: $0, es: $1) },
                    log: { AuraStudioDiagnostics.log($0, $1) },
                    quarantine: { mgr.quarantineRemoteCall(reason: $0) },
                    writeSafetyBlocked: { applySafetyBlocked = $0 },
                    lockGate: { AuraStudioApplyGate.lock() }
                )
                let progressSchedule = EagleAuraStudioProgressScheduler.start(progress: progress)

                DispatchQueue.global(qos: .userInitiated).async {
                    let result = autoreleasepool {
                        eagle_configure_gallery_position(
                            positionSurface,
                            requestedPosition.x,
                            requestedPosition.y
                        )
                        defer { eagle_configure_gallery_position(positionSurface, 0, 0) }
                        return eagle_set_aura_studio(
                            process,
                            redValue,
                            greenValue,
                            blueValue,
                            Int32(operation.nativeMode),
                            step.flag
                        )
                    }
                    let elapsed = Date().timeIntervalSince(started)
                    let processError = process.lastError
                    let springBoardPID = "SpringBoard".withCString {
                        find_process_pid($0)
                    }
                    AuraStudioDiagnostics.log(
                        "step.native.end",
                        "op=\(operationID) module=\(step.englishName) result=\(result) " +
                        "elapsed=\(String(format: "%.3f", elapsed)) target=\(targetPID) " +
                        "current=\(springBoardPID) error=\(processError ?? "none")"
                    )
                    DispatchQueue.main.async {
                        guard EagleAuraStudioResultAdmission(
                            currentPID: { "SpringBoard".withCString { find_process_pid($0) } },
                            readOperationID: { activeOperationID },
                            readApplying: { isApplying },
                            readFinished: { nativeFinished },
                            writeFinished: { nativeFinished = $0 },
                            cancelSoftProgress: { progressSchedule.cancelSoftProgress() },
                            cancelHardDeadline: { progressSchedule.cancelHardDeadline() },
                            endExclusive: { mgr.endExclusiveRemoteCall(label: $0) },
                            log: { AuraStudioDiagnostics.log($0, $1) },
                            writeActiveFlags: { activeFlagsRaw = $0 },
                            writeActiveMode: { activeModeRaw = $0 },
                            writeIslandMode: { activeIslandModeRaw = $0 },
                            writeDockMode: { activeDockModeRaw = $0 },
                            writeSpringBoardPID: { activeSpringBoardPID = $0 },
                            readRetained: { retainedVerified },
                            writeRetained: { retainedVerified = $0 },
                            writeNewlyApplied: { newlyApplied = $0 },
                            readHealthy: { process.isHealthy },
                            readTimedOut: { process.lastCallTimedOut },
                            localizedText: { LaraL10n.text(en: $0, es: $1) },
                            failAfter: { failAfterNativeCall($0, result: $1, userDetail: $2) }
                        ).admit(
                            result: result,
                            processError: processError,
                            operationID: operationID,
                            operationSpringBoardPID: operationSpringBoardPID,
                            targetPID: targetPID,
                            springBoardPID: springBoardPID,
                            stepFlag: step.flag,
                            stepEnglishName: step.englishName,
                            stepSpanishName: step.spanishName
                        ) else { return }
                        EagleAuraStudioResultConsumption(
                            islandFlag: Flag.island,
                            dockFlag: Flag.dock,
                            supportedFlags: Flag.supported,
                            motionDegradedFlag: Flag.motionDegraded,
                            readRetained: { retainedVerified },
                            writeRetained: { retainedVerified = $0 },
                            readNewlyApplied: { newlyApplied },
                            writeNewlyApplied: { newlyApplied = $0 },
                            readRemoved: { removedFlags },
                            writeRemoved: { removedFlags = $0 },
                            readUnavailable: { firstUnavailableResult },
                            writeUnavailable: { firstUnavailableResult = $0 },
                            writeFallback: { verifiedFallbackResult = $0 },
                            readMotionDegraded: { motionDegraded },
                            writeMotionDegraded: { motionDegraded = $0 },
                            readDeadlineExceeded: { hardDeadlineExceeded },
                            readStored: { field in
                                switch field {
                                case .flags: return activeFlagsRaw
                                case .legacyMode: return activeModeRaw
                                case .islandMode: return activeIslandModeRaw
                                case .dockMode: return activeDockModeRaw
                                case .dockGalleryStyle: return activeDockGalleryStyleRaw
                                case .springBoardPID: return activeSpringBoardPID
                                case .islandRed: return activeIslandRed
                                case .islandGreen: return activeIslandGreen
                                case .islandBlue: return activeIslandBlue
                                case .dockRed: return activeDockRed
                                case .dockGreen: return activeDockGreen
                                case .dockBlue: return activeDockBlue
                                }
                            },
                            writeStored: { field, value in
                                switch field {
                                case .flags: activeFlagsRaw = value
                                case .legacyMode: activeModeRaw = value
                                case .islandMode: activeIslandModeRaw = value
                                case .dockMode: activeDockModeRaw = value
                                case .dockGalleryStyle: activeDockGalleryStyleRaw = value
                                case .springBoardPID: activeSpringBoardPID = value
                                case .islandRed: activeIslandRed = value
                                case .islandGreen: activeIslandGreen = value
                                case .islandBlue: activeIslandBlue = value
                                case .dockRed: activeDockRed = value
                                case .dockGreen: activeDockGreen = value
                                case .dockBlue: activeDockBlue = value
                                }
                            },
                            log: { AuraStudioDiagnostics.log($0, $1) },
                            localizedText: { LaraL10n.text(en: $0, es: $1) },
                            errorMessage: { message(for: $0) },
                            failAfter: { failAfterNativeCall($0, result: $1, userDetail: $2) },
                            finishRollback: { finishVerifiedRollback($0, step: $1, reason: $2) }
                        ).consume(
                            result: result,
                            operation: operation,
                            operationID: operationID,
                            target: operationTarget,
                            requestedMode: requestedProfileMode,
                            step: step,
                            index: index,
                            previouslyVerified: previouslyVerified,
                            springBoardPID: springBoardPID,
                            mode: mode,
                            redValue: redValue,
                            greenValue: greenValue,
                            blueValue: blueValue,
                            complete: { completeSuccess(deadlineWarning: $0) },
                            runNext: { runStep($0) }
                        )
                    }
                }
            }
        }

        runStep(0)
    }

    private var requestAdmission: EagleAuraStudioRequestAdmission {
        EagleAuraStudioRequestAdmission(
            localSafetyBlocked: { applySafetyBlocked },
            remoteSafetyLocked: { mgr.rcSafetyLocked },
            operationInProgress: { isApplying },
            beginGate: { AuraStudioApplyGate.begin() },
            islandCanAttempt: { islandCompatibility.canAttemptLiveIslandAura },
            islandUnavailableMessage: { islandHardwareUnavailableMessage },
            debuggerAttached: { isdebugged() },
            accessReady: { mgr.dsready },
            readSelectedTarget: { selectedTarget },
            flagForTarget: { flag(for: $0) },
            allowsMode: { policyAllows($0, for: $1) },
            modeTitle: { $0.title },
            channelTitle: { releaseChannel.title },
            errorMessage: { message(for: $0) },
            localizedText: { LaraL10n.text(en: $0, es: $1) },
            log: { AuraStudioDiagnostics.log($0, $1) },
            showNotice: { notice = AuraStudioNotice(message: $0) },
            finish: { finish(message: $0) }
        )
    }

    private func makeDiagnosticsReport(summary: String) -> URL? {
        EagleAuraStudioDiagnosticsReport(
            now: { Date() },
            readLogs: { globallogger.logs },
            makeHeader: { timestamp, summary in
                [
                    "Eagle Aura Studio diagnostics",
                    "timestamp=\(timestamp)",
                    "engine=\(auraEngineBuild)",
                    "operation=\(activeOperationID ?? "none")",
                    "operationKind=\(operationIsRemoval ? "remove" : "apply")",
                    "operationStep=\(operationStepIndex)/\(operationStepCount)",
                    "summary=\(summary)",
                    "device=\(devicemachine())",
                    "islandHardware=\(islandCompatibility.diagnosticsToken)",
                    "ios=\(ProcessInfo.processInfo.operatingSystemVersionString)",
                    "dsready=\(mgr.dsready)",
                    "rcrunning=\(mgr.rcrunning)",
                    "rcready=\(mgr.rcready)",
                    "rcSafetyLocked=\(mgr.rcSafetyLocked)",
                    "rcError=\(mgr.rcLastError ?? "none")",
                    "selectedTarget=\(selectedTarget.title)",
                    "islandDraft=mode:\(islandModeRaw) rgb:\(rgb255String(islandRed, islandGreen, islandBlue))",
                    "dockDraft=mode:\(dockModeRaw) rgb:\(rgb255String(dockRed, dockGreen, dockBlue))",
                    "selectedFlags=0x\(String(selectedFlags, radix: 16))",
                    "activeFlags=0x\(String(EagleStoredThemeValues.flags(activeFlagsRaw) & deviceSupportedFlags, radix: 16))",
                    "activeIsland=mode:\(activeIslandModeRaw) rgb:\(activeIslandRed),\(activeIslandGreen),\(activeIslandBlue)",
                    "activeDock=mode:\(activeDockModeRaw) rgb:\(activeDockRed),\(activeDockGreen),\(activeDockBlue)",
                    "activeSpringBoardPID=\(activeSpringBoardPID)",
                    "currentSpringBoardPID=\("SpringBoard".withCString { find_process_pid($0) })",
                    "displayZoomed=\(displayGeometry.isDisplayZoomed)",
                    "displayFactor=\(String(format: "%.4f,%.4f", displayGeometry.xFactor, displayGeometry.yFactor))",
                    "--- filtered log ---",
                ]
            },
            temporaryDirectory: { FileManager.default.temporaryDirectory },
            writeReport: { try $0.write(to: $1, atomically: true, encoding: .utf8) },
            log: { AuraStudioDiagnostics.log($0, $1) }
        ).makeDiagnosticsReport(summary: summary)
    }

    private func finish(message: String) {
        operationUI.finish(message: message)
    }

    private var operationUI: EagleAuraStudioOperationUI {
        EagleAuraStudioOperationUI(
            writeApplying: { isApplying = $0 },
            writeRemoval: { operationIsRemoval = $0 },
            writeStepIndex: { operationStepIndex = $0 },
            writeStepCount: { operationStepCount = $0 },
            writeOperationID: { activeOperationID = $0 },
            writeStage: { applyStage = $0 },
            localizedText: { LaraL10n.text(en: $0, es: $1) },
            log: { AuraStudioDiagnostics.log($0, $1) },
            scheduleOnMain: { DispatchQueue.main.async(execute: $0) },
            endGate: { AuraStudioApplyGate.end() },
            showNotice: { notice = AuraStudioNotice(message: $0) }
        )
    }

    private func successMessage(
        appliedFlags: UInt32,
        requestedFlags: UInt32,
        restoring: Bool,
        motionDegraded: Bool,
        appliedMode: AuraStudioMode?
    ) -> String {
        resultFeedback.successMessage(
            appliedFlags: appliedFlags,
            requestedFlags: requestedFlags,
            restoring: restoring,
            motionDegraded: motionDegraded,
            appliedMode: appliedMode
        )
    }

    private func message(for result: Int32) -> String {
        resultFeedback.message(for: result)
    }

    private func names(for flags: UInt32) -> [String] {
        resultFeedback.names(for: flags)
    }

    private var resultFeedback: EagleAuraStudioResultFeedback {
        EagleAuraStudioResultFeedback(
            islandFlag: Flag.island,
            screenFlag: Flag.screen,
            batteryFlag: Flag.battery,
            dockFlag: Flag.dock,
            lockFlag: Flag.lock,
            modeTitle: { $0.title },
            localizedText: { LaraL10n.text(en: $0, es: $1) }
        )
    }
}
