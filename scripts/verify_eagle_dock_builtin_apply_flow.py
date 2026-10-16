#!/usr/bin/env python3
"""Compare built-in Apply coordination with the fixed public method; no native calls."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from verify_eagle_dock_apply_flow import PUBLIC_COMMIT, VIEW_PATH, compact, declaration, replace_once

CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInApplyFlow.swift"
MARKER = "private func apply(_ style: DockGalleryStyle)"
PREVIOUS_VIEW_SHA = "1362f72676ddf74481000edd37a31253e9bf1e25a920a9e5aee65dc201485198"
PREVIOUS_METHOD = '''private func apply(_ style: DockGalleryStyle) {
        guard !isApplying else { return }
        selectedRaw = style.rawValue
        isApplying = true
        Task { @MainActor in
            let result = await DockGalleryExecutor.shared.apply(style, intensity: glowIntensity)
            isApplying = false
            if result.succeeded {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            EagleNotifications.shared.result(result.succeeded, title: "Dock Gallery", message: result.message)
        }
    }'''
SCREEN_METHOD = '''private func apply(_ style: DockGalleryStyle) {
        EagleDockGalleryBuiltInApplyFlow.start(
            style,
            isApplying: { isApplying },
            selectStyle: { selectedRaw = $0 },
            setApplying: { isApplying = $0 },
            intensity: { glowIntensity },
            apply: {
                let result = await DockGalleryExecutor.shared.apply($0, intensity: $1)
                return EagleDockGalleryOutcome(succeeded: result.succeeded, message: result.message)
            },
            successFeedback: { UINotificationFeedbackGenerator().notificationOccurred(.success) },
            notify: { EagleNotifications.shared.result($0, title: "Dock Gallery", message: $1) }
        )
    }'''
HEADER = '''static func start(
        _ style: EagleDockGalleryBuiltInTheme,
        isApplying: () -> Bool,
        selectStyle: (Int) -> Void,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        intensity: @escaping @MainActor @Sendable () -> Double,
        apply: @escaping @MainActor @Sendable (EagleDockGalleryBuiltInTheme, Double) async -> EagleDockGalleryOutcome,
        successFeedback: @escaping @MainActor @Sendable () -> Void,
        notify: @escaping @MainActor @Sendable (Bool, String) -> Void
    )'''


def inline_builtin_apply_flow(source):
    from verify_eagle_dock_restore_flow import inline_restore_flow
    source = inline_restore_flow(source)
    actual = declaration(source, MARKER)
    assert compact(actual) == compact(SCREEN_METHOD), "Built-in Apply screen callbacks changed"
    return replace_once(source, actual, PREVIOUS_METHOD)


def expected_core():
    method = replace_once(PREVIOUS_METHOD, MARKER, HEADER)
    for old, new in (
        ("!isApplying", "!isApplying()"),
        ("selectedRaw = style.rawValue", "selectStyle(style.rawValue)"),
        ("isApplying = true", "setApplying(true)"),
        ("isApplying = false", "setApplying(false)"),
        ("DockGalleryExecutor.shared.apply(style, intensity: glowIntensity)", "apply(style, intensity())"),
        ("UINotificationFeedbackGenerator().notificationOccurred(.success)", "successFeedback()"),
        ('EagleNotifications.shared.result(result.succeeded, title: "Dock Gallery", message: result.message)', "notify(result.succeeded, result.message)"),
    ):
        method = replace_once(method, old, new)
    return "import Foundation\n@MainActor\nenum EagleDockGalleryBuiltInApplyFlow {\n    " + method + "\n}\n"


def verify_texts(view, core):
    assert hashlib.sha256(inline_builtin_apply_flow(view).encode()).hexdigest() == PREVIOUS_VIEW_SHA, \
        "Screen changed beyond the built-in Apply move (including remote Apply/Restore)"
    assert compact(core) == compact(expected_core()), "Built-in Core differs from counted public flow"


def verify_sources(repo):
    view, core = [(repo / path).read_text() for path in (VIEW_PATH, CORE_PATH)]
    verify_texts(view, core)
    public = subprocess.run(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo,
                            check=True, capture_output=True, text=True, timeout=55).stdout
    method = declaration(public, MARKER)
    assert method == PREVIOUS_METHOD, "Built-in Apply no longer matches the fixed public baseline"
    return method, declaration(view, MARKER)


def negatives(repo):
    view, core = [(repo / path).read_text() for path in (VIEW_PATH, CORE_PATH)]
    completion = '''if result.succeeded {
                successFeedback()
            }
            notify(result.succeeded, result.message)'''
    cases = (
        ("view", "selectedRaw = $0", "selectedRaw = 15"),
        ("view", "isApplying = $0", "isApplying = false"),
        ("view", "intensity: { glowIntensity }", "intensity: { 1.0 }"),
        ("view", "apply($0, intensity: $1)", "apply($0, intensity: 0.0)"),
        ("view", "succeeded: result.succeeded", "succeeded: true"),
        ("view", "message: result.message", 'message: "Applied"'),
        ("view", 'title: "Dock Gallery", message: $1', 'title: "Dock", message: $1'),
        ("core", "guard !isApplying()", "guard isApplying()"),
        ("core", "selectStyle(style.rawValue)\n        setApplying(true)", "setApplying(true)\n        selectStyle(style.rawValue)"),
        ("core", "Task { @MainActor in", "Task.detached { @MainActor in"),
        ("core", "Task { @MainActor in", "let captured = intensity()\n        Task { @MainActor in"),
        ("core", "apply(style, intensity())", "apply(style, 1.0)"),
        ("core", "if result.succeeded", "if !result.succeeded"),
        ("core", "setApplying(false)", "// no reset"),
        ("core", "setApplying(false)\n            " + completion, completion + "\n            setApplying(false)"),
        ("core", "notify(result.succeeded, result.message)", "notify(true, result.message)"),
        ("core", "let result = await apply", "guard !Task.isCancelled else { return }\n            let result = await apply"),
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
        raise AssertionError(f"Accepted built-in Apply regression: {old}")
    # A separate edit in Restore or the executor must not hide behind the new move.
    try:
        verify_texts(view + "\n// unrelated screen change\n", core)
    except AssertionError:
        return len(cases) + 1
    raise AssertionError("Accepted unrelated screen change")


def host(name, method):
    return '''@MainActor struct ''' + name + ''': ApplyHost {
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
    func start(_ style: DockGalleryStyle) { apply(style) }
    ''' + method + "\n}\n"


def main():
    repo = Path(__file__).resolve().parents[1]
    public, screen = verify_sources(repo)
    print(f"PASS: complete counted public built-in flow/screen move; {negatives(repo)} rejected regressions", flush=True)
    sources = [repo / path for path in (
        "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
        "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInTheme.swift",
        "lara/EagleCore/DockGallery/EagleDockGalleryCore.swift", CORE_PATH,
    )]
    fixture = "import Foundation\n" + host("PublicApplyHost", public) + host("OwnedApplyHost", screen)
    with tempfile.TemporaryDirectory(prefix="eagle-builtin-apply-flow-") as directory:
        work = Path(directory)
        hosts = work / "ExactBuiltInApplyHosts.swift"
        hosts.write_text(fixture)
        binary = work / "verify-builtin-apply-flow"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
                        "-default-isolation", "MainActor", "-strict-concurrency=complete",
                        "-warnings-as-errors", "-parse-as-library", *map(str, sources),
                        str(hosts), str(repo / "scripts/verify_eagle_dock_builtin_apply_flow.swift"),
                        "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: actual Core and exact public/current methods; no UI/native executor/network/IPA", flush=True)


if __name__ == "__main__":
    main()
