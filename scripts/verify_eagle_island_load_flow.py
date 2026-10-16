#!/usr/bin/env python3
"""Verify Island screen loading against the public flow, with no network/native calls."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/IslandGalleryPresentation.swift"
CORE = "lara/EagleCore/IslandGallery/EagleIslandGalleryLoadFlow.swift"
MARKER = "private func loadCatalog(force: Bool = false) async"
BRIDGE = '''private func loadCatalog(force: Bool = false) async {
        await EagleIslandGalleryLoadFlow.load(
            force: force,
            readLoading: { loading },
            writeLoading: { loading = $0 },
            fetch: { try await IslandLiveMedia.loadCatalog(force: $0) },
            writeThemes: { liveThemes = $0 },
            writeFailed: { loadFailed = $0 },
            restoreSelection: { restoreSelection() },
            synchronizeSelection: { synchronizeSelection() }
        )
    }'''
PREFIX = '''import Foundation

/// Coordinates screen loading and recovery; transport and UI state stay injected.
/// Runs in the caller's task, preserving cancellation and main-actor ordering.
@MainActor
enum EagleIslandGalleryLoadFlow {
    '''
HEADER = '''static func load<Theme: Sendable>(
        force: Bool = false,
        readLoading: () -> Bool,
        writeLoading: (Bool) -> Void,
        fetch: @MainActor (Bool) async throws -> [Theme],
        writeThemes: ([Theme]) -> Void,
        writeFailed: (Bool) -> Void,
        restoreSelection: () -> Void,
        synchronizeSelection: () -> Void
    ) async'''


def original():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    return declaration(public, MARKER)


def inline_load_flow(view):
    from verify_eagle_island_action_flow import inline_action_flow
    view = inline_action_flow(view)
    return replace_once(view, BRIDGE, original())


def expected_core():
    method = original()
    for before, after in (
        (MARKER, HEADER), ("guard !loading", "guard !readLoading()"),
        ("loading = true", "writeLoading(true)"), ("loading = false", "writeLoading(false)"),
        ("IslandLiveMedia.loadCatalog(force: force)", "fetch(force)"),
        ("liveThemes = themes", "writeThemes(themes)"),
        ("loadFailed = false", "writeFailed(false)"), ("loadFailed = true", "writeFailed(true)"),
    ):
        method = replace_once(method, before, after)
    return PREFIX + method + "\n}\n"


def verify_texts(view, core):
    assert hashlib.sha256(inline_load_flow(view).encode()).hexdigest() == \
        "de94ea7f78da18d4de3937196592fc6ef158b6b91f45ef7e67cee6fc6d637d38", "Unrelated screen change"
    assert core == expected_core(), "Flow differs from counted public body/actor/signature"


def verify_sources(repo):
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    mutations = [
        (0, "force: force,\n            readLoading", "force: false,\n            readLoading"),
        (0, "readLoading: { loading }", "readLoading: { false }"),
        (0, "writeThemes: { liveThemes = $0 }", "writeThemes: { _ in }"),
        (0, "writeFailed: { loadFailed = $0 }", "writeFailed: { _ in }"),
        (0, "restoreSelection: { restoreSelection() }", "restoreSelection: {}"),
        (0, "synchronizeSelection: { synchronizeSelection() }", "synchronizeSelection: {}"),
        (0, '.task { await loadCatalog() }', '.task { await loadCatalog(force: true) }'),
        (1, "guard !readLoading()", "guard readLoading()"),
        (1, "defer { writeLoading(false) }", "writeLoading(false)"),
        (1, "writeLoading(true)", "writeLoading(false)"),
        (1, "fetch(force)", "fetch(false)"),
        (1, "guard !Task.isCancelled else { return }", "// cancellation removed"),
        (1, "if !Task.isCancelled { writeFailed(true) }", "writeFailed(true)"),
        (1, "writeFailed(false)", "writeFailed(true)"),
        (1, "restoreSelection()\n            synchronizeSelection()", "synchronizeSelection()\n            restoreSelection()"),
        (1, "@MainActor\nenum", "nonisolated enum"),
    ]
    for index, before, after in mutations:
        texts = [view, core]
        texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation: {before}")
    try:
        verify_texts(view + "\n// unrelated\n", core)
    except AssertionError:
        print(f"PASS: public body, exact screen reversal and {len(mutations)+1} rejected mutations", flush=True)
        return
    raise AssertionError("Accepted unrelated screen edit")


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    # The reference is the actual pinned public method. Only the transport is fake.
    old = replace_once(original(), "IslandLiveMedia.loadCatalog(force: force)", "fetch(force: force)")
    new = replace_once(BRIDGE, "IslandLiveMedia.loadCatalog(force: $0)", "fetch(force: $0)")
    hosts = "\n".join(
        "@MainActor final class " + name + ": Host {\n"
        "    override func run(_ force: Bool) async { await loadCatalog(force: force) }\n"
        "    " + method + "\n}\n"
        for name, method in (("PublicHost", old), ("OwnedHost", new))
    )
    fixture = (repo / "scripts/verify_eagle_island_load_flow.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="eagle-island-load-flow-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture + "\n" + hosts)
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
