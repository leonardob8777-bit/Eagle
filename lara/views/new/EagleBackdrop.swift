import SwiftUI
import UIKit

/// Eagle's app background: the welcome screen's studio white fading into black, inverted with the
/// appearance so the content always sits on its own colour. The fade is the welcome's last frame
/// (measured), so the welcome dissolves onto it without the background changing:
/// - dark appearance: white at the top, black where the content is;
/// - light appearance: black at the top, white where the content is.
/// It can be switched off from Access (`storageKey`), which brings back the plain system background.
/// iOS draws the time and the Wi-Fi in the appearance's text colour, which is the colour of the
/// backdrop's top, so while a backdrop is on screen it asks for the inverse status bar (`EagleStatusBar`).
struct EagleBackdrop: View {
    static let storageKey = "eagle.backdrop.enabled"

    /// Where the switch was when it was last flipped (global coordinates): the gradient opens from
    /// there and closes back into it. Without it the gradient simply fades.
    static var toggleOrigin: CGPoint?
    /// The window's bounds when the switch was flipped (global coordinates), so every view that follows
    /// the circle (the backdrop, the wordmark) uses the same radius whatever its own size.
    static var toggleBounds: CGRect = .zero
    /// How long the gradient takes to open or close from the switch.
    static let toggleDuration = 0.6

    @AppStorage(EagleBackdrop.storageKey) private var enabled = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.eagleTabIsCurrent) private var tabIsCurrent
    @State private var statusBarActive = false
    /// 0 = gradient hidden, 1 = gradient covering the screen.
    /// Starts hidden on the first appearance after launch, so the backdrop lights up softly out of the
    /// launch screen as the content lands, instead of appearing at once.
    @State private var reveal: Double = EagleArrival.shared.arrived
        && (UserDefaults.standard.object(forKey: EagleBackdrop.storageKey) as? Bool ?? true) ? 1 : 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The welcome's studio white (#F5F5F3).
    private static let studio = Color(red: 245 / 255, green: 245 / 255, blue: 243 / 255)

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            gradient
                .modifier(EagleBackdropReveal(progress: reveal, origin: Self.toggleOrigin))
        }
        .background(EagleStatusBarProbe(style: statusBarStyle, active: statusBarActive && tabIsCurrent))
        .animation(.easeInOut(duration: 0.45), value: colorScheme)
        .onAppear {
            statusBarActive = true
            if enabled && reveal < 1 && !reduceMotion {
                withAnimation(.easeOut(duration: 0.6)) { reveal = 1 }
            } else {
                reveal = enabled ? 1 : 0
            }
        }
        .onDisappear { statusBarActive = false }
        .onChange(of: enabled) { on in
            withAnimation(.easeInOut(duration: Self.toggleDuration)) { reveal = on ? 1 : 0 }
        }
    }

    /// Dark text over the white top (dark appearance), light text over the black top (light
    /// appearance); the system's own style when the backdrop is off.
    private var statusBarStyle: UIStatusBarStyle? {
        guard enabled else { return nil }
        return colorScheme == .dark ? .darkContent : .lightContent
    }

    private var gradient: some View {
        let dark = colorScheme == .dark
        let top = dark ? Self.studio : Color.black
        let bottom = dark ? Color.black : Self.studio
        // The top colour holds behind the header, then eases into the content colour exactly where the
        // welcome's fade does (smoothstep stops, so the transition has no visible bands).
        var stops: [Gradient.Stop] = [.init(color: top, location: 0)]
        let start = 0.118, end = 0.388, count = 24
        for i in 0...count {
            let u = Double(i) / Double(count)
            let eased = u * u * (3 - 2 * u)
            stops.append(.init(color: mix(top, bottom, eased, dark: dark), location: start + (end - start) * u))
        }
        stops.append(.init(color: bottom, location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Linear blend between the studio white and black in the given direction.
    private func mix(_ from: Color, _ to: Color, _ amount: Double, dark: Bool) -> Color {
        // Both ends are neutral greys: blend the white level directly.
        let white = (red: 245.0, green: 245.0, blue: 243.0)
        let level = dark ? 1 - amount : amount
        return Color(red: white.red / 255 * level, green: white.green / 255 * level, blue: white.blue / 255 * level)
    }
}

/// Shows the backdrop's gradient through a soft-edged circle that grows from `origin` (the switch, in
/// global coordinates) until it covers the screen, and shrinks back into it. Without an origin it fades.
/// The header's wordmark uses the same circle, so its colours change exactly where the backdrop does.
struct EagleBackdropReveal: ViewModifier, Animatable {
    var progress: Double
    let origin: CGPoint?

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if progress >= 1 {
            // Fully open: the circle covers everything, so no mask is kept on the backdrop afterwards.
            content
        } else if let origin {
            content.mask {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    let size = proxy.size
                    let center = CGPoint(x: origin.x - frame.minX, y: origin.y - frame.minY)
                    let bounds = EagleBackdrop.toggleBounds.isEmpty ? frame : EagleBackdrop.toggleBounds
                    let reach = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                                 CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
                        .map { hypot($0.x - origin.x, $0.y - origin.y) }
                        .max() ?? 0
                    let feather: CGFloat = 90
                    let radius = max((reach + feather) * progress, 0.5)
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, 1 - feather / max(radius, feather))),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)),
                        startRadius: 0,
                        endRadius: radius
                    )
                    .opacity(progress > 0 ? 1 : 0)
                }
            }
        } else {
            content.opacity(progress)
        }
    }
}

