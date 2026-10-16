#!/usr/bin/env python3
"""Exercise owned log history and exact manager/consumer projections, not native access."""
from pathlib import Path
import subprocess
import tempfile

from verify_eagle_core_module_build import declaration

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
MANAGER_PATH = "lara/classes/laramgr.swift"
HISTORY_PATH = "lara/EagleAdapters/Diagnostics/EagleLogHistory.swift"
DELIVERY_PATH = "lara/EagleAdapters/Diagnostics/EagleDiagnosticDelivery.swift"
BINDING_PATH = "lara/config/EagleAppDiagnostics.swift"
ICON_PATH = "lara/classes/tweaks/darkboard/IconThemeManager.swift"
HISTORY_BRIDGE = '''    private let diagnostics: EagleDiagnosticDelivery
    private var logHistory: EagleLogHistory { diagnostics.history }
    private var logHistoryObservation: AnyCancellable?
    var log: String {
        get { logHistory.text }
        set { logHistory.text = newValue }
    }'''
OBSERVATION_INIT = '''    init(diagnostics: EagleDiagnosticDelivery? = nil) {
        self.diagnostics = diagnostics ?? EagleAppDiagnostics.makeDelivery()
        logHistoryObservation = logHistory.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }'''
EXPECTED_HISTORY = '''import Combine

/// In-memory history only. Delivery queues and file logging belong to callers.
@MainActor
final class EagleLogHistory: ObservableObject {
    @Published var text: String = ""

    func append(_ message: String) {
        text += message + "\\n"
        if text.utf8.count > 256 * 1024 { text = String(text.suffix(128 * 1024)) }
    }
}
'''
EXPECTED_DELIVERY = '''import Foundation

/// Delivers history and logger updates on the existing deferred main-queue hop.
@MainActor
final class EagleDiagnosticDelivery {
    let history: EagleLogHistory
    private let write: @MainActor @Sendable (String) -> Void

    init(history: EagleLogHistory, write: @escaping @MainActor @Sendable (String) -> Void) {
        self.history = history
        self.write = write
    }

    func enqueue(_ message: String, retaining owner: AnyObject? = nil) {
        DispatchQueue.main.async { [self, owner] in
            history.append(message)
            write(message)
            withExtendedLifetime(owner) {}
        }
    }
}
'''
EXPECTED_BINDING = '''import Foundation

/// App composition only; neither creating a channel nor logging needs an access manager.
@MainActor
enum EagleAppDiagnostics {
    static let shared = makeDelivery()

    static func makeDelivery() -> EagleDiagnosticDelivery {
        EagleDiagnosticDelivery(history: EagleLogHistory(), write: { globallogger.log($0) })
    }

    nonisolated static let log: @Sendable (String) -> Void = { message in
        Task { @MainActor in
            shared.enqueue(message)
        }
    }
}
'''
EXPECTED_ARCHIVE_BRIDGE = '''//
//  Compatibility adapter for existing archive call sites.
//  The archive implementation lives in EagleCore/Archives/EagleZIPArchive.swift.
//  Original archive author: neonmodder123, 17/05/2026.
//

import Foundation

// Keep existing archive callers compatible with the owned app diagnostic route.
typealias CurrentArchiveDiagnostics = EagleAppDiagnostics

nonisolated extension ZipArchive {
    public convenience init(data: Data) throws {
        try self.init(data: data, log: CurrentArchiveDiagnostics.log)
    }
}

public func createZipArchive(fromDirectory sourceURL: URL, to destinationURL: URL, compressionMethod: UInt16 = 0) throws {
    try createZipArchive(
        fromDirectory: sourceURL,
        to: destinationURL,
        compressionMethod: compressionMethod,
        log: CurrentArchiveDiagnostics.log
    )
}
'''


def public_source(repo, path):
    return subprocess.run(
        ["git", "show", f"{PUBLIC_COMMIT}:{path}"], cwd=repo,
        check=True, capture_output=True, text=True, timeout=55,
    ).stdout


def replace_once(source, old, new):
    assert source.count(old) == 1, f"Manager history boundary changed: {old}"
    return source.replace(old, new)


