import SwiftUI

enum LaraAccessState: Equatable {
    case idle
    case preparing(String, Double?)
#if EAGLE_A18_PREPARE_LAB
    case kernelStageReady(String)
#endif
    case ready
    case failed(String)
}

struct LaraAccessView: View {
    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var state: LaraAccessState = .idle
#if EAGLE_A18_PREPARE_LAB
    @State private var labAttemptLocked = false
#endif

    let compact: Bool
    let onReady: (() -> Void)?

    init(compact: Bool = false, onReady: (() -> Void)? = nil) {
        self.compact = compact
        self.onReady = onReady
    }

    // Presentation only. `mgr.sbxready` still decides readiness and `prepare()` is untouched; these
    // states pace what the card shows so every step reads as the reaction to the one before:
    // touch -> press, release -> ripple + icon kick -> the button becomes the progress -> the icon
    // fills with it -> full: unlock, ring, success -> the button melts and the card settles.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cardSpace
    @State private var showReady = false
    @State private var finishing = false
    @State private var ringBurst = false
    @State private var collapsing = false
    @State private var kick = false
    @State private var rippleOrigin: CGPoint?
    @State private var prepareTouch = EagleTouchAnchor()
    @State private var rippleKey = 0
    @State private var quarter = 0

    var body: some View {
        ZStack {
            if showReady {
                readyContent
                    .transition(.opacity)
            } else {
                preparationContent
                    .transition(.opacity)
            }
        }
        // One card for both states, so its height glides from Prepare to "ready" instead of jumping.
        .padding(compact ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(finishingVisual ? Color.green.opacity(0.45) : EagleVisualTheme.surfaceBorder(for: colorScheme),
                              lineWidth: 1)
        }
        .eagleSurfaceShadow(cornerRadius: 22)
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: showReady)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: collapsing)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: phaseKey)
        .onAppear { showReady = mgr.sbxready }
        .onChange(of: mgr.sbxready) { ready in
            ready ? playFinish() : resetFinish()
        }
        .onChange(of: mgr.dsprogress) { progress in
            if mgr.dsrunning {
                state = .preparing(LaraL10n.text(
                    en: "Preparing device",
                    es: "Preparando el dispositivo"
                ), progress)
            }
            // A light tick at each quarter: the progress is felt, not only seen.
            let reached = Int(min(max(progress, 0), 1) * 4)
            if mgr.dsrunning, reached > quarter, reached < 4 {
                quarter = reached
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .onChange(of: state) { value in
            switch value {
            case .ready:
                EagleNotifications.shared.result(true, title: "Eagle",
                    message: LaraL10n.text(en: "Access is ready", es: "Acceso preparado"))
            case .failed(let message):
                EagleNotifications.shared.result(false, title: "Prepare", message: message)
            default: break
            }
        }
#if EAGLE_A18_PREPARE_LAB
        .onAppear(perform: refreshA18LabAttemptLock)
#endif
    }

    /// Release on the button: firm haptic, a ripple from the touch point, and the icon receives the
    /// impulse a beat later. Then the untouched `prepare()` runs.
    private func tapPrepare() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Where the finger went down (`EagleTouchTracker`; a gesture here would block this very tap).
        rippleOrigin = prepareTouch.lastTouch ?? prepareTouch.center
        quarter = 0
        rippleKey += 1
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { kick = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { kick = false }
                }
            }
        }
        prepare()
    }

    /// Full: the icon unlocks and throws a ring of light, then the button melts away and the same
    /// card settles into its compact "ready" form.
    private func playFinish() {
        guard !showReady else { return }
        if reduceMotion {
            showReady = true
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { finishing = true }
        withAnimation(.easeOut(duration: 0.9)) { ringBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard mgr.sbxready else { return }
            collapsing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard mgr.sbxready else { return }
            showReady = true
            finishing = false
            ringBurst = false
            collapsing = false
        }
    }

    private func resetFinish() {
        finishing = false
        ringBurst = false
        collapsing = false
        showReady = false
        quarter = 0
    }

    /// True from the very frame the engine reports ready until the card settles.
    private var finishingVisual: Bool { finishing || (mgr.sbxready && !showReady) }

    /// What the button and the icon show as progress: full when finishing, the engine's value while
    /// preparing (nil until it reports one), empty otherwise.
    private var displayProgress: Double? {
        if finishingVisual { return 1 }
        if case .preparing(_, let progress) = state { return progress.map { min(max($0, 0), 1) } }
        return isBusy ? nil : 0
    }

    /// Changes whenever the card's content changes, to animate those changes as one.
    private var phaseKey: String {
        if finishingVisual { return "finishing" }
        switch state {
        case .preparing(let message, let progress): return "preparing|\(message)|\(progress == nil)"
        case .failed: return "failed"
        default: return isBusy ? "busy" : "idle"
        }
    }

    private var readyContent: some View {
        HStack(spacing: 12) {
            EagleAccessTile(busy: false, finishing: true, burst: false, level: 1, kick: false)
                .matchedGeometryEffect(id: "tile", in: cardSpace)
            VStack(alignment: .leading, spacing: 2) {
                Text(LaraL10n.text(en: "Eagle is ready", es: "Eagle está lista"))
                    .font(.subheadline.weight(.semibold))
                Text(LaraL10n.text(en: "Device prepared", es: "Dispositivo preparado"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(EagleVisualTheme.secondaryText(for: colorScheme))
            }
            Spacer(minLength: 0)
        }
    }

    private var preparationContent: some View {
        let finishing = finishingVisual
        let progress = displayProgress
        return VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            HStack(spacing: 12) {
                EagleAccessTile(busy: isBusy && !finishing, finishing: finishing, burst: ringBurst,
                                level: progress ?? 0.06, kick: kick)
                    .matchedGeometryEffect(id: "tile", in: cardSpace)

                Text(finishing ? LaraL10n.text(en: "Ready", es: "Listo") : LaraL10n.text(en: "Prepare", es: "Preparar"))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)

                Spacer(minLength: 0)

                if finishing {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else if isBusy {
                    EagleMarkSpinner(size: 24)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }

            if !collapsing {
                if finishing {
                    Text(LaraL10n.text(en: "Device ready", es: "Dispositivo listo"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else {
                    switch state {
                    case .preparing(let message, _):
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(EagleVisualTheme.secondaryText(for: colorScheme))
                            .id(message)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                    removal: .opacity))

                    case .failed:
                        EmptyView()

#if EAGLE_A18_PREPARE_LAB
                    case .kernelStageReady(let message):
                        Label(message, systemImage: "checkmark.shield.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.green)
#endif

                    default:
                        EmptyView()
                    }
                }

                Button(action: tapPrepare) {
                    EaglePrepareButtonLabel(
                        title: finishing ? LaraL10n.text(en: "Ready", es: "Listo") : buttonTitle,
                        progress: progress,
                        busy: isBusy && !finishing,
                        finishing: finishing,
                        rippleOrigin: rippleOrigin,
                        rippleKey: rippleKey)
                }
                .buttonStyle(EaglePrepareButtonStyle())
                .eagleTouchAnchor(prepareTouch)
                .allowsHitTesting(!finishing)
#if EAGLE_A18_PREPARE_LAB
                .disabled(isBusy || isKernelStageReady || labAttemptLocked || isunsupported() || isdebugged())
#else
                .disabled(isBusy || isunsupported() || isdebugged())
#endif
                .transition(.asymmetric(insertion: .opacity,
                                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))))
            }
        }
    }

    private var isBusy: Bool {
        if case .preparing = state { return true }
        return mgr.dsrunning || mgr.sbxrunning
    }

#if EAGLE_A18_PREPARE_LAB
    private var isKernelStageReady: Bool {
        if case .kernelStageReady = state { return true }
        return false
    }
#endif

    private var buttonTitle: String {
        if isBusy { return LaraL10n.text(en: "Preparing…", es: "Preparando…") }
        if isdebugged() { return LaraL10n.text(en: "Disconnect Xcode", es: "Desconecta Xcode") }
#if EAGLE_A18_PREPARE_LAB
        if isA18KernelStageLabRuntime {
            if labAttemptLocked {
                return LaraL10n.text(en: "Lab attempt recorded", es: "Intento de laboratorio registrado")
            }
            return LaraL10n.text(en: "Test kernel stage once", es: "Probar etapa del kernel una vez")
        }
        if isKernelStageReady {
            return LaraL10n.text(en: "Kernel stage verified", es: "Etapa del kernel verificada")
        }
#endif
        if case .failed = state { return LaraL10n.text(en: "Try again", es: "Intentar otra vez") }
        return LaraL10n.text(en: "Prepare iPhone", es: "Preparar iPhone")
    }

    private func prepare() {
        guard !isBusy, !isunsupported(), !isdebugged() else { return }
#if EAGLE_A18_PREPARE_LAB
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let machine = devicemachine()
        let systemBuild = eagleSystemBuild()?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let route = eaglePrepareExecutionRoute(
            version: version,
            machine: machine,
            systemBuild: systemBuild
        )
        if route == .a18KernelStageLab {
            guard let systemBuild else {
                state = .failed(LaraL10n.text(
                    en: "The verified system build could not be read, so the private lab did not run.",
                    es: "No se pudo leer la compilación verificada del sistema, por lo que el laboratorio privado no se ejecutó."
                ))
                return
            }
            prepareA18KernelStageLab(
                route: route,
                machine: machine,
                systemBuild: systemBuild
            )
            return
        }
        if route == .blockedFieldRestart {
            state = .failed(EagleSupportAssessment(
                status: .unsupported,
                reason: .iphone16IOS185FieldRestart
            ).message(spanish: LaraL10n.language == .spanish))
            return
        }
#endif
        state = .preparing(LaraL10n.text(
            en: "Checking compatibility",
            es: "Comprobando compatibilidad"
        ), nil)
        offsets_init()

        if mgr.dsready {
            resolveOffsetsAndOpenSandbox()
            return
        }

        mgr.run { success in
            guard success else {
                state = .failed(LaraL10n.text(
                    en: "The device could not be prepared. You can try again.",
                    es: "No se pudo preparar el dispositivo. Puedes intentarlo de nuevo."
                ))
                return
            }
            resolveOffsetsAndOpenSandbox()
        }
    }

#if EAGLE_A18_PREPARE_LAB
    private func prepareA18KernelStageLab(
        route: EaglePrepareExecutionRoute,
        machine: String,
        systemBuild: String
    ) {
        guard !labAttemptLocked else {
            state = .failed(LaraL10n.text(
                en: "This private lab already recorded an attempt for this iPhone and build.",
                es: "Este laboratorio privado ya registró un intento para este iPhone y esta compilación."
            ))
            return
        }
        guard !UserDefaults.standard.bool(forKey: "stashKRW") else {
            state = .failed(LaraL10n.text(
                en: "Turn off Stash KRW primitives in Settings and restart Eagle before this isolated test. Nothing was run.",
                es: "Desactiva Guardar primitivas KRW en Ajustes y reinicia Eagle antes de esta prueba aislada. No se ejecutó nada."
            ))
            return
        }
        let beginResult = EaglePrepareAttemptJournal.begin(
            route: route.rawValue,
            machine: machine,
            systemBuild: systemBuild
        )
        let attemptID: String
        switch beginResult {
        case .started(let identifier):
            attemptID = identifier
        case .alreadyRecorded:
            labAttemptLocked = true
            state = .failed(LaraL10n.text(
                en: "This private lab already recorded an attempt for this iPhone and build.",
                es: "Este laboratorio privado ya registró un intento para este iPhone y esta compilación."
            ))
            return
        case .unavailable:
            state = .failed(LaraL10n.text(
                en: "Eagle could not create the durable test record, so the kernel stage was not started.",
                es: "Eagle no pudo crear el registro duradero de la prueba, por lo que no inició la etapa del kernel."
            ))
            return
        }
        labAttemptLocked = true
        state = .preparing(LaraL10n.text(
            en: "Testing the isolated kernel stage",
            es: "Probando la etapa aislada del kernel"
        ), nil)
        offsets_init()
        EaglePrepareAttemptJournal.mark(attemptID, stage: .offsetsInitialized)

        if mgr.dsready {
            guard hasVerifiedA18LabPrimitive else {
                EaglePrepareAttemptJournal.finish(
                    attemptID,
                    succeeded: false,
                    detail: "ready flag was set without complete proc/task/kernel-base references"
                )
                state = .failed(LaraL10n.text(
                    en: "The kernel stage was incomplete. Do not retry; share a Prepare report.",
                    es: "La etapa del kernel quedó incompleta. No lo repitas; comparte un reporte de Preparar."
                ))
                mgr.quarantineRemoteCall(
                    reason: "A18 lab rejected incomplete kernel primitive references"
                )
                return
            }
            EaglePrepareAttemptJournal.finish(
                attemptID,
                succeeded: true,
                detail: "reused verified primitive; sandbox was not started"
            )
            state = .kernelStageReady(LaraL10n.text(
                en: "Kernel access was already ready. Sandbox was not started in this lab.",
                es: "El acceso al kernel ya estaba listo. El laboratorio no abrió el sandbox."
            ))
            mgr.quarantineRemoteCall(
                reason: "A18 kernel-stage lab stops before RemoteCall and sandbox"
            )
            return
        }

        EaglePrepareAttemptJournal.mark(attemptID, stage: .darkSwordRunning)
        mgr.run { success in
            guard success, hasVerifiedA18LabPrimitive else {
                EaglePrepareAttemptJournal.finish(
                    attemptID,
                    succeeded: false,
                    detail: success
                        ? "DarkSword ready flag lacked complete proc/task/kernel-base references"
                        : "DarkSword returned without a verified primitive"
                )
                state = .failed(LaraL10n.text(
                    en: "The isolated kernel stage failed. Do not retry; share a Prepare report.",
                    es: "Falló la etapa aislada del kernel. No lo repitas; comparte un reporte de Preparar."
                ))
                if success {
                    mgr.quarantineRemoteCall(
                        reason: "A18 lab rejected incomplete kernel primitive references"
                    )
                }
                return
            }

            EaglePrepareAttemptJournal.finish(
                attemptID,
                succeeded: true,
                detail: "kernel primitive verified; compatibility data and sandbox were intentionally skipped"
            )
            state = .kernelStageReady(LaraL10n.text(
                en: "Kernel stage verified. This lab intentionally skipped compatibility data and sandbox access.",
                es: "Etapa del kernel verificada. Este laboratorio omitió intencionalmente los datos de compatibilidad y el acceso al sandbox."
            ))
            mgr.quarantineRemoteCall(
                reason: "A18 kernel-stage lab stops before RemoteCall and sandbox"
            )
        }
    }

    private var hasVerifiedA18LabPrimitive: Bool {
        ds_get_our_proc() != 0 &&
            ds_get_our_task() != 0 &&
            ds_get_kernel_base() != 0
    }

    private var isA18KernelStageLabRuntime: Bool {
        eaglePrepareExecutionRoute(
            version: ProcessInfo.processInfo.operatingSystemVersion,
            machine: devicemachine(),
            systemBuild: eagleSystemBuild()
        ) == .a18KernelStageLab
    }

    private func refreshA18LabAttemptLock() {
        guard isA18KernelStageLabRuntime,
              let build = eagleSystemBuild()?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !build.isEmpty else {
            labAttemptLocked = false
            return
        }
        labAttemptLocked = EaglePrepareAttemptJournal.hasRecordedAttempt(
            route: EaglePrepareExecutionRoute.a18KernelStageLab.rawValue,
            machine: devicemachine(),
            systemBuild: build
        )
    }
#endif

    private func resolveOffsetsAndOpenSandbox() {
        if mgr.hasOffsets {
            openSandbox()
            return
        }

        state = .preparing(LaraL10n.text(
            en: "Getting compatibility data for your iPhone",
            es: "Obteniendo compatibilidad para tu iPhone"
        ), nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = fetchkcache()
            let loaded = fetched && dlkcache()
            DispatchQueue.main.async {
                mgr.hasOffsets = loaded
                if loaded {
                    openSandbox()
                } else {
                    state = .failed(LaraL10n.text(
                        en: "Compatibility data could not be prepared.",
                        es: "No fue posible preparar los datos de compatibilidad."
                    ))
                }
            }
        }
    }

    private func openSandbox() {
        state = .preparing(LaraL10n.text(
            en: "Opening temporary access",
            es: "Abriendo acceso temporal"
        ), nil)
        mgr.sbxescape { success in
            if success {
                state = .ready
                onReady?()
            } else {
                state = .failed(LaraL10n.text(
                    en: "Temporary access could not be started.",
                    es: "El acceso temporal no pudo iniciarse."
                ))
            }
        }
    }
}

/// Prepare's icon tile. Green rises inside it with the progress (the same level the button shows),
/// it breathes while working, takes the tap's impulse as a small jump, unlocks into a check when full
/// and throws a ring of light at that moment.
private struct EagleAccessTile: View {
    let busy: Bool
    let finishing: Bool
    let burst: Bool
    let level: Double
    let kick: Bool

    var body: some View {
        // 60 fps while preparing (a small tile, cheap to draw): the liquid's wave stepped at 30.
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !busy)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = busy ? (sin(t * 2.6) + 1) / 2 : 0
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.14))
                EagleLiquid(level: finishing ? 1 : level, phase: busy ? t * 3.2 : 0, wave: busy ? 2 : 0)
                    .fill(Color.green.opacity(finishing ? 0.3 : 0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: level)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.green.opacity(0.45 * (1 - breath)), lineWidth: 1.5)
                    .scaleEffect(1 + 0.22 * breath)
                    .opacity(busy ? 1 : 0)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.green.opacity(burst ? 0 : 0.6), lineWidth: 2)
                    .scaleEffect(burst ? 1.9 : 1)
                    .opacity(finishing ? 1 : 0)
                EagleAccessSymbol(name: finishing ? "checkmark.shield.fill" : "lock.shield.fill", bounce: finishing)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.green)
                    .scaleEffect(1 + 0.05 * breath)
            }
            .frame(width: 42, height: 42)
            .scaleEffect(kick ? 1.14 : 1)
        }
    }
}

