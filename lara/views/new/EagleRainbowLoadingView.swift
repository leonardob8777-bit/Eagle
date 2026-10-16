import SwiftUI

enum EagleAppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    static let storageKey = "eagle.appearance.mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return LaraL10n.text(en: "Dark", es: "Oscuro")
        case .light: return LaraL10n.text(en: "Light", es: "Claro")
        case .system: return LaraL10n.text(en: "System", es: "Sistema")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

struct EagleBrandMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 42
    /// When true the mark carries its own rainbow sweep. The header turns this
    /// off so a single sweep can travel across the whole lockup instead.
    var shimmer: Bool = true

    var body: some View {
        Group {
            if shimmer && !reduceMotion {
                TimelineView(EagleBrandSweepSchedule()) { context in
                    glyph(sweep: eagleBrandSweepProgress(at: context.date))
                }
            } else {
                glyph(sweep: nil)
            }
        }
        .shadow(color: EagleVisualTheme.accent.opacity(0.16), radius: size * 0.10)
        .accessibilityHidden(true)
    }

    private func glyph(sweep: Double?) -> some View {
        ZStack {
            brandGlyph
                .foregroundStyle(.primary.opacity(0.92))

            if let sweep {
                brandShine(progress: sweep)
            }
        }
        .frame(width: size, height: size)
    }

    /// A glossy rainbow reflection that glides across the mark: a feathered
    /// spectrum band carries the colour while a bright specular core gives the
    /// gleam, both clipped to the silhouette so only the bird catches the light.
    private func brandShine(progress: Double) -> some View {
        let x = size * (-1.2 + 2.4 * progress)

        return ZStack {
            EagleSpectrumStyle.gradient
                .frame(width: size * 0.6, height: size * 1.7)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white.opacity(0.65), location: 0.33),
                            .init(color: .white, location: 0.5),
                            .init(color: .white.opacity(0.65), location: 0.67),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(-16))
                .offset(x: x)
                .opacity(0.92)

            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white, location: 0.5),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size * 0.17, height: size * 1.7)
                .rotationEffect(.degrees(-16))
                .offset(x: x)
                .blendMode(.plusLighter)
                .opacity(0.75)
        }
        .frame(width: size, height: size)
        .mask(brandGlyph)
        .allowsHitTesting(false)
    }

    private var brandGlyph: some View {
        Image("EagleBrandMark")
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// A reusable rainbow "reflection" that periodically sweeps across whatever it
/// is attached to, then parks off-screen until the next pass. The band carries
/// a vivid full-spectrum colour plus a bright white specular core for the gleam,
/// and is clipped to the content's own shapes so only the glyphs catch the
/// light — it reads on the solid eagle mark and on thin serif letters alike.
struct EagleRainbowSweep: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Only while on screen: a covered screen or another tab does not keep redrawing it.
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion && onScreen {
                    GeometryReader { geo in
                        TimelineView(EagleBrandSweepSchedule()) { ctx in
                            ZStack {
                                if let progress = eagleBrandSweepProgress(at: ctx.date) {
                                    band(in: geo.size, progress: progress)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }

    private func band(in size: CGSize, progress: Double) -> some View {
        let h = max(size.height, 1)
        let bandWidth = h * 1.0
        let reach = size.width / 2 + bandWidth
        let x = -reach + progress * (reach * 2)
        let tall = max(h, size.width) * 2.2

        return ZStack {
            // Vivid full-spectrum colour, feathered at the edges.
            Rectangle()
                .fill(EagleSpectrumStyle.gradient)
                .frame(width: bandWidth, height: tall)
                .mask(feather(soft: 0.7))
                .saturation(1.5)
                .rotationEffect(.degrees(-18))
                .offset(x: x)

            // Bright white specular core — the crisp "shine" streak.
            Rectangle()
                .fill(Color.white)
                .frame(width: bandWidth * 0.22, height: tall)
                .mask(feather(soft: 0.0))
                .blendMode(.plusLighter)
                .opacity(0.9)
                .rotationEffect(.degrees(-18))
                .offset(x: x)
        }
        .frame(width: size.width, height: size.height)
        .blur(radius: 0.5)
    }

    private func feather(soft: Double) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .white.opacity(soft), location: 0.30),
                .init(color: .white, location: 0.5),
                .init(color: .white.opacity(soft), location: 0.70),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension View {
    /// Adds Eagle's periodic rainbow reflection, clipped to the view's shapes.
    func eagleRainbowSweep() -> some View {
        modifier(EagleRainbowSweep())
    }
}

/// The header lockup: the eagle mark followed by the serif wordmark, sharing a
/// single rainbow reflection that sweeps across both at once.
struct EagleWordmark: View {
    var logoSize: CGFloat = 54
    var nameSize: CGFloat = 32
    var spacing: CGFloat = 12
    /// In the main headers the wordmark sits on the Eagle backdrop's top, which is the inverse of the
    /// appearance; there it takes the inverted colours so it stays readable.
    var invertsOnBackdrop = false

    @AppStorage(EagleBackdrop.storageKey) private var backdropEnabled = true
    @Environment(\.colorScheme) private var colorScheme
    /// 0 = normal colours, 1 = inverted (the backdrop is behind the wordmark).
    @State private var reveal: Double = (UserDefaults.standard.object(forKey: EagleBackdrop.storageKey) as? Bool ?? true) ? 1 : 0

    var body: some View {
        if invertsOnBackdrop {
            // The inverted colouring shows through the same circle that opens the backdrop from the
            // switch, so every part of the wordmark takes its new colour exactly when the backdrop
            // behind it changes and never disappears against it.
            ZStack {
                lockup
                    .environment(\.colorScheme, colorScheme)
                    .opacity(reveal >= 1 ? 0 : 1)
                lockup
                    .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
                    .modifier(EagleBackdropReveal(progress: reveal, origin: EagleBackdrop.toggleOrigin))
                    .accessibilityHidden(true)
            }
            .eagleRainbowSweep()
            .onAppear { reveal = backdropEnabled ? 1 : 0 }
            .onChange(of: backdropEnabled) { on in
                withAnimation(.easeInOut(duration: EagleBackdrop.toggleDuration)) { reveal = on ? 1 : 0 }
            }
        } else {
            lockup
                .eagleRainbowSweep()
        }
    }

    private var lockup: some View {
        HStack(spacing: spacing) {
            EagleBrandMark(size: logoSize, shimmer: false)

            Text("Eagle")
                .font(.system(size: nameSize, weight: .semibold, design: .serif).lowercaseSmallCaps())
                .tracking(1.5)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Shared top header for both the Customize and Access screens: the Eagle
/// wordmark on the left, the language and settings controls together on the
/// right at the same level, and the device-identity pill fixed on the line
/// directly below the wordmark.
/// The backdrop switch's look: system size and motion, in black and white. While it is on, the
/// backdrop's top (the inverse of the appearance) is behind it, so the track takes the appearance's
/// background colour and the knob its text colour; while it is off, the usual grey track and white
/// knob. The knob stretches under the finger like a system switch.
private struct EagleBackdropSwitchStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? EagleVisualTheme.actionText : Color(uiColor: .systemFill))
            Capsule()
                .fill(isOn ? EagleVisualTheme.actionFill : Color.white)
                .frame(width: configuration.isPressed ? 33 : 27, height: 27)
                .shadow(color: .black.opacity(0.2), radius: 2.5, y: 1.5)
                .padding(2)
        }
        .frame(width: 51, height: 31)
        .frame(height: 44)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isOn)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct EagleHeaderBar: View {
    @Binding var language: LaraLanguage
    /// Access shows the backdrop switch under Settings; Customize does not.
    var showsBackdropToggle = false
    var onSettings: () -> Void

    @AppStorage(EagleBackdrop.storageKey) private var backdropEnabled = true
    @State private var gearTurns = 0.0
    @State private var wordmarkHop = false
    @State private var readyRingScale: CGFloat = 1
    @State private var readyRingOpacity: Double = 0

    @ObservedObject private var mgr = laramgr.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                EagleWordmark(invertsOnBackdrop: true)
                    // A tap on the wordmark makes it hop, with a soft tap of feedback.
                    .scaleEffect(wordmarkHop ? 1.06 : 1, anchor: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { wordmarkHop = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { wordmarkHop = false }
                        }
                    }
                Spacer(minLength: 8)
                languageBadge
                settingsButton
            }
            HStack(alignment: .center, spacing: 10) {
                readinessBadge
                Spacer(minLength: 8)
                if showsBackdropToggle {
                    backdropSwitch
                }
            }
        }
    }

    /// Switch that turns the Eagle backdrop on or off: a system-style switch in black and white
    /// instead of green.
    /// The backdrop opens in a circle from the switch (and closes back into it); a light tap on the
    /// flip and a softer one as the backdrop settles.
    private var backdropSwitch: some View {
        GeometryReader { proxy in
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let frame = proxy.frame(in: .global)
                EagleBackdrop.toggleOrigin = CGPoint(x: frame.midX, y: frame.midY)
                EagleBackdrop.toggleBounds = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
                    .first?.bounds ?? .zero
                withAnimation(.easeInOut(duration: EagleBackdrop.toggleDuration)) { backdropEnabled.toggle() }
                DispatchQueue.main.asyncAfter(deadline: .now() + EagleBackdrop.toggleDuration * 0.9) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
                }
            } label: {
                EmptyView()
            }
            .buttonStyle(EagleBackdropSwitchStyle(isOn: backdropEnabled))
            .accessibilityLabel(LaraL10n.text(en: "Eagle background", es: "Fondo Eagle"))
            .accessibilityValue(backdropEnabled
                ? LaraL10n.text(en: "On", es: "Activado")
                : LaraL10n.text(en: "Off", es: "Desactivado"))
        }
        .frame(width: 51, height: 44)
    }

    private var languageBadge: some View {
        Menu {
            Picker(
                LaraL10n.text(en: "Language", es: "Idioma"),
                selection: $language
            ) {
                ForEach(LaraLanguage.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.primary)
                Text(language.shortName)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .tint(.primary)
        .accessibilityLabel(LaraL10n.text(en: "Language", es: "Idioma"))
        .accessibilityValue(language.displayName)
    }

    /// The gear gives a quarter turn as Settings opens.
    private var settingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { gearTurns += 1 }
            onSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(gearTurns * 90))
                .frame(width: 44, height: 44)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LaraL10n.text(en: "Settings", es: "Ajustes"))
    }

    private var deviceModelName: String {
        let full = EagleDynamicIslandCompatibility.current.displayModel
        if let cut = full.range(of: " (") {
            return String(full[..<cut.lowerBound])
        }
        return full
    }

    private var iosVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0
            ? "\(v.majorVersion).\(v.minorVersion)"
            : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// When the device becomes identified the dot turns green with a soft glow and sends out one ring,
    /// and the pill grows to the new text.
    private var readinessBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mgr.sbxready ? Color.green : Color.secondary.opacity(0.32))
                .frame(width: 8, height: 8)
                .shadow(color: mgr.sbxready ? Color.green.opacity(0.65) : .clear, radius: 3)
                .overlay {
                    Circle()
                        .stroke(Color.green, lineWidth: 1.5)
                        .scaleEffect(readyRingScale)
                        .opacity(readyRingOpacity)
                }
            Text(mgr.sbxready
                ? "\(deviceModelName) · iOS \(iosVersionString)"
                : LaraL10n.text(en: "Not identified", es: "No identificado"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .id(mgr.sbxready)
                .transition(.opacity.combined(with: .offset(y: 4)))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: mgr.sbxready)
        .onChange(of: mgr.sbxready) { ready in
            guard ready else { return }
            readyRingScale = 1
            readyRingOpacity = 0.9
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.9)) {
                    readyRingScale = 3.2
                    readyRingOpacity = 0
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            mgr.sbxready
                ? LaraL10n.text(
                    en: "Identified: \(deviceModelName), iOS \(iosVersionString)",
                    es: "Identificado: \(deviceModelName), iOS \(iosVersionString)"
                )
                : LaraL10n.text(en: "Not identified", es: "No identificado")
        )
    }
}

