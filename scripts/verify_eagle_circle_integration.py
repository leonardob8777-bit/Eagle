#!/usr/bin/env python3
"""Check circle integration, preserved behavior and narrowly accepted visual edits."""
from pathlib import Path
import math

from verify_eagle_dock_apply_flow import declaration, replace_once

REPO = Path(__file__).resolve().parents[1]


def read(path):
    return (REPO / path).read_text()


def main():
    from verify_eagle_gallery_services import verify_texts as dock_check, VIEW_PATH, SERVICES_PATH, STORE_PATH
    from verify_eagle_island_filter import verify_texts as island_check, VIEW as ISLAND, MODEL
    from verify_eagle_aura_mode_policy import verify_texts as aura_check, VIEW as AURA, CORE

    dock = read(VIEW_PATH)
    island = read(ISLAND)
    aura = read(AURA)
    checks = [
        (dock, lambda v: dock_check(v, read(SERVICES_PATH), read(STORE_PATH)), [
            (".eagleSymbolPop(favoriteIDs.contains(theme.id))", ".eagleSymbolPop(true)"),
            ("EagleAmbientTimeline(paused: !remoteGallery.loading)", "EagleAmbientTimeline(paused: false)"),
            ("Task { await remoteGallery.load(force: true) }", "Task { await remoteGallery.load(force: false) }"),
            (".disabled(remoteGallery.loading)", ".disabled(false)"),
            (".safeAreaInset(edge: .bottom, spacing: 0)", ".safeAreaInset(edge: .top, spacing: 0)"),
        ]),
        (island, lambda v: island_check(v, read(MODEL)), [
            (".eagleSymbolPop(favorites.contains(item.id))", ".eagleSymbolPop(true)"),
            (".animation(.easeInOut(duration: 0.22), value: isSelected)", ".animation(.linear, value: isSelected)"),
            ("Button { toggleFavorite(item) }", "Button { select(item) }"),
            (".disabled(applying || visibleArtworks.count < 2)", ".disabled(false)"),
            (".eagleActionBar()", ".padding()"),
        ]),
        (aura, lambda v: aura_check(v, read(CORE)), [
            (".transition(.eagleWorking)", ".transition(.slide)"),
            ("if !editingIcons || !mgr.dsready", "if !editingIcons"),
            (".buttonStyle(EaglePressableStyle(kind: .swatch))", ".buttonStyle(.plain)"),
            ("cancelHardDeadline: { progressSchedule.cancelHardDeadline() }", "cancelHardDeadline: {}"),
            ("let progressSchedule = EagleAuraStudioProgressScheduler.start(progress: progress)", "let progressSchedule = EagleAuraStudioProgressScheduler.start(progress: wrong)")
        ])
    ]
    rejected = 0
    for view, check, mutations in checks:
        check(view)
        for before, after in mutations:
            assert before in view
            changed = view.replace(before, after, 1)
            try:
                check(changed)
            except AssertionError:
                rejected += 1
            else:
                raise AssertionError("Accepted visual/behavior mutation: " + before)

    welcome = read("lara/views/new/EagleBeta10WelcomeView.swift")
    opening = declaration(welcome, "private struct EagleWelcomeOpening:")
    for exact in [
        "get { progress }", "set { progress = newValue }",
        ".map { hypot($0.x - origin.x, $0.y - origin.y) }",
        "let feather: CGFloat = 90", "let radius = max((reach + feather) * progress, 0.5)",
        ".init(color: .clear, location: max(0, 1 - feather / max(radius, feather)))",
        ".init(color: .black, location: 1)", ".ignoresSafeArea()",
    ]:
        assert exact in opening, exact
    assert "origin: CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 146)" in welcome
    assert "guard scene.finished, !gathering, !exiting else { return }" in welcome
    assert "duration: 0.75), lasting: 0.75, { opening = 1 }" in welcome
    shell = read("lara/views/new/EagleAppShellView.swift")
    assert "DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { EagleArrival.shared.arrive() }" in shell
    arrival = read("lara/views/new/EagleArrival.swift")
    assert "guard !arrived else { return }\n        arrived = true" in arrival
    root = read("lara/lara.swift")
    assert root.index("EagleAppShellView()") < root.index("EagleBeta10WelcomeView(onContinue:")
    assert ".allowsHitTesting(!showingStableUpdate && !showingLaunchSplash)" in root
    assert ".accessibilityHidden(showingStableUpdate || showingLaunchSplash)" in root

    # Same production geometry: every corner, including the top safe area, is
    # inside the completely clear part at completion. Intermediate radius grows.
    cases = 0
    for width, height in [(320, 568), (375, 667), (393, 852), (402, 874), (430, 932), (440, 956), (768, 1024)]:
        origin = (width / 2, height - 146)
        distances = [math.hypot(x - origin[0], y - origin[1]) for x, y in [(0, 0), (width, 0), (0, height), (width, height)]]
        reach = max(distances)
        previous = 0
        for step in range(1, 101):
            radius = max((reach + 90) * step / 100, 0.5)
            assert radius >= previous
            previous = radius
            cases += 1
        clear_radius = previous * max(0, 1 - 90 / max(previous, 90))
        assert all(distance <= clear_radius + 1e-9 for distance in distances)

    tracker = read("lara/views/new/EagleTouchPoint.swift")
    for exact in ["tracker.cancelsTouchesInView = false", "tracker.delaysTouchesBegan = false", "tracker.delaysTouchesEnded = false", "state = .failed"]:
        assert exact in tracker
    style = read("lara/EagleAdapters/Appearance/EagleApplyButtonStyle.swift")
    assert ".gesture(" not in style and ".simultaneousGesture(" not in style
    print(f"PASS: frozen Dock/Island/Aura behavior with exact visual projections; {rejected} rejected mutations")
    print(f"PASS: pre-mounted app, idempotent arrival, non-intercepting touch adapter; {cases} circle geometry samples")
    print("Geometry/source checks are not device-rendering or native-theme tests.")


if __name__ == "__main__":
    main()
