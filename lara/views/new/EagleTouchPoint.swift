import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Remembers where the last touch went down in the window, without taking part in any gesture: it
/// fails at once, so buttons, scrolling and everything else behave exactly as without it. Buttons use
/// it to start their ripple under the finger. (A SwiftUI `DragGesture` attached for the same purpose
/// stops a `Button`'s own tap from firing.) Appearance only.
final class EagleTouchTracker: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Window coordinates of the last touch-down.
    private(set) static var lastLocation: CGPoint?

    static func install(on window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0 is EagleTouchTracker }) else { return }
        let tracker = EagleTouchTracker(target: nil, action: nil)
        tracker.cancelsTouchesInView = false
        tracker.delaysTouchesBegan = false
        tracker.delaysTouchesEnded = false
        tracker.delegate = tracker
        window.addGestureRecognizer(tracker)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            Self.lastLocation = touch.location(in: nil)
        }
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A plain view behind a SwiftUI view that turns the last touch into that view's own coordinates.
final class EagleTouchAnchor {
    fileprivate weak var view: UIView?

    /// Where the last touch went down, in the anchored view's coordinates, if it landed on it.
    var lastTouch: CGPoint? {
        guard let view, view.window != nil, let location = EagleTouchTracker.lastLocation else { return nil }
        let point = view.convert(location, from: nil)
        return view.bounds.insetBy(dx: -12, dy: -12).contains(point) ? point : nil
    }

    /// The middle of the anchored view, for when the touch is unknown.
    var center: CGPoint? {
        view.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
    }
}

extension View {
    /// Places `anchor` behind this view, so `anchor.lastTouch` is in this view's coordinates.
    func eagleTouchAnchor(_ anchor: EagleTouchAnchor) -> some View {
        background(EagleTouchAnchorView(anchor: anchor).allowsHitTesting(false))
    }
}

private struct EagleTouchAnchorView: UIViewRepresentable {
    let anchor: EagleTouchAnchor

    func makeUIView(context: Context) -> EagleTouchAnchorUIView {
        let view = EagleTouchAnchorUIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        anchor.view = view
        return view
    }

    func updateUIView(_ view: EagleTouchAnchorUIView, context: Context) {
        anchor.view = view
    }
}

private final class EagleTouchAnchorUIView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { EagleTouchTracker.install(on: window) }
    }
}