enum EagleSpectrumStyle {
    static let colors: [Color] = [
        .cyan,
        .blue,
        .purple,
        .pink,
        .red,
        .orange,
        .yellow,
        .green,
        .cyan,
    ]

    static var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var wordmarkGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.13, green: 0.72, blue: 0.90),
                Color(red: 0.19, green: 0.55, blue: 0.96),
                Color(red: 0.33, green: 0.42, blue: 0.94),
                Color(red: 0.52, green: 0.34, blue: 0.91),
                Color(red: 0.74, green: 0.30, blue: 0.85),
                Color(red: 0.93, green: 0.33, blue: 0.63),
                Color(red: 0.98, green: 0.44, blue: 0.42),
                Color(red: 0.99, green: 0.62, blue: 0.30),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // Monochrome, adaptive navigation tint (black in light, white in dark) so
    // Back/Close match the rest of the neutral chrome.
    static let navigationTintColor = UIColor.label

    static func configureGlobalNavigationAppearance() {
        UINavigationBar.appearance().tintColor = navigationTintColor
        UIBarButtonItem.appearance(
            whenContainedInInstancesOf: [UINavigationBar.self]
        ).tintColor = navigationTintColor
        EagleSegmentedAppearance.apply()
    }
}

struct EagleSpectrumText: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(EagleVisualTheme.accent)
    }
}

