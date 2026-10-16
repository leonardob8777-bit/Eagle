#!/usr/bin/env python3
"""Verify remote Apply orchestration using recording ports, never native execution."""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
CORE_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryApplyFlow.swift"
MARKER = "private func applyRemote(_ theme: RemoteDockGalleryTheme)"
PREVIOUS_VIEW_SHA = "ad6c0da0b8f87017c86903b84d8b9d66e892973ecad1bf4e8f4e6cf6d762c115"
REQUEST_CALL = '''let result = await EagleDockGalleryCore(port: CurrentDockGalleryPort())
                    .applyRemote(EagleDockGalleryApplyRequest(
                        theme: theme,
                        directory: directory,
                        intensity: requestedIntensity
                    ))'''
PUBLIC_REQUEST = "let result = await DockGalleryExecutor.shared.applyRemote(theme, directory: directory, intensity: requestedIntensity)"
FAILURE_TEXT = '''LaraL10n.text(
                    en: "The original theme package could not be downloaded or verified. Nothing changed.",
                    es: "No se pudo descargar o verificar el paquete original. Nada cambió."
                )'''
PREVIOUS_METHOD = '''private func applyRemote(_ theme: RemoteDockGalleryTheme) {
        guard !isApplying, remoteGallery.downloadingID == nil else { return }
        let requestedIntensity = glowIntensity
        isApplying = true
        Task { @MainActor in
            do {
                let directory = try await remoteGallery.prepare(theme)
                ''' + REQUEST_CALL + '''
                if result.succeeded {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                EagleNotifications.shared.result(result.succeeded, title: "Dock Gallery", message: result.message)
            } catch {
                EagleNotifications.shared.result(false, title: "Dock Gallery", message: ''' + FAILURE_TEXT + ''')
            }
            isApplying = false
        }
    }'''
SCREEN_METHOD = '''private func applyRemote(_ theme: RemoteDockGalleryTheme) {
        EagleDockGalleryApplyFlow.start(
            theme,
            isApplying: { isApplying },
            downloadingID: { remoteGallery.downloadingID },
            intensity: { glowIntensity },
            setApplying: { isApplying = $0 },
            prepare: { try await remoteGallery.prepare($0) },
            apply: {
                await EagleDockGalleryCore(port: CurrentDockGalleryPort()).applyRemote($0)
            },
            successFeedback: { UINotificationFeedbackGenerator().notificationOccurred(.success) },
            notify: { EagleNotifications.shared.result($0, title: "Dock Gallery", message: $1) },
            preparationFailureMessage: {
                ''' + FAILURE_TEXT + '''
            }
        )
    }'''
HEADER = '''static func start(
        _ theme: EagleDockGalleryTheme,
        isApplying: () -> Bool,
        downloadingID: () -> String?,
        intensity: () -> Double,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        prepare: @escaping @MainActor @Sendable (EagleDockGalleryTheme) async throws -> URL,
        apply: @escaping @MainActor @Sendable (EagleDockGalleryApplyRequest) async -> EagleDockGalleryOutcome,
        successFeedback: @escaping @MainActor @Sendable () -> Void,
        notify: @escaping @MainActor @Sendable (Bool, String) -> Void,
        preparationFailureMessage: @escaping @MainActor @Sendable () -> String
    )'''


def declaration(source, marker):
    assert source.count(marker) == 1, f"Expected one declaration: {marker}"
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        assert end < len(source)
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def replace_once(source, old, new):
    assert source.count(old) == 1, f"Apply seam changed: {old}"
    return source.replace(old, new, 1)


def compact(source):
    return "".join(re.sub(r"//[^\n]*", "", source).split())


def inline_apply_flow(source):
    from verify_eagle_dock_builtin_apply_flow import inline_builtin_apply_flow
    source = inline_builtin_apply_flow(source)
    actual = declaration(source, MARKER)
    assert compact(actual) == compact(SCREEN_METHOD), "Screen Apply callbacks/order changed"
    return replace_once(source, actual, PREVIOUS_METHOD)


