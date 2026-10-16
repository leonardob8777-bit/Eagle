import SwiftUI
import UIKit

extension View {
    /// Inner screens (Aura Studio, galleries, styles…) on exactly the same Eagle backdrop as Customize
    /// and Access. The navigation bar is painted in the backdrop's top colour, with its title and back
    /// button in the inverse colours (black on white in dark appearance). The content starts just below
    /// the bar, with no empty band, and while scrolling it dissolves into the top instead of passing
    /// under the title. With the backdrop switched off the screen keeps the plain system background.
    /// Appearance only.
    func eagleScreenBackdrop() -> some View {
        modifier(EagleScreenBackdropModifier())
    }
}

extension View {
    /// For the main tabs, whose navigation bar is hidden: they declare the same bar colours as the
    /// inner screens. Nothing changes on the tabs themselves; while an inner screen is swiped back,
    /// the bar no longer blends towards the default colours, so its title stays readable to the end.
    func eagleRootNavigationBar() -> some View {
        modifier(EagleRootNavigationBarModifier())
    }
}

extension View {
    /// For the main tabs, which scroll up to the very top: a veil in the backdrop's top colour behind
    /// the status bar, fading out just below it, so the cards dissolve before reaching the time and
    /// battery instead of passing under them. Appearance only.
    func eagleStatusBarVeil() -> some View {
        modifier(EagleStatusBarVeilModifier())
    }
}

private struct EagleStatusBarVeilModifier: ViewModifier {
    @AppStorage(EagleBackdrop.storageKey) private var enabled = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                let top = proxy.safeAreaInsets.top
                let color = enabled
                    ? EagleScreenBackdropModifier.topColor(colorScheme)
                    : Color(uiColor: .systemGroupedBackground)
                VStack(spacing: 0) {
                    color.frame(height: top)
                    LinearGradient(
                        stops: (0...10).map { i in
                            let u = Double(i) / 10
                            return .init(color: color.opacity(1 - u * u * (3 - 2 * u)), location: u)
                        },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 22)
                }
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct EagleRootNavigationBarModifier: ViewModifier {
    @AppStorage(EagleBackdrop.storageKey) private var enabled = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .toolbarBackground(enabled ? .visible : .automatic, for: .navigationBar)
            .toolbarBackground(
                enabled ? AnyShapeStyle(EagleScreenBackdropModifier.topColor(colorScheme)) : AnyShapeStyle(.bar),
                for: .navigationBar
            )
            .toolbarColorScheme(enabled ? (colorScheme == .dark ? .light : .dark) : nil, for: .navigationBar)
    }
}

private struct EagleScreenBackdropModifier: ViewModifier {
    @AppStorage(EagleBackdrop.storageKey) private var enabled = true
    @Environment(\.colorScheme) private var colorScheme
    /// The navigation bar's bottom edge and the screen's height, measured below.
    @State private var header: CGFloat = 0
    @State private var screenHeight: CGFloat = 0
    /// Flipped just after the screen appears: SwiftUI gets the bar's colours right from the second time
    /// it configures the bar, so it is made to configure it again (with an imperceptibly different
    /// shade, 1/10 of a level) on the first screen opened after launch too.
    @State private var barPass = 0

    /// The content starts just below the navigation bar, with no empty band, and that is where it
    /// comes back to after being pulled down.
    private static let inset: CGFloat = 26

    private var contentInset: CGFloat { enabled ? Self.inset : 0 }