/// Liquid surface for the tile: fills from the bottom to `level`, with a gentle wave on top.
private struct EagleLiquid: Shape {
    var level: Double
    var phase: Double
    var wave: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = rect.maxY - rect.height * CGFloat(min(max(level, 0), 1))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 24
        for i in 0...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let y = top + CGFloat(wave * sin(phase + Double(i) / Double(steps) * .pi * 2))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The Prepare button's face, monochrome with the system appearance: white with black text in dark
/// mode, black with white text in light mode. Once tapped it becomes the progress: the fill grows from
/// the left with the percentage. The title takes the contrasting
/// colour over the fill and over the track, so the fill reads through it.
private struct EaglePrepareButtonLabel: View {
    let title: String
    let progress: Double?
    let busy: Bool
    let finishing: Bool
    let rippleOrigin: CGPoint?
    let rippleKey: Int
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var rippleScale: CGFloat = 0

    /// One motion for the fill and the text cut that follows it, so they always move together.
    private static let fillAnimation = Animation.spring(response: 0.6, dampingFraction: 0.92)

    private var dark: Bool { colorScheme == .dark }
    /// Button and fill colour: white on a dark system, black on a light one.
    private var fill: Color { dark ? .white : .black }
    private var onFill: Color { dark ? .black : .white }
    private var track: Color { dark ? Color(white: 0.23) : Color(white: 0.86) }
    private var onTrack: Color { dark ? .white : .black }
    @State private var rippleOpacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let filled = busy ? width * CGFloat(progress ?? 0) : width
            ZStack(alignment: .leading) {
                Capsule().fill(busy ? track : fill)
                // The fill is a straight-edged level inside the rounded track (the track's own corners
                // round it on the left), exactly the shape the inverse text below is cut with, so the
                // text never sits white on white and a small value never turns into a round blob.
                if busy {
                    Rectangle().fill(fill)
                        .frame(width: filled)
                        .animation(Self.fillAnimation, value: filled)
                }
                if let rippleOrigin {
                    Circle()
                        .fill(dark ? Color.black.opacity(0.16) : Color.white.opacity(0.32))
                        .frame(width: width * 2.2, height: width * 2.2)
                        .scaleEffect(rippleScale)
                        .opacity(rippleOpacity)
                        .position(rippleOrigin)
                }
                face(onTrack)
                face(onFill)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: filled)
                            .animation(Self.fillAnimation, value: filled)
                    }
            }
            .clipShape(Capsule())
        }
        .frame(height: 52)
        .opacity(!isEnabled && !busy && !finishing ? 0.45 : 1)
        .onChange(of: rippleKey) { _ in
            rippleScale = 0.04
            rippleOpacity = 1
            withAnimation(.easeOut(duration: 0.6)) {
                rippleScale = 1
                rippleOpacity = 0
            }
        }
    }

    private func face(_ color: Color) -> some View {
        HStack(spacing: 6) {
            if finishing {
                Image(systemName: "checkmark")
                    .transition(.scale.combined(with: .opacity))
            }
            // A new title slides in from below as the old one leaves upward, never overlapping.
            Text(title)
                .id(title)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
            if busy, let progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: Int((progress * 100).rounded()))
            }
        }
        .font(.headline)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: title)
    }
}

/// Touch-down reaction: the button gives under the finger and brightens, with a soft haptic,
/// before the release fires the action.
private struct EaglePrepareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EaglePrepareButtonPress(configuration: configuration)
    }
}

private struct EaglePrepareButtonPress: View {
    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? 0.07 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
            }
    }
}

/// SF Symbol that swaps with the system's replace effect and bounces when `bounce` turns true
/// (iOS 17+); a plain crossfade on iOS 16.
private struct EagleAccessSymbol: View {
    let name: String
    let bounce: Bool

    var body: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: name)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounce)
        } else {
            Image(systemName: name)
                .id(name)
                .transition(.opacity)
        }
    }
}
