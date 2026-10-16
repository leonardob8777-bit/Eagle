import SwiftUI
import WebKit
import Combine
import AVFoundation

struct EagleBeta10WelcomeView: View {
    @State private var showingTelegram = false
    let onContinue: () -> Void
    /// Called as the welcome starts dissolving, so the host can settle the app underneath.
    var onReveal: () -> Void = {}

    @AppStorage(LaraLanguage.storageKey) private var language = LaraLanguage.english
    private let colorScheme: ColorScheme = .dark

    private var support: EagleSupportAssessment {
        eagleSupportAssessment()
    }

    private var deviceName: String {
        EagleDeviceIdentity.displayName(for: devicemachine())
    }

    private var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return [version.majorVersion, version.minorVersion, version.patchVersion]
            .map(String.init)
            .joined(separator: ".")
    }

    /// The welcome is laid out edge to edge (its host ignores the safe area), so the geometry reports no
    /// insets; the window's own top inset, read once it is on screen, keeps the title clear of the
    /// Dynamic Island.
    @State private var windowTopInset: CGFloat = 0

    /// Smoothstep opacity from clear to opaque, so the top of the cards fades without a line.
    private static let cardsFadeStops: [Gradient.Stop] = (0...12).map { i in
        let u = Double(i) / 12
        return .init(color: Color.black.opacity(u * u * (3 - 2 * u)), location: u)
    }

    @StateObject private var scene = EagleWelcomeSceneController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Get started: gathering (the cards settle) -> exiting (the cards fall away while the mark takes off)
    // -> opening (as the mark rises away, a circle opens from Get started and the app shows through it,
    // already in place, until the welcome is gone; nothing lands on top afterwards).
    // With Reduce Motion: settling (the app's backdrop covers the scene) -> dissolving (it clears onto the
    // app). The scene itself is never faded: a web view faded over the app shows a grey veil for a moment.
    @State private var gathering = false
    @State private var exiting = false
    @State private var settling = false
    @State private var sceneRetired = false
    @State private var dissolving = false
    /// 0 = welcome whole, 1 = the circle from Get started has opened over the whole screen.
    @State private var opening: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let revealDistance = max(300, geometry.size.height * 0.42 + 24)
            let lift = 1 - pow(1 - min(1, max(0, scrollOffset) / revealDistance), 2)
            ZStack {
                ZStack(alignment: .top) {
                    if !sceneRetired {
                        EagleWelcomeSceneView(controller: scene, offset: scrollOffset * 300 / revealDistance,
                                              progress: scrollProgress, active: scenePhase == .active)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    if !scene.finished,
                       let movieURL = Bundle.main.url(forResource: "EagleWelcomeIntro", withExtension: "mp4") {
                        EagleWelcomeMovieView(url: movieURL, active: scenePhase == .active) {
                            scene.movieDidEnd()
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }

                    // Flattened before fading: otherwise its black base and its gradient fade separately and
                    // the base dims the background halfway through. When it is the scene's own background it
                    // simply fades in; when the background really changes (light appearance, backdrop off)
                    // it opens in a circle from Get started, like the backdrop switch does.
                    EagleBackdrop()
                        .ignoresSafeArea()
                        .compositingGroup()
                        .modifier(EagleBackdropReveal(progress: settling ? 1 : 0, origin: nil))
                        // Flattened again after the circle's mask, or the fade below reaches the layers
                        // inside it separately and lightens the top as the app appears (light mode).
                        .compositingGroup()
                        .opacity(dissolving ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    Text(LaraL10n.text(en: "Updates", es: "Actualizaciones"))
                        .font(.headline)
                        .foregroundStyle(Color(white: 0.14))
                        .padding(.top, max(geometry.safeAreaInsets.top, windowTopInset) + 10)
                        .opacity(scene.finished && !exiting ? Double(lift) : 0)
                        .accessibilityHidden(lift == 0)

                    EagleWelcomeScroll(offset: $scrollOffset, progress: $scrollProgress,
                                       enabled: scene.finished && !exiting) {
                        VStack(spacing: 18) {
                            Color.clear.frame(height: revealDistance).accessibilityHidden(true)
                            // The cards enter the screen with the first points of scroll, before the scene's
                            // dark gradient has risen; they appear only once that gradient sits behind them.
                            Group {
                                currentDeviceCard
                                updatesCard
                                fixesCard
                                compatibilityCard
                            }
                            .opacity(min(1, max(0, (Double(lift) - 0.28) / 0.14)))
                            Button(action: finishWelcome) {
                                Text(LaraL10n.text(en: "Get started", es: "Empezar"))
                                    .font(.headline)
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(EagleApplyButtonStyle(fill: nil))
                            .disabled(!scene.finished || gathering || exiting)
                            .accessibilityIdentifier("eagle.welcome.start")
                            // Eagle's Telegram, under Get started, opening in Safari inside Eagle.
                            EagleTelegramButton { showingTelegram = true }
                                .disabled(!scene.finished || gathering || exiting)
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(30, geometry.safeAreaInsets.bottom + 16))
                        .environment(\.colorScheme, .dark)
                        .environment(\.locale, language.locale)
                    }
                    .padding(.top, geometry.size.height * (0.58 - 0.18 * lift))
                    .mask(alignment: .top) {
                        // A tall, eased fade: the cards dissolve into the dark as they scroll up, with no
                        // visible edge where the list ends.
                        VStack(spacing: 0) {
                            LinearGradient(stops: Self.cardsFadeStops, startPoint: .top, endPoint: .bottom)
                                .frame(height: 110)
                            Color.black
                        }
                        .padding(.top, geometry.size.height * (0.58 - 0.18 * lift))
                    }
                    .offset(y: gathering && !exiting ? 8 : 0)
                    .scaleEffect(exiting && !reduceMotion ? 0.94 : 1)
                    .blur(radius: exiting && !reduceMotion ? 10 : 0)
                    .opacity(scene.finished ? (exiting ? 0 : gathering ? 0.82 : 1) : 0)
                    .accessibilityHidden(!scene.finished)

                    // Tells the user the welcome continues below; it fades away as soon as they scroll.
                    EagleSwipeHint()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 34)
                        .opacity(scene.finished && !exiting ? max(0, 1 - Double(lift) * 5) : 0)
                        .offset(y: scene.finished ? -Double(lift) * 40 : 12)
                        .animation(.easeOut(duration: 0.7).delay(0.6), value: scene.finished)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .background {
                    // Off at once when the welcome dissolves: the backdrop above still covers it, and
                    // fading it too would dim the shared background halfway through.
                    Color.black
                        .opacity(dissolving ? 0 : 1)
                        .transaction { $0.animation = nil }
                }
                .modifier(EagleWelcomeOpening(
                    progress: opening,
                    // Get started, now with the Telegram button below it.
                    origin: CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 146)
                ))
                .allowsHitTesting(!gathering)
            }
            .accessibilityIdentifier("eagle.welcome")
            .onAppear {
                scene.active = scenePhase == .active
                let windows = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                windowTopInset = (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets.top ?? 0
            }
        }
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showingTelegram) {
            TelegramSafariView(url: EagleLinks.telegram)
                .ignoresSafeArea()
        }
    }

    private func finishWelcome() {
        guard scene.finished, !gathering, !exiting else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if reduceMotion {
            gathering = true
            withAnimation(.easeInOut(duration: 0.3)) { exiting = true }
            coverScene(lasting: 0.3) { revealApp(lasting: 0.3) }
            return
        }
        // The real 3D mark dips, then takes off with the brand shine (EagleWelcomeScene.html, ~0.95 s).
        scene.takeOff()
        withAnimation(.easeOut(duration: 0.22)) { gathering = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
            withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 0.36)) { exiting = true }
        }
        // As the mark rises away, a circle opens from Get started and the app shows through it, already
        // in place (its content landed under the welcome at launch), until the welcome is gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            onReveal()
            animate(.timingCurve(0.45, 0, 0.25, 1, duration: 0.75), lasting: 0.75, { opening = 1 }) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                onContinue()
            }
        }
    }

    /// Fades the backdrop in over the scene, then calls `covered` once it really covers it on screen.
    private func coverScene(lasting duration: Double, covered: @escaping () -> Void) {
        animate(.easeInOut(duration: duration), lasting: duration, { settling = true }, then: covered)
    }

    /// The scene is covered: it goes, and the welcome clears onto the app, whose background is the same.
    private func revealApp(lasting duration: Double) {
        sceneRetired = true
        onReveal()
        animate(.timingCurve(0.3, 0, 0.2, 1, duration: duration), lasting: duration, { dissolving = true }) {
            if !reduceMotion { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55) }
            onContinue()
        }
    }

    /// Runs `changes` with `animation` and calls `then` when the animation has finished on screen. Timers
    /// alone drift behind the animation when the WebGL scene keeps the main thread busy; before iOS 17
    /// a timer with some margin is the fallback.
    private func animate(_ animation: Animation, lasting duration: Double, _ changes: () -> Void,
                         then: @escaping () -> Void) {
        if #available(iOS 17.0, *) {
            withAnimation(animation, completionCriteria: .removed, changes, completion: then)
        } else {
            withAnimation(animation, changes)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.12, execute: then)
        }
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            LinearGradient(
                colors: [Color.primary.opacity(0.055), .clear, .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                EagleWordmark(logoSize: 58, nameSize: 34, spacing: 12)

                Text(LaraL10n.text(
                    en: "A more polished Eagle.",
                    es: "Una Eagle más pulida."
                ))
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.6")  •  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "95")")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(EagleVisualTheme.secondaryText(for: colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.065), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(EagleVisualTheme.surfaceBorder(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: EagleVisualTheme.surfaceShadow(for: colorScheme), radius: 18, y: 8)
    }

    private var currentDeviceCard: some View {
        welcomeCard {
            HStack(spacing: 13) {
                Image(systemName: supportSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(supportColor)
                    .frame(width: 42, height: 42)
                    .background(supportColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LaraL10n.text(en: "This device", es: "Este dispositivo"))
                                .font(.headline)
                                .fixedSize()
                            Spacer(minLength: 8)
                            supportBadge
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LaraL10n.text(en: "This device", es: "Este dispositivo"))
                                .font(.headline)
                            supportBadge
                        }
                    }

                    Text("\(deviceName) · iOS \(systemVersion)")
                        .font(.subheadline.weight(.medium))

                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var supportBadge: some View {
        Text(supportTitle)
            .font(.caption.weight(.bold))
            .foregroundStyle(supportColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(supportColor.opacity(0.13), in: Capsule())
            .fixedSize()
    }

    private var updatesCard: some View {
        welcomeCard {
            welcomeSectionTitle(
                "Eagle \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.6")",
                systemImage: "sparkles",
                color: .primary
            )
            welcomeRow(
                icon: "character.bubble",
                color: .primary,
                title: LaraL10n.text(en: "Simplified Chinese", es: "Chino simplificado"),
                detail: LaraL10n.text(
                    en: "Choose 简体中文 from the language menu. Interface text updates without reopening Eagle.",
                    es: "Elige 简体中文 en el menú de idioma. La interfaz cambia sin volver a abrir Eagle."
                )
            )

            welcomeRow(
                icon: "sparkles",
                color: .primary,
                title: LaraL10n.text(en: "A new arrival", es: "Una nueva entrada"),
                detail: LaraL10n.text(
                    en: "A new logo opening and a circular reveal from Get started, with smoother transitions.",
                    es: "Nueva apertura con el logo y entrada circular desde Empezar, con transiciones más suaves."
                )
            )

            welcomeRow(
                icon: "rectangle.bottomthird.inset.filled",
                color: .primary,
                title: LaraL10n.text(en: "Actions within reach", es: "Acciones a mano"),
                detail: LaraL10n.text(
                    en: "Fixed Apply and Prepare controls. Dock Gallery now shares Island Gallery’s control layout.",
                    es: "Aplicar y Preparar quedan a mano. Dock Gallery comparte la distribución de controles de Island Gallery."
                )
            )

            welcomeRow(
                icon: "photo.stack",
                color: .primary,
                title: LaraL10n.text(en: "31 new Dock backgrounds", es: "31 nuevos fondos de Dock"),
                detail: LaraL10n.text(
                    en: "18 Static and 13 Live themes, downloaded from the gallery when you choose them.",
                    es: "18 temas Static y 13 Live que se descargan desde la galería cuando los eliges."
                )
            )
        }
    }

    private var fixesCard: some View {
        welcomeCard {
            welcomeSectionTitle(
                LaraL10n.text(en: "Polished details", es: "Detalles mejorados"),
                systemImage: "checkmark.circle",
                color: .primary
            )
            welcomeRow(
                icon: "iphone",
                color: .primary,
                title: LaraL10n.text(en: "Clearer controls", es: "Controles más claros"),
                detail: LaraL10n.text(
                    en: "Solid preview buttons, readable disabled actions and unclipped switches. Clearer text over the gradient.",
                    es: "Botones de vista previa sólidos, acciones desactivadas legibles e interruptores sin recortes. Textos más claros sobre el degradado."
                )
            )

            welcomeRow(
                icon: "hand.tap",
                color: .primary,
                title: LaraL10n.text(en: "Touch and motion", es: "Toques y movimiento"),
                detail: LaraL10n.text(
                    en: "Smoother tabs and scrolling, clearer Prepare progress and a unified loading ring. Hidden effects pause.",
                    es: "Pestañas y desplazamiento más fluidos, progreso de Preparar más claro y un mismo aro de carga. Los efectos ocultos se pausan."
                )
            )
        }
    }

    private var compatibilityCard: some View {
        welcomeCard {
            Text(LaraL10n.text(
                en: "This update does not add support for new iOS versions. Check your device in Access → Compatibility.",
                es: "Esta actualización no añade soporte para nuevas versiones de iOS. Consulta tu dispositivo en Acceso → Compatibilidad."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var referenceDeviceCard: some View {
        welcomeCard {
            welcomeSectionTitle(
                LaraL10n.text(en: "Reference device", es: "Dispositivo de referencia"),
                systemImage: "iphone.gen3",
                color: .cyan
            )

            Text("iPhone 16 Pro · iOS 18.6.2 (22G100)")
                .font(.headline)

            Text(LaraL10n.text(
                en: "Physical reference for development. Results can vary by device and iOS version.",
                es: "Referencia física de desarrollo. Los resultados pueden variar según el dispositivo y la versión de iOS."
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var safetyNote: some View {
        Label {
            Text(LaraL10n.text(
                en: "Back up important data, apply one feature at a time, and stop after any reboot, timeout, or protected-call error. You can review compatibility again from Eagle Home.",
                es: "Respalda tus datos importantes, aplica una función a la vez y detente ante cualquier reinicio, espera agotada o error de llamada protegida. Puedes volver a revisar la compatibilidad desde Inicio."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 4)
    }

    private func welcomeCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .padding(17)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(EagleVisualTheme.surfaceBorder(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: EagleVisualTheme.surfaceShadow(for: colorScheme), radius: 12, y: 5)
    }

    private func welcomeSectionTitle(
        _ title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }

    private func welcomeRow(
        icon: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func compatibilityRow(
        status: String,
        range: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(range)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Text(status)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private var supportTitle: String {
        switch support.status {
        case .possible:
            return LaraL10n.text(en: "LIMITED TEST", es: "PRUEBA LIMITADA")
        case .testedNeedsMoreTesting:
            return LaraL10n.text(en: "LIMITED TEST", es: "PRUEBA LIMITADA")
        case .supported:
            return LaraL10n.text(en: "SUPPORTED", es: "COMPATIBLE")
        case .unsupported:
            return LaraL10n.text(en: "BLOCKED", es: "BLOQUEADO")
        }
    }

    private var supportColor: Color {
        switch support.status {
        case .possible, .testedNeedsMoreTesting: return .orange
        case .supported: return .green
        case .unsupported: return .red
        }
    }

    private var supportSymbol: String {
        switch support.status {
        case .possible, .testedNeedsMoreTesting: return "exclamationmark.shield.fill"
        case .supported: return "checkmark.shield.fill"
        case .unsupported: return "xmark.shield.fill"
        }
    }
}

#Preview {
    EagleBeta10WelcomeView(onContinue: {})
}

/// Opens a soft-edged hole in the welcome that grows from `origin` (Get started) until the app
/// underneath shows through entirely.
private struct EagleWelcomeOpening: ViewModifier, Animatable {
    var progress: Double
    let origin: CGPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { proxy in
                let size = proxy.size
                let reach = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height),
                             CGPoint(x: size.width, y: size.height)]
                    .map { hypot($0.x - origin.x, $0.y - origin.y) }
                    .max() ?? 0
                let feather: CGFloat = 90
                let radius = max((reach + feather) * progress, 0.5)
                if progress <= 0 {
                    Color.black
                } else {
                    RadialGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: max(0, 1 - feather / max(radius, feather))),
                            .init(color: .black, location: 1)
                        ],
                        center: UnitPoint(x: origin.x / max(size.width, 1), y: origin.y / max(size.height, 1)),
                        startRadius: 0,
                        endRadius: radius
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct EagleSwipeHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var sweep = false
    private let label = LaraL10n.text(en: "Swipe up", es: "Desliza hacia arriba")

    var body: some View {
        VStack(spacing: 10) {
            // Two system grabber chevrons that light up in turn, leading the eye upward.
            VStack(spacing: -1) {
                Image(systemName: "chevron.compact.up")
                    .opacity(reduceMotion ? 0.9 : (pulse ? 0.95 : 0.3))
                Image(systemName: "chevron.compact.up")
                    .opacity(reduceMotion ? 0.45 : (pulse ? 0.3 : 0.95))
            }
            .font(.system(size: 24, weight: .medium))
            .offset(y: reduceMotion ? 0 : (pulse ? -3 : 2))

            // The caption carries a soft light sweep, in the spirit of slide-to-unlock.
            Text(label)
                .font(.footnote.weight(.semibold))
                .tracking(0.3)
                .foregroundStyle(Color(white: 0.52))
                .overlay {
                    if !reduceMotion {
                        Text(label)
                            .font(.footnote.weight(.semibold))
                            .tracking(0.3)
                            .foregroundStyle(Color(white: 0.12))
                            .mask {
                                GeometryReader { proxy in
                                    LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: proxy.size.width * 0.55)
                                        .offset(x: sweep ? proxy.size.width * 1.05 : -proxy.size.width * 0.6)
                                }
                            }
                    }
                }
        }
        .foregroundStyle(Color(white: 0.28))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 2.6).delay(0.4).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}

// The WebGL scene and native content share a single uninterrupted welcome surface.
private final class EagleWelcomeSceneController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var finished = false
    weak var webView: WKWebView?
    var active = true
    private var movieEnded = false
    private var sceneDrawn = false

    /// Starts the mark's take-off in the WebGL scene.
    func takeOff() {
        webView?.evaluateJavaScript("window.eagleExit?.()", completionHandler: nil)
    }

    /// The movie has played to its end. Its last frame is the live scene's first, so it stays on screen
    /// until the scene reports it is drawing. A scene that finishes loading after the movie gets the call
    /// again when it loads; before, it missed it and stayed frozen and white behind the cards.
    func movieDidEnd() {
        movieEnded = true
        startLiveScene()
        settleIfReady()
        // Never leave the welcome waiting on a scene that cannot draw.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
        }
    }

    private func startLiveScene() {
        webView?.evaluateJavaScript("window.eagleMovieDidFinish?.()", completionHandler: nil)
    }

    private func settleIfReady() {
        if movieEnded, sceneDrawn, !finished { finished = true }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if movieEnded { startLiveScene() }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "eagleIntro", let body = message.body as? String else { return }
        switch body {
        case "finished": finished = true
        case "drawn":
            sceneDrawn = true
            settleIfReady()
        default: break
        }
    }
}

private struct EagleWelcomeSceneView: UIViewRepresentable {
    let controller: EagleWelcomeSceneController
    let offset: CGFloat
    let progress: CGFloat
    let active: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if Bundle.main.url(forResource: "EagleWelcomeIntro", withExtension: "mp4") != nil {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.eagleUsesNativeMovie=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
        }
        configuration.userContentController.add(controller, name: "eagleIntro")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(white: 0.96, alpha: 1)
        view.scrollView.isScrollEnabled = false
        // Full-bleed like the intro movie, so the mark does not shift by the safe area at handoff.
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isUserInteractionEnabled = false
        view.navigationDelegate = controller
        controller.webView = view
        if let url = Bundle.main.url(forResource: "EagleWelcomeScene", withExtension: "html") {
            // With the native movie playing first, the WebGL scene is only needed when it ends;
            // loading it a moment later keeps the movie's first second free of that work.
            let hasMovie = Bundle.main.url(forResource: "EagleWelcomeIntro", withExtension: "mp4") != nil
            DispatchQueue.main.asyncAfter(deadline: .now() + (hasMovie ? 0.5 : 0)) { [weak view] in
                view?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        controller.active = active
        view.evaluateJavaScript("window.eagleUpdate?.(\(Double(offset)),\(Double(progress)),\(active ? "true" : "false"))", completionHandler: nil)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "eagleIntro")
        view.stopLoading()
    }
}

private struct EagleWelcomeScroll<Content: View>: UIViewControllerRepresentable {
    @Binding var offset: CGFloat
    @Binding var progress: CGFloat
    let enabled: Bool
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> EagleWelcomeScrollController {
        let controller = EagleWelcomeScrollController(content: AnyView(content()))
        controller.didScroll = { y, p in
            offset = y
            progress = p
        }
        return controller
    }

    func updateUIViewController(_ controller: EagleWelcomeScrollController, context: Context) {
        controller.host.rootView = AnyView(content())
        controller.scroll.isScrollEnabled = enabled
        controller.scroll.accessibilityElementsHidden = !enabled
    }
}

// Not generic on purpose: Swift 6.3's optimizer crashes (EarlyPerfInliner) on the implicit deinit
// of a generic UIViewController subclass in Release builds. The content is type-erased instead.
private final class EagleWelcomeScrollController: UIViewController, UIScrollViewDelegate {
    let scroll = UIScrollView()
    let host: UIHostingController<AnyView>
    var didScroll: ((CGFloat, CGFloat) -> Void)?

    init(content: AnyView) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scroll.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bounces = false
        scroll.scrollsToTop = false
        scroll.accessibilityIdentifier = "eagle.welcome.scroll"
        scroll.indicatorStyle = .white
        // Full-screen film and cards: no system scroll bar along the edge.
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = self
        scroll.isScrollEnabled = false
        view.addSubview(scroll)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }

    /// Speed limit: the finger moves the content 1:1 and a flick glides naturally, but one flick never
    /// carries more than about three quarters of a screen, so it cannot fly straight to Get started.
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let current = scrollView.contentOffset.y
        let travel = targetContentOffset.pointee.y - current
        let limit = scrollView.bounds.height * 0.75
        let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        targetContentOffset.pointee.y = min(maximum, max(0, current + min(limit, max(-limit, travel))))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = max(0, scrollView.contentOffset.y)
        let maximum = max(1, scrollView.contentSize.height - scrollView.bounds.height)
        didScroll?(y, min(1, y / maximum))
    }
}

private struct EagleWelcomeMovieView: UIViewRepresentable {
    let url: URL
    let active: Bool
    let onComplete: () -> Void

    func makeUIView(context: Context) -> EagleWelcomeMovieSurface {
        let view = EagleWelcomeMovieSurface(url: url, onComplete: onComplete)
        if active { view.player.play() }
        return view
    }

    func updateUIView(_ view: EagleWelcomeMovieSurface, context: Context) {
        if active { view.player.play() } else { view.player.pause() }
    }

    static func dismantleUIView(_ view: EagleWelcomeMovieSurface, coordinator: ()) {
        view.player.pause()
    }
}

private final class EagleWelcomeMovieSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    let player: AVPlayer
    // The sound design lives in its own file so the silent movie never drops frames to follow an audio clock.
    private let sound: AVAudioPlayer?
    private var completionObserver: NSObjectProtocol?
    private var playbackObservation: NSKeyValueObservation?
    private var hapticObserver: Any?

    init(url: URL, onComplete: @escaping () -> Void) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        // Ambient respects the silent switch and mixes with the user's music; only applied
        // while no other part of Eagle has configured the session.
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient {
            try? session.setCategory(.ambient, mode: .default)
        }
        sound = Bundle.main.url(forResource: "EagleWelcomeIntro", withExtension: "m4a")
            .flatMap { try? AVAudioPlayer(contentsOf: $0) }
        sound?.prepareToPlay()
        super.init(frame: .zero)
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.followMovie() }
        }
        // The intro opens in darkness; black behind the first frame avoids a light flash at launch.
        backgroundColor = .black
        let playerLayer = layer as! AVPlayerLayer
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        isUserInteractionEnabled = false
        // Touch locked to the film: a crisp tap as the rainbow glint reaches the wing tip with the eagle's
        // cry (2.05 s), then a soft one as the light floods to white (2.4 s).
        let accents = [2.05, 2.4].map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
        hapticObserver = player.addBoundaryTimeObserver(forTimes: accents, queue: .main) { [weak player] in
            let time = player?.currentTime().seconds ?? 0
            if time < 2.25 {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            } else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
            }
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in onComplete() }
    }

    /// Starts or pauses the sound at the movie's current time whenever playback actually starts or stops.
    /// Once the movie has played to its end, the sound's tail (it runs ~3 s longer) keeps ringing over the
    /// live scene instead of stopping with the movie.
    private func followMovie() {
        guard let sound else { return }
        if player.timeControlStatus == .playing {
            guard !sound.isPlaying else { return }
            sound.currentTime = max(0, player.currentTime().seconds)
            sound.play()
        } else if sound.isPlaying, !movieReachedEnd {
            sound.pause()
        }
    }

    /// True once the movie has played to its last frame (it then stops by itself).
    private var movieReachedEnd: Bool {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else { return false }
        return player.currentTime().seconds >= duration - 0.05
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        playbackObservation?.invalidate()
        if let hapticObserver { player.removeTimeObserver(hapticObserver) }
        if let sound, sound.isPlaying, movieReachedEnd {
            // The movie view goes as soon as the movie ends; the sound's tail plays out on its own.
            let remaining = max(0, sound.duration - sound.currentTime)
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.1) { sound.stop() }
        } else {
            sound?.stop()
        }
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
    }
}