    func body(content: Content) -> some View {
        content
            // Text that follows the backdrop (`eagleBackdropText`) needs to know it moved down.
            .environment(\.eagleBackdropShift, enabled ? backdropShift : 0)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: contentInset)
            }
            // Content dissolves into the top as it scrolls up: a band in the backdrop's top colour lies
            // over it, opaque behind the status and navigation bars and fading out across the inset.
            // Under that band the backdrop is still the top colour (its fade starts at the bar's edge),
            // so it looks exactly like masking the content, but the scrolling list no longer has to be
            // redrawn off screen on every frame.
            .overlay(alignment: .top) {
                if enabled {
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            topColor.frame(height: proxy.safeAreaInsets.top)
                            LinearGradient(
                                stops: (0...12).map { i in
                                    let u = Double(i) / 12
                                    return .init(color: topColor.opacity(1 - u * u * (3 - 2 * u)), location: u)
                                },
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: contentInset)
                        }
                        .ignoresSafeArea(edges: .top)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background {
                GeometryReader { proxy in
                    // Exactly the backdrop of Customize and Access. Its top colour holds to 11.8 % of
                    // the screen, about where a navigation bar ends; when the bar is taller (a search
                    // field under the title) the backdrop moves down with it, so the fade still starts
                    // right where the bar ends instead of being cut by it.
                    ZStack(alignment: .top) {
                        if enabled { topColor }
                        EagleBackdrop()
                            .offset(y: enabled ? backdropShift : 0)
                    }
                    // One layer: while the screen slides in or out, the backdrop's base colour no
                    // longer shows as a thin line along its edge.
                    .compositingGroup()
                    .ignoresSafeArea()
                        .onAppear { measure(proxy) }
                        .onChange(of: proxy.size) { _ in measure(proxy) }
                        .onChange(of: proxy.safeAreaInsets.top) { _ in measure(proxy) }
                }
            }
            .background(EagleNavigationBarClipProbe(active: enabled, style: navigationBarStyle))
            .modifier(EagleTopScrollEdgeEffectHidden(hidden: enabled))
            // The bar is painted in the backdrop's own top colour (the backdrop holds that colour down
            // to the bar's edge, so nothing changes to the eye), and with a visible bar SwiftUI itself
            // gives the title, the back button and the bar buttons the inverse colours, every time it
            // refreshes the bar, including while scrolling.
            .toolbarBackground(enabled ? .visible : .automatic, for: .navigationBar)
            .toolbarBackground(enabled ? AnyShapeStyle(barColor) : AnyShapeStyle(.bar), for: .navigationBar)
            .toolbarColorScheme(enabled ? (colorScheme == .dark ? .light : .dark) : nil, for: .navigationBar)
            .animation(.easeInOut(duration: EagleBackdrop.toggleDuration), value: enabled)
            .onAppear {
                for (index, delay) in [0.05, 0.35].enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { barPass = index + 1 }
                }
            }
    }

    /// The bar's colour for this pass: the top colour, nudged by a tenth of a level on odd passes.
    private var barColor: Color {
        guard barPass % 2 == 1 else { return topColor }
        let level = colorScheme == .dark ? 244.9 / 255 : 0.1 / 255
        return colorScheme == .dark ? Color(red: level, green: level, blue: 242.9 / 255) : Color(red: level, green: level, blue: level)
    }

    /// How far the backdrop moves down so its fade starts under a taller navigation bar.
    private var backdropShift: CGFloat {
        guard screenHeight > 0 else { return 0 }
        return max(0, header - screenHeight * 0.118)
    }

    private func measure(_ proxy: GeometryProxy) {
        header = proxy.safeAreaInsets.top
        screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
    }

    /// The same inverse appearance `toolbarColorScheme` asks for, for the probe below.
    private var navigationBarStyle: UIUserInterfaceStyle {
        guard enabled else { return .unspecified }
        return colorScheme == .dark ? .light : .dark
    }

    /// `EagleBackdrop`'s top colour: studio white in dark appearance, black in light.
    private var topColor: Color { Self.topColor(colorScheme) }

    static func topColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 245 / 255, green: 245 / 255, blue: 243 / 255) : .black
    }
}

/// iOS 26 tints the bar's title from the content scrolling under it; here that content is already
/// faded out under the bar, so the title keeps the backdrop's colours instead.
private struct EagleTopScrollEdgeEffectHidden: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(hidden, for: .top)
        } else {
            content
        }
    }
}