/// Eagle's shared activity indicator, used by every screen while something loads or applies. It is
/// Eagle's own black-and-white ring (the same as Prepare's), no longer a rainbow wheel; the name stays
/// so every screen keeps using it unchanged.
struct EagleRainbowSpinner: View {
    var size: CGFloat = 20

    var body: some View {
        EagleMarkSpinner(size: size)
    }
}

struct EagleRainbowProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let value: Double
    var height: CGFloat = 4

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: reduceMotion || scenePhase != .active
        )) { context in
            let time = reduceMotion || scenePhase != .active
                ? 0 : context.date.timeIntervalSinceReferenceDate

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let fillWidth = width * min(max(value, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.24))

                    Capsule(style: .continuous)
                        .fill(rainbow(at: time))
                        .frame(width: fillWidth)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LaraL10n.text(
            en: "Preparation progress",
            es: "Progreso de preparación"
        ))
        .accessibilityValue(Text(
            min(max(value, 0), 1),
            format: .percent.precision(.fractionLength(0))
        ))
    }

    private func rainbow(at time: TimeInterval) -> LinearGradient {
        let phase = (time / 7).truncatingRemainder(dividingBy: 1)
        let motion = phase * 2 * Double.pi
        let stops = (0...32).map { index -> Gradient.Stop in
            let location = Double(index) / 32
            // Both waves complete whole revolutions in the seven-second hue
            // cycle, so the last frame joins the first without a color jump.
            let flow = 0.04 * sin(location * .pi * 4 - motion)
                + 0.02 * sin(location * .pi * 6 + 2 * motion)
            let hue = (0.5 + location + phase + flow)
                .truncatingRemainder(dividingBy: 1)
            return Gradient.Stop(
                color: Color(hue: hue, saturation: 0.98, brightness: 1),
                location: location
            )
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

private func eagleRainbowPhase(at date: Date, duration: TimeInterval) -> Double {
    let cycles = date.timeIntervalSinceReferenceDate / duration
    return cycles - floor(cycles)
}

/// A short, restrained sheen followed by a long pause. Returning `nil` keeps
/// the overlay out of the render tree while the mark is resting.
/// Wakes a `TimelineView` 30 times a second only while the brand sweep is crossing, plus once when the
/// next pass begins; between passes (six of every 7.2 seconds) nothing redraws. Same rhythm as
/// `eagleBrandSweepProgress`: one 1.2 s pass every 7.2 s.
struct EagleBrandSweepSchedule: TimelineSchedule {
    nonisolated func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date

        nonisolated mutating func next() -> Date? {
            let current = upcoming
            let time = current.timeIntervalSinceReferenceDate
            let phase = time.truncatingRemainder(dividingBy: 7.2)
            // A frame just past the pass clears the band; then sleep until the next pass. 60 fps during
            // the short pass (1.25 s every 7.2 s), so the shine glides instead of stepping.
            upcoming = phase < 1.25
                ? current.addingTimeInterval(1.0 / 60.0)
                : Date(timeIntervalSinceReferenceDate: time - phase + 7.2)
            return current
        }
    }
}

func eagleBrandSweepProgress(at date: Date) -> Double? {
    let cycleDuration = 7.2
    let sweepDuration = 1.2
    let elapsed = date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: cycleDuration)

    guard elapsed < sweepDuration else { return nil }
    let progress = max(0, min(elapsed / sweepDuration, 1))
    return progress * progress * (3 - (2 * progress))
}
