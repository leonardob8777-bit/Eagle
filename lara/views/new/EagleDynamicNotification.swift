import SwiftUI
import UIKit
import Combine

// Native adaptation of the capsule/drop interaction in rit3zh's
// expo-dynamic-notifications. See NOTICE_Dynamic_Notifications.txt.
enum EagleNoticeKind: Sendable {
    case success, error, information

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .information: return "info.circle.fill"
        }
    }

    /// Accent for the title and symbols, as in the reference (#2F9BFF), with system green and red for results.
    var color: Color {
        switch self {
        case .success: return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .error: return Color(red: 1, green: 0.231, blue: 0.188)
        case .information: return Color(red: 0.184, green: 0.608, blue: 1)
        }
    }
}

struct EagleDynamicNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let kind: EagleNoticeKind
    let actionTitle: String?
    let action: (() -> Void)?
    var immediate = false
    /// The card takes the colour opposite to the app: white over a dark app, black over a light one.
    var lightCard = true

    var sourceSymbol: String {
        let source = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if source.contains("island") || source.contains("isla") { return "capsule" }
        if source.contains("dock") { return "dock.rectangle" }
        if source.contains("prepare") || source.contains("prepar") || source == "eagle" { return "lock.shield.fill" }
        if source.contains("battery") || source.contains("bateria") { return "battery.100percent" }
        if source.contains("font") || source.contains("fuente") { return "textformat" }
        if source.contains("wallpaper") || source.contains("fondo") { return "photo.fill" }
        if source.contains("icon") || source.contains("icono") { return "square.grid.2x2.fill" }
        if source.contains("scene") || source.contains("escena") { return "square.stack.3d.up.fill" }
        if source.contains("aura") { return "sparkles" }
        return "sparkles"
    }
}

/// One visible notification and one cancellable expiry. No polling, network,
/// background work or permanent animation. Purely visual: it never intercepts touches.
@MainActor
final class EagleNotifications: ObservableObject {
    static let shared = EagleNotifications()
    @Published private(set) var current: EagleDynamicNotice?
    @Published private(set) var visible = false
    private weak var scene: UIWindowScene?
    private var window: EagleNoticeWindow?
    private var expiry: Task<Void, Never>?
    private var retirement: Task<Void, Never>?
    private var presentation: Task<Void, Never>?
    private var pending: EagleDynamicNotice?
    private var observers: [NSObjectProtocol] = []
    /// Length of the exit choreography in EagleNoticeCard, plus a frame of margin.
    static let exitDuration: UInt64 = 780_000_000

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in EagleNotifications.shared.clear() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let center = EagleNotifications.shared
                guard let next = center.pending else { return }
                center.pending = nil
                center.schedule(next)
            }
        })
    }

    func attach(to scene: UIWindowScene) {
        self.scene = scene
        if let next = pending, UIApplication.shared.applicationState == .active {
            pending = nil
            schedule(next)
        }
    }

    func show(title: String, message: String, kind: EagleNoticeKind = .information,
              actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let next = EagleDynamicNotice(title: title, message: message, kind: kind,
                                     actionTitle: actionTitle, action: action)
        guard UIApplication.shared.applicationState == .active, scene != nil else {
            pending = next // bounded: retain only the most recent completion
            return
        }
        if visible {
            // Repeated actions replace the current notice without queuing a
            // second entrance animation or delaying the new result.
            presentation?.cancel()
            presentation = nil
            present(next)
        } else {
            schedule(next)
        }
    }

    func result(_ succeeded: Bool, title: String, message: String) {
        show(title: title, message: message, kind: succeeded ? .success : .error)
    }

    private func schedule(_ next: EagleDynamicNotice) {
        presentation?.cancel()
        presentation = Task { [weak self] in
            // Let the triggering control finish its own state transition
            // before the separate Island overlay begins to expand.
            do { try await Task.sleep(nanoseconds: 320_000_000) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.presentation = nil
            guard UIApplication.shared.applicationState == .active else {
                self.pending = next
                return
            }
            self.present(next)
        }
    }

    private func present(_ next: EagleDynamicNotice) {
        guard let scene else { pending = next; return }
        expiry?.cancel()
        retirement?.cancel()
        var incoming = next
        incoming.immediate = current != nil
        if window == nil {
            let overlay = EagleNoticeWindow(windowScene: scene)
            overlay.windowLevel = .normal + 1
            overlay.backgroundColor = .clear
            let controller = UIHostingController(rootView: EagleNoticeOverlay(center: self))
            controller.view.backgroundColor = .clear
            overlay.rootViewController = controller
            EagleStatusBar.adopt(controller, from: scene)
            window = overlay
        }
        incoming.lightCard = appIsDark(scene)
        current = incoming
        visible = true
        window?.isHidden = false // deliberately never becomes key window
        // Purely visual: actions are not offered from the notice, so no longer lifetime for them.
        let lifetime: UInt64 = UIAccessibility.isVoiceOverRunning ? 12 : (incoming.kind == .error ? 7 : 4)
        expiry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: (lifetime * 1_000_000_000) + (incoming.immediate ? 0 : 560_000_000)) }
            catch { return }
            guard let self, self.current?.id == incoming.id else { return }
            self.dismiss()
        }
    }

    func hold() { expiry?.cancel(); expiry = nil }

    /// Reads the appearance the app is actually showing (dark, light or following the system).
    private func appIsDark(_ scene: UIWindowScene) -> Bool {
        let app = scene.windows.first { !($0 is EagleNoticeWindow) && $0.isKeyWindow }
            ?? scene.windows.first { !($0 is EagleNoticeWindow) }
        return (app?.traitCollection.userInterfaceStyle ?? .dark) != .light
    }

    func dismiss() {
        beginExit()
    }

    private func beginExit() {
        hold()
        guard let id = current?.id, visible else { return }
        visible = false
        retirement?.cancel()
        retirement = Task { [weak self] in
            // Keep the overlay until the exit has fully played (the drop back inside the island).
            do { try await Task.sleep(nanoseconds: Self.exitDuration) }
            catch { return }
            guard let self, self.current?.id == id else { return }
            self.clear()
        }
    }

    private func clear() {
        presentation?.cancel(); presentation = nil
        expiry?.cancel(); expiry = nil
        retirement?.cancel(); retirement = nil
        visible = false
        current = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        pending = nil
    }
}