def expected_core():
    method = replace_once(PREVIOUS_METHOD, MARKER, HEADER)
    for old, new in (
        ("!isApplying, remoteGallery.downloadingID == nil", "!isApplying(), downloadingID() == nil"),
        ("let requestedIntensity = glowIntensity", "let requestedIntensity = intensity()"),
        ("isApplying = true", "setApplying(true)"),
        ("isApplying = false", "setApplying(false)"),
        ("remoteGallery.prepare(theme)", "prepare(theme)"),
        (REQUEST_CALL, '''let result = await apply(EagleDockGalleryApplyRequest(
                    theme: theme,
                    directory: directory,
                    intensity: requestedIntensity
                ))'''),
        ("UINotificationFeedbackGenerator().notificationOccurred(.success)", "successFeedback()"),
        ('EagleNotifications.shared.result(result.succeeded, title: "Dock Gallery", message: result.message)', "notify(result.succeeded, result.message)"),
        ('EagleNotifications.shared.result(false, title: "Dock Gallery", message: ' + FAILURE_TEXT + ')', "notify(false, preparationFailureMessage())"),
    ):
        method = replace_once(method, old, new)
    return "import Foundation\n@MainActor\nenum EagleDockGalleryApplyFlow {\n    " + method + "\n}\n"


def verify_texts(view, core):
    assert hashlib.sha256(inline_apply_flow(view).encode()).hexdigest() == PREVIOUS_VIEW_SHA, \
        "Screen changed beyond the one remote Apply method"
    assert compact(core) == compact(expected_core()), "Core orchestration differs from counted public flow"


def verify_sources(repo):
    view, core = [(repo / path).read_text() for path in (VIEW_PATH, CORE_PATH)]
    verify_texts(view, core)
    public = subprocess.run(["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo,
                            check=True, capture_output=True, text=True, timeout=55).stdout
    method = declaration(public, MARKER)
    assert replace_once(method, PUBLIC_REQUEST, REQUEST_CALL) == PREVIOUS_METHOD, \
        "Pre-extraction remote Apply no longer matches the fixed public baseline"
    return method, declaration(view, MARKER)


def negatives(repo):
    view, core = [(repo / path).read_text() for path in (VIEW_PATH, CORE_PATH)]
    cases = (
        ("view", "intensity: { glowIntensity }", "intensity: { 1.0 }"),
        ("view", "isApplying = $0", "isApplying = false"),
        ("view", 'title: "Dock Gallery", message: $1', 'title: "Dock", message: $1'),
        ("core", "!isApplying(), downloadingID() == nil", "downloadingID() == nil, !isApplying()"),
        ("core", "if result.succeeded", "if !result.succeeded"),
        ("core", "intensity: requestedIntensity", "intensity: intensity()"),
        ("core", "notify(false, preparationFailureMessage())", "notify(true, preparationFailureMessage())"),
        ("core", "setApplying(true)", "setApplying(false)"),
        ("core", "Task { @MainActor in", "Task.detached { @MainActor in"),
        ("core", "notify(result.succeeded, result.message)", "setApplying(false)\n                notify(result.succeeded, result.message)"),
        ("core", "let directory = try await prepare(theme)", "try Task.checkCancellation()\n                let directory = try await prepare(theme)"),
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
        raise AssertionError(f"Accepted Apply regression: {old}")
    return len(cases)


def host(name, method):
    return '''@MainActor struct ''' + name + ''': ApplyHost {
    let context: FlowContext
    var isApplying: Bool {
        get { context.readBusy() }
        nonmutating set { context.writeBusy(newValue) }
    }
    var glowIntensity: Double { context.readIntensity() }
    var remoteGallery: RecordingGallery { context.gallery }
    func start(_ theme: RemoteDockGalleryTheme) { applyRemote(theme) }
    ''' + method + "\n}\n"


def main():
    repo = Path(__file__).resolve().parents[1]
    public, screen = verify_sources(repo)
    print(f"PASS: counted complete public flow/screen move and {negatives(repo)} rejected Apply regressions", flush=True)
    sources = [repo / path for path in (
        "lara/EagleCore/DockGallery/EagleDockGalleryTheme.swift",
        "lara/EagleCore/DockGallery/EagleDockGalleryCore.swift", CORE_PATH,
    )]
    fixture = "import Foundation\n" + host("PublicApplyHost", public) + host("OwnedApplyHost", screen)
    with tempfile.TemporaryDirectory(prefix="eagle-apply-flow-") as directory:
        work = Path(directory)
        hosts = work / "ExactApplyHosts.swift"
        hosts.write_text(fixture)
        binary = work / "verify-apply-flow"
        subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
                        "-default-isolation", "MainActor", "-strict-concurrency=complete",
                        "-warnings-as-errors", "-parse-as-library", *map(str, sources),
                        str(hosts), str(repo / "scripts/verify_eagle_dock_apply_flow.swift"),
                        "-o", str(binary)], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: isolated real Core and exact screen callbacks; no UI/native executor/network/IPA", flush=True)


if __name__ == "__main__":
    main()