def verify_manager_sources(repo):
    public = public_source(repo, MANAGER_PATH)
    expected = public
    for old, new in (
        ('    @Published var log: String = ""', HISTORY_BRIDGE),
        ('    init() {}', OBSERVATION_INIT),
        ('    static let shared = laramgr()', '    static let shared = laramgr(diagnostics: EagleAppDiagnostics.shared)'),
        ('            log += batch + "\\n"\n'
         '            if log.utf8.count > 256 * 1024 { log = String(log.suffix(128 * 1024)) }',
         '            logHistory.append(batch)'),
        (declaration(public, '    func logmsg(_ message: String)'),
         '    func logmsg(_ message: String) {\n        diagnostics.enqueue(message, retaining: self)\n    }'),
    ):
        expected = replace_once(expected, old, new)
    current = (repo / MANAGER_PATH).read_text()
    assert current == expected, "Manager changed beyond history/delivery ownership and binding"
    assert (repo / HISTORY_PATH).read_text() == EXPECTED_HISTORY, "History state/append policy changed"
    assert (repo / DELIVERY_PATH).read_text() == EXPECTED_DELIVERY, "Delivery order, lifetime or queue changed"
    assert (repo / BINDING_PATH).read_text() == EXPECTED_BINDING, "Shared/private history or lazy logger wiring changed"
    assert (repo / "lara/classes/zipmgr.swift").read_text() == EXPECTED_ARCHIVE_BRIDGE, "Archive defaults or diagnostic alias changed"
    from verify_eagle_gallery_services import verify_sources as verify_gallery_services
    services = verify_gallery_services(repo)
    assert services.count("diagnostics: { EagleAppDiagnostics.log }") == 1
    assert "CurrentArchiveDiagnostics" not in services
    icons = (repo / ICON_PATH).read_text()
    # The October 16 contrast pass changes only the fixup sheet's label rendering.
    # Reverse that exact modifier in context; retain byte-for-byte action, disabled
    # predicate and all icon/ZIP/history comparisons against the frozen public file.
    icons = replace_once(icons, '''                .buttonStyle(.borderedProminent)
                // The contrasting colour on the black/white fill, grey while disabled.
                .eagleProminentLabel()
                .disabled(manager.isFixingUp)''', '''                .buttonStyle(.borderedProminent)
                .disabled(manager.isFixingUp)''')
    assert icons == public_source(repo, ICON_PATH), "Direct icon/ZIP history writers changed"
    # The old projected $log stream has no production consumers. General manager
    # objectWillChange is preserved and tested; no new public publisher is invented.
    consumers = subprocess.run(["rg", "-n", r"\$log\b", "lara", "--glob", "*.swift"], cwd=repo, capture_output=True, text=True)
    assert consumers.returncode == 1, "A projected log publisher consumer needs an explicit migration"
    return public, current, icons


def host_source(source, name, owned):
    storage = HISTORY_BRIDGE if owned else '    @Published var log: String = ""'
    initialization = OBSERVATION_INIT if owned else '    init() {}'
    shared = f"    static let shared = {name}(diagnostics: EagleAppDiagnostics.shared)" if owned else f"    static let shared = {name}()"
    # These are the exact methods after whole-file source parity is verified.
    methods = "\n".join(declaration(source, marker) for marker in (
        "    func logmsg(_ message: String)", "    private func flushPendingDSUI()",
    ))
    return f'''@MainActor final class {name}: ObservableObject, HistoryHost {{
{storage}
{shared}
    @Published var dsprogress: Double = 0
    private let dsUICallbackLock = NSLock()
    private var pendingDSLogLines: [String] = []
    private var pendingDSProgress: Double?
    private var dsUIFlushScheduled = false
{initialization}
{methods}
    func flush(lines: [String], progress: Double?) {{
        pendingDSLogLines = lines
        pendingDSProgress = progress
        dsUIFlushScheduled = true
        flushPendingDSUI()
        precondition(pendingDSLogLines.isEmpty && pendingDSProgress == nil && !dsUIFlushScheduled)
    }}
}}
'''


def main():
    repo = Path(__file__).resolve().parents[1]
    public, current, icons = verify_manager_sources(repo)
    print("PASS: exact history/delivery move, app/ZIP/Gallery bindings and unchanged direct icon/ZIP writers", flush=True)
    fixture = "import Foundation\nimport Combine\n\n"
    fixture += "typealias CurrentArchiveDiagnostics = EagleAppDiagnostics\n\n"
    fixture += host_source(public, "PublicHistoryHost", owned=False)
    fixture += host_source(current, "OwnedHistoryHost", owned=True)
    fixture += '''@MainActor final class IconHistoryWriter<Host: HistoryHost> {
    let mgr: Host
    init(_ manager: Host) { mgr = manager }
'''
    for marker in ("    func icon_logmsg(_ message: String)", "    func unzip_logmsg(_ message: String)"):
        fixture += declaration(icons, marker) + "\n"
    fixture += "}\n"
    with tempfile.TemporaryDirectory(prefix="eagle-log-history-") as directory:
        work = Path(directory)
        source = work / "ExactHistoryHosts.swift"
        source.write_text(fixture)
        binary = work / "history-checks"
        subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
            "-default-isolation", "MainActor", "-strict-concurrency=complete",
            "-warnings-as-errors", "-parse-as-library", str(repo / HISTORY_PATH),
            str(repo / DELIVERY_PATH), str(repo / BINDING_PATH),
            str(source), str(repo / "scripts/verify_eagle_log_history.swift"), "-o", str(binary),
        ], check=True, timeout=55)
        subprocess.run([str(binary)], check=True, timeout=55)
    print("PASS: no native manager/executor compiled or executed, no files or app logger accessed", flush=True)


if __name__ == "__main__":
    main()