/// The notice is purely visual: its window never takes a touch, so taps reach the app underneath.
private final class EagleNoticeWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

struct EagleNotificationInstaller: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene {
                EagleNotifications.shared.attach(to: scene)
            }
        }
    }
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}
}

private struct EagleNoticeOverlay: View {
    @ObservedObject var center: EagleNotifications
    var body: some View {
        GeometryReader { geometry in
            if let notice = center.current {
                EagleNoticeCard(notice: notice, visible: center.visible,
                    layout: EagleNotificationLayout(width: geometry.size.width,
                                                    insetTop: geometry.safeAreaInsets.top),
                    center: center)
                    .id(notice.id)
                    // The source overlay begins at the SCREEN top, not the safe
                    // area. This is what makes the droplet join the actual cutout.
                    .offset(y: -geometry.safeAreaInsets.top)
            }
        }
    }
}

private struct EagleNoticeCard: View {
    let notice: EagleDynamicNotice
    let visible: Bool
    let layout: EagleNotificationLayout
    @ObservedObject var center: EagleNotifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drop: CGFloat = 0
    @State private var expand: CGFloat = 0
    @State private var reveal: CGFloat = 0
    @State private var tint: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var shown = false
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var messageSize: CGFloat = 14

    /// Entrance: a quick spring per part, offset by `delay`. Exit: all parts fade together, fast.
    private func entry(_ delay: Double) -> Animation {
        shown ? .spring(response: 0.42, dampingFraction: 0.82).delay(delay) : .easeOut(duration: 0.14)
    }

