#!/usr/bin/env python3
"""Source integration gates for the status-bar fix; runtime UI checks live with its IPA."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]


def verify(root, backdrop, notice):
    assert root.count('.statusBarHidden(') == 1
    assert '.statusBarHidden(showingStableUpdate || showingLaunchSplash)' in root
    assert '.onChange(of: showingStableUpdate) { _ in EagleStatusBar.refresh() }' in root
    assert '.onChange(of: showingLaunchSplash) { _ in EagleStatusBar.refresh() }' in root
    assert root.index('.statusBarHidden(showingStableUpdate || showingLaunchSplash)') > root.index('.zIndex(101)')
    assert 'visibleBackdrops' not in backdrop and 'backdropStyle' not in backdrop
    for fragment in [
        'NSHashTable<EagleStatusBarProbeView>.weakObjects()',
        'NSMapTable<UIViewController, UIWindow>.weakToWeakObjects()',
        'statusBarActive && tabIsCurrent',
        '.onDisappear { statusBarActive = false }',
        'guard probe.active, probe.window != nil else { return false }',
        'navigation.topViewController !== controller',
        'tabs.selectedViewController !== controller',
        '$0.window === window && $0.isDescendant(of: view) && isFrontmost($0)',
        'controller.children.forEach { refreshTree($0) }',
        'if let sheet = window.rootViewController?.presentedViewController,',
        'sheet.sheetPresentationController != nil',
        'sheet.viewIfLoaded.map { probe.isDescendant(of: $0) }',
        'return style(for: controller)?.rawValue ?? original(controller, selector)',
        'return owner.preferredStatusBarStyle.rawValue',
        'return owner.prefersStatusBarHidden',
        'guard !refreshScheduled else { return }',
    ]:
        assert fragment in backdrop, fragment
    assert 'EagleStatusBar.adopt(controller, from: scene)' in notice
    assert 'overlay.windowLevel = .normal + 1' in notice
    assert 'override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }' in notice
    assert '.makeKey' not in notice


def main():
    paths = ['lara/lara.swift', 'lara/views/new/EagleBackdrop.swift', 'lara/views/new/EagleDynamicNotification.swift']
    values = [(ROOT / p).read_text() for p in paths]
    verify(*values)
    mutations = [
        (0, '.statusBarHidden(showingStableUpdate || showingLaunchSplash)', '.statusBarHidden(true)'),
        (0, '.statusBarHidden(showingStableUpdate || showingLaunchSplash)', '.statusBarHidden(showingStableUpdate)'),
        (0, '.onChange(of: showingLaunchSplash) { _ in EagleStatusBar.refresh() }', ''),
        (0, '.onChange(of: showingStableUpdate) { _ in EagleStatusBar.refresh() }', ''),
        (1, 'statusBarActive && tabIsCurrent', 'true'),
        (1, 'navigation.topViewController !== controller', 'false'),
        (1, 'tabs.selectedViewController !== controller', 'false'),
        (1, '$0.window === window && $0.isDescendant(of: view)', '$0.window != nil'),
        (1, 'controller.children.forEach { refreshTree($0) }', ''),
        (1, 'sheet.sheetPresentationController != nil', 'false'),
        (1, 'sheet.viewIfLoaded.map { probe.isDescendant(of: $0) }', 'sheet.viewIfLoaded.map { _ in true }'),
        (1, 'return owner.preferredStatusBarStyle.rawValue', 'return UIStatusBarStyle.default.rawValue'),
        (1, 'return owner.prefersStatusBarHidden', 'return false'),
        (2, 'EagleStatusBar.adopt(controller, from: scene)', ''),
    ]
    for index, before, after in mutations:
        changed = values.copy()
        assert before in changed[index]
        changed[index] = changed[index].replace(before, after, 1)
        try:
            verify(*changed)
        except AssertionError:
            continue
        raise AssertionError('Accepted status regression: ' + before)
    for path, expected in [
        ('lara/classes/laramgr.swift', '318983f67aa2af3896e0deadac2a079f52d440a5aeba2810fa6401b0d99cd24b'),
        ('Config/lara.entitlements', '4ef60cb88d3092dad8b2caeba0d842d03f3cb78bcca956eb330ad647f1ec80f9'),
    ]:
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected
    print('PASS: one Updates/splash visibility owner, per-controller backdrop/sheet scope, notification forwarding; 14 rejected mutations')
    print('PASS: native manager and entitlements unchanged; these checks do not replace simulator/device rendering tests')


if __name__ == '__main__':
    main()
