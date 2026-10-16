#!/usr/bin/env python3
"""Compare actual Restore orchestration and mixed Dock flows, without native execution."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import PUBLIC_COMMIT, VIEW_PATH, compact, declaration, replace_once

CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryRestoreFlow.swift"
MARKER = "private func restore()"
PREVIOUS_VIEW_SHA = "8983175f1a61a4bfae24038a8ae28d3c2e450e56d9953ccc8c3f6542167d8cc4"
PUBLIC_CALL = "DockGalleryExecutor.shared.restore()"
OWNED_CALL = "EagleDockGalleryCore(port: CurrentDockGalleryPort()).restore()"
PREVIOUS_METHOD = '''private func restore() {
        guard !isApplying else { return }
        isApplying = true
        Task { @MainActor in
            let result = await ''' + OWNED_CALL + '''
            isApplying = false
            if result.succeeded {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            EagleNotifications.shared.result(result.succeeded, title: "Dock Gallery", message: result.message)
        }
    }'''
SCREEN_METHOD = '''private func restore() {
        EagleDockGalleryRestoreFlow.start(
            isApplying: { isApplying },
            setApplying: { isApplying = $0 },
            restore: { await ''' + OWNED_CALL + ''' },
            successFeedback: { UINotificationFeedbackGenerator().notificationOccurred(.success) },
            notify: { EagleNotifications.shared.result($0, title: "Dock Gallery", message: $1) }
        )
    }'''
HEADER = '''static func start(
        isApplying: () -> Bool,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        restore: @escaping @MainActor @Sendable () async -> EagleDockGalleryOutcome,
        successFeedback: @escaping @MainActor @Sendable () -> Void,
        notify: @escaping @MainActor @Sendable (Bool, String) -> Void
    )'''


def inline_restore_flow(source):
    from verify_eagle_visual_base import inline_dock_apply_visuals
    source = inline_dock_apply_visuals(source)
    actual = declaration(source, MARKER)
    assert compact(actual) == compact(SCREEN_METHOD), "Restore screen callbacks changed"
    return replace_once(source, actual, PREVIOUS_METHOD)


def expected_core():
    method = replace_once(PREVIOUS_METHOD, MARKER, HEADER)
    for old, new in (
        ("!isApplying", "!isApplying()"),
        ("isApplying = true", "setApplying(true)"),
        ("isApplying = false", "setApplying(false)"),
        (OWNED_CALL, "restore()"),
        ("UINotificationFeedbackGenerator().notificationOccurred(.success)", "successFeedback()"),
        ('EagleNotifications.shared.result(result.succeeded, title: "Dock Gallery", message: result.message)', "notify(result.succeeded, result.message)"),
    ):
        method = replace_once(method, old, new)
    return "import Foundation\n@MainActor\nenum EagleDockGalleryRestoreFlow {\n    " + method + "\n}\n"


def verify_texts(view, core):
    assert hashlib.sha256(inline_restore_flow(view).encode()).hexdigest() == PREVIOUS_VIEW_SHA, \
        "Screen changed beyond Restore coordination (including Apply, port and native executor)"
    assert compact(core) == compact(expected_core()), "Restore Core differs from counted public sequence"


def verify_sources(repo):
    view, core = [(repo / path).read_text() for path in (VIEW_PATH, CORE_PATH)]
    verify_texts(view, core)
    public = subprocess.run(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo,
                            check=True, capture_output=True, text=True, timeout=55).stdout
    assert replace_once(declaration(public, MARKER), PUBLIC_CALL, OWNED_CALL) == PREVIOUS_METHOD, \
        "Pre-extraction Restore differs from the fixed public method beyond the existing port"
    return public, view


def negatives(repo):
    view, core = [(repo / path).read_text() for path in (VIEW_PATH, CORE_PATH)]
    completion = '''if result.succeeded {
                successFeedback()
            }
            notify(result.succeeded, result.message)'''
    cases = (
        ("view", "isApplying: { isApplying }", "isApplying: { false }"),
        ("view", "isApplying = $0", "isApplying = true"),
        ("view", OWNED_CALL, "EagleDockGalleryOutcome(succeeded: true, message: \"Restored\")"),
        ("view", 'title: "Dock Gallery", message: $1', 'title: "Dock", message: $1'),
        ("view", 'result($0, title:', 'result(true, title:'),
        ("core", "guard !isApplying()", "guard isApplying()"),
        ("core", "setApplying(true)", "setApplying(false)"),
        ("core", "Task { @MainActor in", "Task.detached { @MainActor in"),
        ("core", "let result = await restore()", "let result = await restore()\n            _ = await restore()"),
        ("core", "if result.succeeded", "if !result.succeeded"),
        ("core", "setApplying(false)", "// no reset"),
        ("core", "setApplying(false)\n            " + completion, completion + "\n            setApplying(false)"),
        ("core", "notify(result.succeeded, result.message)", "notify(true, result.message)"),
        ("core", "let result = await restore()", "guard !Task.isCancelled else { return }\n            let result = await restore()"),
    )
    for target, old, new in cases:
        if target == "view":
            method = declaration(view, MARKER)
            changed = replace_once(view, method, replace_once(method, old, new))
        else:
            changed = replace_once(core, old, new)
        try:
            verify_texts(changed if target == "view" else view, changed if target == "core" else core)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted Restore regression: {old}")
    try:
        verify_texts(view + "\n// unrelated change\n", core)
    except AssertionError:
        return len(cases) + 1
    raise AssertionError("Accepted unrelated screen edit")


def host(name, source):
    markers = (MARKER, "private func apply(_ style: DockGalleryStyle)",
               "private func applyRemote(_ theme: RemoteDockGalleryTheme)")
    methods = "\n".join(declaration(source, marker) for marker in markers)
    return '''@MainActor struct ''' + name + ''': FlowHost {
    let context: FlowContext
    var isApplying: Bool {
        get { context.readBusy() }
        nonmutating set { context.writeBusy(newValue) }
    }
    var selectedRaw: Int {
        get { context.selectedRaw }
        nonmutating set { context.writeSelection(newValue) }
    }
    var glowIntensity: Double { context.readIntensity() }
    var remoteGallery: RecordingGallery { context.gallery }
    func start(_ operation: Operation) {
        switch operation {
        case .restore: restore()
        case .builtin: apply(.bubblegum)
        case .remote: applyRemote(context.theme)
        }
    }
    ''' + methods + "\n}\n"


def main():
    repo = Path(__file__).resolve().parents[1]
    public, screen = verify_sources(repo)
    print(f"PASS: counted complete public Restore move and screen binding; {negatives(repo)} rejected regressions", flush=True)
    sources = [repo / "lara/EagleCore/DockGallery" / name for name in (
        "EagleDockGalleryTheme.swift", "EagleDockGalleryBuiltInTheme.swift",
        "EagleDockGalleryCore.swift", "EagleDockGalleryApplyFlow.swift",
        "EagleDockGalleryBuiltInApplyFlow.swift", "EagleDockGalleryRestoreFlow.swift",
    )]
    # Compile the actual existing adapter against a recording executor; do not copy its logic.
    port = "@MainActor\n" + declaration(screen, "private struct CurrentDockGalleryPort:")
    fixture = "import Foundation\n" + port + "\n" + host("PublicFlowHost", public) + host("OwnedFlowHost", screen)
    with tempfile.TemporaryDirectory(prefix="eagle-restore-flow-") as directory:
        work = Path(directory)
        hosts = work / "ExactDockFlowHosts.swift"
        hosts.write_text(fixture)
        binary = work / "verify-restore-flow"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
                        "-default-isolation", "MainActor", "-strict-concurrency=complete",
                        "-warnings-as-errors", "-parse-as-library", *map(str, sources),
                        str(hosts), str(repo / "scripts/verify_eagle_dock_restore_flow.swift"),
                        "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: actual three Core flows, exact public/current screen methods and current port; no native execution/UI/network/IPA", flush=True)


if __name__ == "__main__":
    main()