/// While a backdrop screen is on screen:
/// - hides the hairline under the navigation bar: the bar is clipped to its own bounds, which cuts the
///   line drawn just below it (and the bar's background behind the status bar, where the backdrop shows
///   the same colour);
/// - gives the bar the inverse appearance. SwiftUI does the same through `toolbarColorScheme`, but not
///   on the first screen opened after launch (the main tabs hide the bar): there it even puts the bar
///   back to the default while scrolling, which would make the title invisible. A sentinel inside the
///   bar hears every change of its appearance and restores the inverse one right away, in the same
///   update, before anything is drawn. Same value as SwiftUI's, so they never disagree.
/// Screens without the backdrop (Laboratory tools, Settings) get the bar back as it was.
private struct EagleNavigationBarClipProbe: UIViewRepresentable {
    let active: Bool
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> EagleNavigationBarClipProbeView {
        let view = EagleNavigationBarClipProbeView()
        view.isUserInteractionEnabled = false
        view.active = active
        view.style = style
        return view
    }

    func updateUIView(_ view: EagleNavigationBarClipProbeView, context: Context) {
        view.active = active
        view.style = style
    }
}

final class EagleNavigationBarClipProbeView: UIView {
    var active = false {
        didSet { if oldValue != active { apply() } }
    }
    var style: UIUserInterfaceStyle = .unspecified {
        didSet { if oldValue != style { apply() } }
    }
    private weak var bar: UINavigationBar?

    /// Screens currently holding each bar, so a screen that leaves never undoes the one arriving.
    private static var holders: [ObjectIdentifier: Int] = [:]

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            attach()
            // The screen joins its navigation controller, and the bar finishes appearing, just after it
            // enters the window.
            for delay in [0.0, 0.05, 0.15, 0.35, 0.7] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.attach() }
            }
        } else if let held = bar {
            let key = ObjectIdentifier(held)
            let remaining = max(0, (Self.holders[key] ?? 1) - 1)
            Self.holders[key] = remaining == 0 ? nil : remaining
            if remaining == 0 {
                Self.sentinel(in: held)?.removeFromSuperview()
                held.clipsToBounds = false
                held.overrideUserInterfaceStyle = .unspecified
            }
            bar = nil
        }
    }

    private func attach() {
        guard window != nil else { return }
        if bar == nil, let found = findBar() {
            bar = found
            Self.holders[ObjectIdentifier(found), default: 0] += 1
        }
        apply()
    }

    private func apply() {
        guard let bar else { return }
        // Clipping only hides the hairline of the bars before iOS 26. iOS 26 bars have no hairline, and
        // clipping them would cut the round back button's shadow into a visible line below the bar.
        let clip: Bool
        if #available(iOS 26.0, *) { clip = false } else { clip = active }
        if bar.clipsToBounds != clip { bar.clipsToBounds = clip }
        let sentinel = Self.sentinel(in: bar) ?? {
            let view = EagleNavigationBarStyleSentinel(frame: .zero)
            bar.addSubview(view)
            return view
        }()
        sentinel.style = style
        if bar.overrideUserInterfaceStyle != style { bar.overrideUserInterfaceStyle = style }
    }

    private static func sentinel(in bar: UINavigationBar) -> EagleNavigationBarStyleSentinel? {
        bar.subviews.lazy.compactMap { $0 as? EagleNavigationBarStyleSentinel }.first
    }

    private func findBar() -> UINavigationBar? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController {
                return controller.navigationController?.navigationBar
            }
            responder = next
        }
        return nil
    }
}

/// An invisible view inside the navigation bar: its appearance follows the bar's, so it hears when the
/// bar is put back to the default and restores the inverse appearance in the same update.
final class EagleNavigationBarStyleSentinel: UIView {
    var style: UIUserInterfaceStyle = .unspecified

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // Transparent rather than hidden, so it keeps receiving the bar's appearance changes.
        alpha = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // The bar's actual appearance, however it was changed.
        guard style != .unspecified, let bar = superview as? UINavigationBar,
              traitCollection.userInterfaceStyle != style else { return }
        bar.overrideUserInterfaceStyle = style
    }
}