/// Records the actual backdrop's location, not a global count shared by hidden tabs/sheets.
private struct EagleStatusBarProbe: UIViewRepresentable {
    let style: UIStatusBarStyle?
    let active: Bool

    func makeUIView(context: Context) -> EagleStatusBarProbeView {
        let view = EagleStatusBarProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: EagleStatusBarProbeView, context: Context) {
        view.style = style
        view.active = active
        EagleStatusBar.register(view)
    }

    static func dismantleUIView(_ view: EagleStatusBarProbeView, coordinator: ()) {
        view.active = false
        EagleStatusBar.refresh()
    }
}

private final class EagleStatusBarProbeView: UIView {
    var style: UIStatusBarStyle?
    var active = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        EagleStatusBar.register(self)
    }
}

/// The existing SwiftUI status-style bridge, scoped to the controller that owns a visible backdrop.
/// Navigation children also own the status bar; changing only the window root misses them.
/// Normal destinations/sheets keep UIKit's original style. No controller or root view is replaced.
enum EagleStatusBar {
    private static let probes = NSHashTable<EagleStatusBarProbeView>.weakObjects()
    private static let overlaySources = NSMapTable<UIViewController, UIWindow>.weakToWeakObjects()
    private static var patchedClasses = Set<ObjectIdentifier>()
    private static var patchedVisibilityClasses = Set<ObjectIdentifier>()
    private static var refreshScheduled = false

    fileprivate static func register(_ probe: EagleStatusBarProbeView) {
        probes.add(probe)
        refresh()
    }

    private static func isFrontmost(_ probe: EagleStatusBarProbeView) -> Bool {
        guard probe.active, probe.window != nil else { return false }
        var responder: UIResponder? = probe
        while let current = responder {
            if let view = current as? UIView, view.isHidden || view.alpha <= 0.01 { return false }
            if let controller = current as? UIViewController {
                if let navigation = controller.parent as? UINavigationController,
                   navigation.topViewController !== controller { return false }
                if let tabs = controller.parent as? UITabBarController,
                   tabs.selectedViewController !== controller { return false }
            }
            responder = current.next
        }
        return true
    }

