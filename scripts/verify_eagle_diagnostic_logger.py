#!/usr/bin/env python3
"""Check owned diagnostics against the public logger in temporary directories.

Only fixture subprocess stdout/stderr and temporary log files are captured.
No app is installed; the app global logger and Prepare are never initialized.
The service keeps the existing app's Swift 5 concurrency mode. The separate
Core/adapter module gate retains its stronger strict-concurrency requirements.
"""
from pathlib import Path
import hashlib
import subprocess
import tempfile

from verify_eagle_core_project_membership import inspect_membership, load_project
from verify_eagle_log_history import verify_manager_sources

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
LEGACY_PATH = "lara/classes/Logger.swift"
OWNED_PATH = "lara/EagleServices/Diagnostics/EagleDiagnosticLogger.swift"
EXPECTED_BRIDGE = '''// Compatibility names for existing log consumers; implementation is Eagle-owned.
typealias Logger = EagleDiagnosticLogger

let globallogger = Logger()

extension EagleDiagnosticLogger {
    convenience init() {
        self.init(disableLogDividersKey: EaglePreferenceKeys.disableLogDividers)
    }
}
'''


def public_source(repo, path):
    return subprocess.run(
        ["git", "show", f"{PUBLIC_COMMIT}:{path}"], cwd=repo,
        check=True, capture_output=True, text=True, timeout=55,
    ).stdout


def projected_source(public, name):
    for old, new in (
        ("//  Logger.swift", f"//  {name}.swift"),
        ("let globallogger = Logger()\n\n", ""),
        ("class Logger: ObservableObject {", f"class {name}: ObservableObject {{"),
        ("    private let nobullshitkey = EaglePreferenceKeys.disableLogDividers",
         "    private let nobullshitkey: String\n    private let logDirectory: URL?"),
        ("    init() {\n        setuplogfile()\n    }",
         "    init(disableLogDividersKey: String, logDirectory: URL? = nil) {\n"
         "        self.nobullshitkey = disableLogDividersKey\n"
         "        self.logDirectory = logDirectory\n        setuplogfile()\n    }"),
        ("        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]",
         "        let docs = logDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]"),
    ):
        assert public.count(old) == 1, f"Public logger projection changed: {old}"
        public = public.replace(old, new)
    return public


def verify_sources(repo):
    public = public_source(repo, LEGACY_PATH)
    owned = (repo / OWNED_PATH).read_text()
    assert owned == projected_source(public, "EagleDiagnosticLogger"), \
        "Logging, queues, filtering, capture, rotation or original attribution changed"
    assert (repo / LEGACY_PATH).read_text() == EXPECTED_BRIDGE, \
        "Legacy logger alias, single global instance or default preference binding changed"
    assert all(name not in owned for name in (
        "laramgr", "RemoteCall", "DarkSword", "EaglePreferenceKeys", "globallogger",
    )), "Owned logger depends on app or native-access implementations"
    # The manager's history move is checked as a complete counted projection;
    # delivery, file consumers and lifecycle retain their existing connection.
    verify_manager_sources(repo)
    for path in (
        "lara/views/app/LogsView.swift",
        "lara/classes/EaglePrepareDiagnostics.swift", "lara/config/EaglePreferenceMigration.swift",
    ):
        assert (repo / path).read_text() == public_source(repo, path), f"Unrelated consumer changed: {path}"
    # Reviewed 1.0.6 root: welcome/splash, Chinese and visual controls changed.
    # Pin the complete reviewed file AND compare logging lifecycle to public;
    # no blanket exemption for future root edits or changed logger ordering.
    root = (repo / "lara/lara.swift").read_text()
    assert hashlib.sha256(root.encode()).hexdigest() == "3b1f160f6b99ea7370299a2638d6546517f125789a7955a77aca8bf5465577bf"
    from verify_eagle_dock_apply_flow import declaration, replace_once
    lifecycle = declaration(root, "private func handleScenePhase(")
    lifecycle = replace_once(lifecycle, '''                if !showingStableUpdate {
                    EagleSceneManager.shared.applyPendingShortcutIfNeeded()
                }''', '''                EagleSceneManager.shared.applyPendingShortcutIfNeeded()''')
    assert lifecycle == declaration(public_source(repo, "lara/lara.swift"), "private func handleScenePhase(")
    assert root.count("globallogger.capture()") == 2 and root.count("globallogger.flushToDisk()") == 1
    membership = inspect_membership(load_project(repo), repo)
    assert membership["service_count"] == 3 and OWNED_PATH in membership["source_paths"]
    return public


def run(command, **kwargs):
    return subprocess.run(command, check=True, timeout=55, **kwargs)


def main():
    repo = Path(__file__).resolve().parents[1]
    public = verify_sources(repo)
    print("PASS: whole public logger parity, exact app bridge and unchanged consumers", flush=True)
    with tempfile.TemporaryDirectory(prefix="eagle-diagnostic-logger-") as directory:
        work = Path(directory)
        reference = work / "PublicDiagnosticLogger.swift"
        reference.write_text(projected_source(public, "PublicDiagnosticLogger"))
        # Match the app's concurrency mode without changing its capture behavior.
        # Complete strict-concurrency checking of the inherited FileHandle
        # callback is a separate, still-unresolved baseline limitation.
        flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-parse-as-library"]
        executable = work / "logger-checks"
        run([
            "xcrun", "--sdk", "macosx", "swiftc", *flags, str(repo / OWNED_PATH),
            str(repo / LEGACY_PATH), str(repo / "lara/config/EaglePreferenceMigration.swift"),
            str(reference), str(repo / "scripts/verify_eagle_diagnostic_logger.swift"),
            "-o", str(executable),
        ])
        for mode in ("presentation", "rotation", "owned-capture", "public-capture"):
            fixture = work / mode
            fixture.mkdir()
            run([str(executable), mode, str(fixture)])

        sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
        for name, optimization in (("Debug", "-Onone"), ("Release", "-O")):
            module = "EagleDiagnostics" + name
            output = work / ("lib" + module + ".a")
            run([
                "xcrun", "--sdk", "iphoneos", "swiftc", *flags, optimization,
                "-target", "arm64-apple-ios16.0", "-sdk", sdk, "-emit-module",
                "-emit-library", "-static", "-module-name", module,
                "-emit-module-path", str(work / (module + ".swiftmodule")),
                str(repo / OWNED_PATH), "-o", str(output),
            ])
            symbols = run(["xcrun", "nm", "-u", str(output)], capture_output=True, text=True).stdout
            assert all(name not in symbols for name in ("laramgr", "RemoteCall", "DarkSword", "EaglePreferenceKeys"))
            print(f"PASS: isolated {name} iOS diagnostic service, original Swift 5 concurrency mode", flush=True)
    print("PASS: temporary logs/fixtures removed; no device, IPA or app-global logger initialization", flush=True)


if __name__ == "__main__":
    main()