    private func announceHaptic() {
        switch notice.kind {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .information: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var resolvedLayout: EagleNotificationLayout {
        // Normal type uses the reference's exact 74-point card. Larger type
        // retains readable text rather than clipping accessibility settings.
        EagleNotificationLayout(width: layout.width, insetTop: layout.insetTop,
                                cardHeight: typeSize.isAccessibilitySize ? 132 : 74)
    }

    var body: some View {
        let l = resolvedLayout
        EagleNotificationMorph(layout: l, drop: drop, expand: expand,
                               reveal: reveal, tint: tint, dragY: dragY,
                               cardTone: notice.lightCard ? 1 : 0) {
            // Reference body (notification-body.tsx): 46 pt avatar disc, accent title, grey message,
            // 27 pt accent symbol, on the card the island's drop turns into. Its parts arrive in a
            // short cascade and leave together.
            let light = notice.lightCard
            HStack(spacing: 12) {
                Image(systemName: notice.sourceSymbol)
                    // Same symbol design in every language (textformat is redrawn per language).
                    .environment(\.locale, Locale(identifier: "en"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(notice.kind.color)
                    .frame(width: 46, height: 46)
                    .background(light ? Color(red: 0.91, green: 0.914, blue: 0.922) : Color(white: 0.17),
                                in: Circle())
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)
                    .animation(entry(0), value: shown)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(notice.title)
                        .font(.system(size: titleSize, weight: .bold))
                        .tracking(-0.35)
                        .foregroundStyle(notice.kind.color)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .offset(y: shown ? 0 : 5)
                        .opacity(shown ? 1 : 0)
                        .animation(entry(0.05), value: shown)
                    Text(notice.message)
                        .font(.system(size: messageSize, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(light ? Color(red: 0.467, green: 0.471, blue: 0.49) : Color(white: 0.64))
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        .offset(y: shown ? 0 : 5)
                        .opacity(shown ? 1 : 0)
                        .animation(entry(0.1), value: shown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                EagleNoticeResultSymbol(symbol: notice.kind.symbol, color: notice.kind.color, shown: shown)
                    .scaleEffect(shown ? 1 : 0.4)
                    .opacity(shown ? 1 : 0)
                    .animation(shown ? .spring(response: 0.45, dampingFraction: 0.58).delay(0.15)
                                     : .easeOut(duration: 0.14), value: shown)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 13).padding(.trailing, 20)
            .frame(width: l.cardWidth, height: l.cardHeight)
            .background(light ? Color.white : Color.black, in: Capsule())
            .environment(\.colorScheme, light ? .light : .dark)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notice.title + ". " + notice.message)
        }
        .frame(width: l.width, height: l.canvasHeight, alignment: .topLeading)
        .task(id: visible) {
            if reduceMotion || (visible && notice.immediate) {
                if visible { announceHaptic() }
                shown = visible
                drop = visible ? 1 : 0
                expand = visible ? 1 : 0
                reveal = visible ? 1 : 0
                tint = visible ? 1 : 0
                return
            }
            if visible {
                announceHaptic()
                // Faster than the reference (drop 1150 ms, tint +110, expand +340, reveal +560): the drop
                // leaves the island with a bulge, stretches into the card with a small width "pop",
                // and the body cascades in as soon as the card has its shape.
                withAnimation(EagleReferenceSpring.animation(milliseconds: 900, dampingRatio: 0.8)) {
                    drop = 1
                }
                do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
                withAnimation(EagleReferenceSpring.animation(milliseconds: 520, dampingRatio: 1)) {
                    tint = 1
                }
                do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                withAnimation(EagleReferenceSpring.animation(milliseconds: 780, dampingRatio: 0.72)) {
                    expand = 1
                }
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
                withAnimation(EagleReferenceSpring.animation(milliseconds: 480, dampingRatio: 1)) {
                    reveal = 1
                }
                shown = true
                UIAccessibility.post(notification: .announcement,
                                     argument: notice.title + ". " + notice.message)
            } else {
                // The body leaves first, the card folds into a drop, then the island draws it back in,
                // accelerating, and swells as it swallows it. ~0.75 s (EagleNotifications.exitDuration).
                shown = false
                do { try await Task.sleep(nanoseconds: 70_000_000) } catch { return }
                withAnimation(EagleReferenceSpring.animation(milliseconds: 240, dampingRatio: 1)) {
                    reveal = 0
                }
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
                withAnimation(EagleReferenceSpring.animation(milliseconds: 460, dampingRatio: 0.9)) {
                    expand = 0
                }
                do { try await Task.sleep(nanoseconds: 110_000_000) } catch { return }
                withAnimation(.timingCurve(0.55, 0, 0.85, 0.45, duration: 0.5)) {
                    drop = 0; tint = 0; dragY = 0
                }
            }
        }
    }
}

/// The result glyph; on iOS 17 and later it bounces once as it lands.
private struct EagleNoticeResultSymbol: View {
    let symbol: String
    let color: Color
    let shown: Bool

    var body: some View {
        let image = Image(systemName: symbol)
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(color)
        if #available(iOS 17.0, *) {
            image.symbolEffect(.bounce, value: shown)
        } else {
            image
        }
    }
}

private struct EagleNoticeModifier<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let title: String
    let message: (Item) -> String
    let kind: (Item) -> EagleNoticeKind
    func body(content: Content) -> some View {
        content.onChange(of: item?.id) { _ in deliver() }.onAppear { deliver() }
    }
    private func deliver() {
        guard let value = item else { return }
        EagleNotifications.shared.show(title: title, message: message(value), kind: kind(value))
        item = nil
    }
}

extension View {
    func eagleNotice<Item: Identifiable>(item: Binding<Item?>, title: String,
        kind: @escaping (Item) -> EagleNoticeKind = { _ in .information },
        message: @escaping (Item) -> String) -> some View {
        modifier(EagleNoticeModifier(item: item, title: title, message: message, kind: kind))
    }
    func eagleStatus(_ status: Binding<String?>, title: String) -> some View {
        onChange(of: status.wrappedValue) { value in
            guard let value else { return }
            EagleNotifications.shared.show(title: title, message: value)
            status.wrappedValue = nil
        }
    }
}