    private static func style(for controller: UIViewController) -> UIStatusBarStyle? {
        guard let view = controller.viewIfLoaded, let window = view.window else { return nil }
        // UIKit dims the area above a page sheet. With Eagle's inverted top it is
        // gray or black, even if the app switches to Light while the sheet is open.
        // The sheet's cached appearance must not turn those indicators black.
        // A page sheet can leave the presenting controller in charge of the status
        // bar. Resolve it from the window, not only from the queried sheet child.
        // Not while the sheet is closing: UIKit asks again as it goes, and the screen's own style must
        // come back (otherwise the indicators stayed light over the white top after any sheet).
        if let sheet = window.rootViewController?.presentedViewController,
           sheet.sheetPresentationController != nil,
           !sheet.isBeingDismissed,
           probes.allObjects.contains(where: { probe in
               probe.window === window && isFrontmost(probe) && probe.style != nil
                   && !(sheet.viewIfLoaded.map { probe.isDescendant(of: $0) } ?? false)
           }) {
            return .lightContent
        }
        return probes.allObjects.first {
            $0.window === window && $0.isDescendant(of: view) && isFrontmost($0) && $0.style != nil
        }?.style
    }

    /// A non-key notification window must mirror its app window, not its own default appearance.
    static func adopt(_ controller: UIViewController, from scene: UIWindowScene) {
        if let source = scene.windows.first(where: { $0.isKeyWindow }) {
            overlaySources.setObject(source, forKey: controller)
        }
        redirect(type(of: controller))
        redirectVisibility(type(of: controller))
        controller.setNeedsStatusBarAppearanceUpdate()
    }

    static func refresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async {
            refreshScheduled = false
            let roots = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .compactMap(\.rootViewController)
            roots.forEach { refreshTree($0) }
        }
    }

    private static func refreshTree(_ controller: UIViewController) {
        redirect(type(of: controller))
        controller.children.forEach { refreshTree($0) }
        if let presented = controller.presentedViewController { refreshTree(presented) }
        controller.setNeedsStatusBarAppearanceUpdate()
    }

    private static func owner(in window: UIWindow, hidden: Bool = false) -> UIViewController? {
        var result = window.rootViewController
        var seen = Set<ObjectIdentifier>()
        while let current = result, seen.insert(ObjectIdentifier(current)).inserted {
            if let presented = current.presentedViewController,
               presented.modalPresentationCapturesStatusBarAppearance || presented.modalPresentationStyle == .fullScreen {
                result = presented
            } else if let child = hidden ? current.childForStatusBarHidden : current.childForStatusBarStyle {
                result = child
            } else { break }
        }
        return result
    }

    private static func redirect(_ controllerClass: AnyClass) {
        guard patchedClasses.insert(ObjectIdentifier(controllerClass)).inserted else { return }
        let selector = #selector(getter: UIViewController.preferredStatusBarStyle)
        guard let method = class_getInstanceMethod(controllerClass, selector) else { return }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let replacement: @convention(block) (AnyObject) -> Int = { controller in
            guard let controller = controller as? UIViewController else { return original(controller, selector) }
            if let source = overlaySources.object(forKey: controller), let owner = owner(in: source) {
                return owner.preferredStatusBarStyle.rawValue
            }
            return style(for: controller)?.rawValue ?? original(controller, selector)
        }
        class_replaceMethod(controllerClass, selector, imp_implementationWithBlock(replacement),
                            method_getTypeEncoding(method))
    }

    private static func redirectVisibility(_ controllerClass: AnyClass) {
        guard patchedVisibilityClasses.insert(ObjectIdentifier(controllerClass)).inserted else { return }
        let selector = #selector(getter: UIViewController.prefersStatusBarHidden)
        guard let method = class_getInstanceMethod(controllerClass, selector) else { return }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let replacement: @convention(block) (AnyObject) -> Bool = { controller in
            if let controller = controller as? UIViewController,
               let source = overlaySources.object(forKey: controller), let owner = owner(in: source, hidden: true) {
                return owner.prefersStatusBarHidden
            }
            return original(controller, selector)
        }
        class_replaceMethod(controllerClass, selector, imp_implementationWithBlock(replacement),
                            method_getTypeEncoding(method))
    }
}