extension View {
    /// The fixed bottom bar of an inner screen (Apply, Restore, Prepare): it floats over the content on
    /// the same light material as the tab bar, with a hairline, in reach of the thumb, and stays put
    /// while the screen scrolls.
    func eagleActionBar() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            // A separate layer: with the material as the background style itself, SwiftUI makes the
            // buttons' white/black fills vibrant (washed-out grey).
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            }
    }
}

/// The fixed bottom bar for a screen's actions. Until Eagle is prepared it holds Prepare, always at
/// hand; once ready, the screen's Apply (and Restore/Remove) buttons. Appearance only: the buttons and
/// their actions are the screen's own.
struct EagleApplyBar<Actions: View>: View {
    var ready = true
    /// Called when Prepare finishes, as the screen's own Prepare did.
    var onPrepared: (() -> Void)? = nil
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 8) {
            if ready {
                VStack(spacing: 8) { actions() }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                LaraAccessView(compact: true, onReady: onPrepared)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: ready)
        .eagleActionBar()
    }
}

/// Eagle's segmented controls (option pickers on every screen): solid instead of translucent, so they
/// read the same over the light top of the backdrop as over the dark. The chosen option takes the
/// action colours (white with black text in dark appearance, black with white text in light), the
/// track is opaque. Appearance only.
enum EagleSegmentedAppearance {
    static func apply() {
        let control = UISegmentedControl.appearance()
        // White in dark appearance, black in light.
        control.selectedSegmentTintColor = .label
        control.backgroundColor = .secondarySystemGroupedBackground
        control.setTitleTextAttributes([
            .foregroundColor: UIColor.systemBackground,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ], for: .selected)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 13, weight: .medium)
        ], for: .normal)
    }
}

extension View {
    /// An inner screen's introduction (title and description at the top) on its own opaque card, like
    /// the rest of the screen, so it reads over the light top of the backdrop as well as over the dark.
    /// Appearance only.
    func eagleHeaderCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    /// For text that scrolls over the main tabs' backdrop (section titles): its colour follows the
    /// backdrop beneath it, white over the dark part and darkening as it moves up onto the light top
    /// (the other way round in light appearance), so it always reads. Computed while drawing, from the
    /// text's position, at no cost to scrolling. Appearance only; iOS 17 and later.
    func eagleBackdropText() -> some View {
        modifier(EagleBackdropTextModifier())
    }
}

private struct EagleBackdropShiftKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How far an inner screen's backdrop sits lower than the main tabs' (under a taller bar).
    var eagleBackdropShift: CGFloat {
        get { self[EagleBackdropShiftKey.self] }
        set { self[EagleBackdropShiftKey.self] = newValue }
    }
}

private struct EagleBackdropTextModifier: ViewModifier {
    @AppStorage(EagleBackdrop.storageKey) private var enabled = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.eagleBackdropShift) private var shift

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), enabled {
            let dark = colorScheme == .dark
            let screenHeight = max(UIScreen.main.bounds.height, 1)
            let shift = shift
            content.visualEffect { effect, proxy in
                // `EagleBackdrop`'s fade runs from 11.8 % to 38.8 % of the screen (smoothstep).
                let y = (proxy.frame(in: .global).midY - shift) / screenHeight
                let u = min(1, max(0, (y - 0.118) / (0.388 - 0.118)))
                let topness = 1 - u * u * (3 - 2 * u)
                // Flips decisively around the middle of the fade instead of following it step by step,
                // so the text is never grey on a grey of the same shade for more than a moment.
                let k = min(1, max(0, (topness - 0.3) / 0.4))
                let flip = k * k * (3 - 2 * k)
                return effect.brightness(dark ? -flip : flip)
            }
        } else {
            content
        }
    }
}
