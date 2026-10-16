#!/usr/bin/env python3
"""Check the bounded shared-Store move and run its real composition in isolation."""
from pathlib import Path
import argparse
import hashlib
import platform
import re
import subprocess
import tempfile
import uuid

SERVICES_PATH = "lara/config/EagleGalleryServices.swift"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
STORE_PATH = "lara/EagleAdapters/DockGallery/EagleDockGalleryStore.swift"
PREVIOUS_VIEW_SHA = "6c579d9ce207fd36e93f46c8d97ec504f472c4d51e0ff82caab5e2db4ddd4c94"
STORE_SHA = "00c8dd2da2ec0d79d37f6e9ff515094f67ff5d104b499ac9803555736e324f13"
VIEW_BINDING = "    @StateObject private var remoteGallery = EagleGalleryServices.dock"
OLD_VIEW_BINDING = "    @StateObject private var remoteGallery = RemoteDockGalleryStore.shared"
FACTORY = '''    static let dock = EagleDockGalleryStore(
        catalogFailureMessage: {
            EagleLocalization.text(
                en: "The online collection could not be loaded.",
                es: "No se pudo cargar la colección en línea."
            )
        },
        diagnostics: { EagleAppDiagnostics.log }
    )'''
EXPECTED_SERVICES = '''import Foundation

/// App-owned composition. The screen observes this one lazily created Store.
@MainActor
enum EagleGalleryServices {
''' + FACTORY + "\n}\n"
OLD_BOOTSTRAP = (
    "private typealias RemoteDockGalleryStore = EagleDockGalleryStore\n\n"
    "private extension EagleDockGalleryStore {\n"
    + FACTORY.replace("static let dock =", "static let shared =") + "\n}\n\n"
)
FIXTURE_ACCESSORS = '''
// Fixture-only typed reads: appended after the complete unchanged Store source.
extension EagleDockGalleryStore {
    func fixtureFailureMessage() -> String { catalogFailureMessage() }
    func fixtureDiagnosticSink() -> (@Sendable (String) -> Void) { diagnostics() }
}
'''


def verify_texts(view, services, store):
    from verify_eagle_dock_apply_flow import inline_apply_flow
    view = inline_apply_flow(view)
    assert services == EXPECTED_SERVICES, "Shared construction, defaults or lazy callbacks changed"
    assert view.count(VIEW_BINDING) == 1, "Screen must observe exactly the same shared Store"
    assert not re.search(r"\b(?:RemoteDockGalleryStore|EagleDockGalleryStore)\b", view), \
        "Screen regained Store ownership, alias or construction"
    anchor = "private final class DockGalleryRemoteCallBox:"
    assert view.count(anchor) == 1
    previous = view.replace(VIEW_BINDING, OLD_VIEW_BINDING, 1)
    previous = previous.replace(anchor, OLD_BOOTSTRAP + anchor, 1)
    assert hashlib.sha256(previous.encode()).hexdigest() == PREVIOUS_VIEW_SHA, \
        "Screen changed beyond the counted Store composition move"
    assert hashlib.sha256(store.encode()).hexdigest() == STORE_SHA, "Store implementation changed"


def verify_sources(repo):
    sources = [(repo / path).read_text() for path in (VIEW_PATH, SERVICES_PATH, STORE_PATH)]
    verify_texts(*sources)
    return sources[1]


def negative_cases(repo):
    view, services, store = [(repo / path).read_text() for path in (VIEW_PATH, SERVICES_PATH, STORE_PATH)]
    mutations = (
        (view.replace("@StateObject private var remoteGallery", "@ObservedObject private var remoteGallery"), services, store),
        (view.replace("EagleGalleryServices.dock", "EagleGalleryServices.other"), services, store),
        (view + "\nprivate let extra = EagleDockGalleryStore()\n", services, store),
        (view + "\n// unrelated screen change\n", services, store),
        (view, services.replace("static let dock", "static var dock"), store),
        (view, services.replace("EagleLocalization.text", "LaraL10n.text"), store),
        (view, services.replace("EagleAppDiagnostics.log", "CurrentArchiveDiagnostics.log"), store),
        (view, services.replace("EagleDockGalleryStore(", "EagleDockGalleryStore(catalogLoader: replacement,"), store),
        (view, services.replace("@MainActor\n", ""), store),
        (view, services, store.replace("var loading = false", "var loading = true")),
    )
    for mutation in mutations:
        try:
            verify_texts(*mutation)
        except AssertionError:
            continue
        raise AssertionError("A composition regression was accepted")
    return len(mutations)


def main():
    from verify_eagle_core_project_membership import APP_CORE_RELATIVE_PATHS, APP_ADAPTER_RELATIVE_PATHS
    from verify_eagle_dock_store_pipeline import run, select_runtime
    from verify_eagle_log_history import BINDING_PATH, verify_manager_sources

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-version", default="26.5")
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    verify_manager_sources(repo)
    print(f"PASS: exact two-edit screen move, unchanged Store/defaults and {negative_cases(repo)} rejected regressions", flush=True)
    if args.source_only:
        return
    architecture = platform.machine()
    assert architecture in ("arm64", "x86_64")
    sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).stdout.strip()
    sources = [repo / path for path in (*APP_CORE_RELATIVE_PATHS, *APP_ADAPTER_RELATIVE_PATHS, SERVICES_PATH, BINDING_PATH)]
    sources.append(repo / "lara/views/new/EaglePressableStyle.swift")
    assert len(sources) == len(set(sources)), "Compile each production source once"
    with tempfile.TemporaryDirectory(prefix="eagle-gallery-services-") as directory:
        work = Path(directory).resolve()
        binary = work / "verify-gallery-services"
        fixture_store = work / "ExactStoreWithReadOnlyAccessors.swift"
        fixture_store.write_text((repo / STORE_PATH).read_text() + FIXTURE_ACCESSORS)
        sources = [fixture_store if path == repo / STORE_PATH else path for path in sources]
        assert sources.count(fixture_store) == 1
        run([
            "xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5",
            "-default-isolation", "MainActor", "-strict-concurrency=complete",
            "-warnings-as-errors", "-parse-as-library",
            "-target", f"{architecture}-apple-ios16.0-simulator", "-sdk", sdk,
            *map(str, sources), str(repo / "scripts/verify_eagle_gallery_services.swift"),
            "-o", str(binary),
        ])
        print("PASS: unchanged Store body with fixture-only typed reads, real services/localization/delivery; no screen/manager/native engine", flush=True)
        runtime, device_type = select_runtime(args.runtime_version, architecture)
        device = None
        try:
            created = run(["xcrun", "simctl", "create", f"Eagle-Gallery-Services-QA-{uuid.uuid4().hex[:8]}",
                           device_type, runtime["identifier"]]).stdout.strip()
            device = str(uuid.UUID(created)).upper()
            print(f"Temporary iOS {runtime['version']} Simulator: {device}", flush=True)
            run(["xcrun", "simctl", "boot", device])
            for attempt in range(3):
                try:
                    run(["xcrun", "simctl", "bootstatus", device, "-b"])
                    break
                except subprocess.TimeoutExpired:
                    if attempt == 2:
                        raise
                    print("Temporary simulator still booting", flush=True)
            result = run(["xcrun", "simctl", "spawn", device, str(binary)])
            print(result.stdout.strip(), flush=True)
        finally:
            if device is not None:
                try:
                    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False,
                                   timeout=55, capture_output=True, text=True)
                finally:
                    run(["xcrun", "simctl", "delete", device])
                    print(f"Removed temporary Simulator: {device}", flush=True)


if __name__ == "__main__":
    main()
