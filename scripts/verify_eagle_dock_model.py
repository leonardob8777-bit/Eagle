#!/usr/bin/env python3
"""Compare the exact production Dock model to its public, UI-bound predecessor."""
from pathlib import Path
import re
import subprocess
import tempfile
from verify_eagle_dock_builtin_theme import verify_sources
from verify_eagle_dock_media_filter import verify_sources as verify_media_filter_sources
from verify_eagle_dock_favorites import verify_sources as verify_favorites_sources
from verify_eagle_dock_collection import verify_sources as verify_collection_sources
from verify_eagle_dock_selection import verify_sources as verify_selection_sources
from verify_eagle_dock_visit_order import verify_sources as verify_visit_order_sources
from verify_eagle_dock_selection_memory import verify_sources as verify_selection_memory_sources
from verify_eagle_dock_session import verify_sources as verify_session_sources
from verify_eagle_localization import verify_sources as verify_localization_sources
from verify_eagle_gallery_services import verify_sources as verify_gallery_services

repo = Path(__file__).resolve().parents[1]
core_dir = repo / "lara/EagleCore/DockGallery"
model = core_dir / "EagleDockGalleryTheme.swift"
core = core_dir / "EagleDockGalleryCore.swift"
view = repo / "lara/views/new/DockGalleryView.swift"
baseline = subprocess.check_output([
    "git", "show", "823ab22c60ac6289314577034085784b8fdc24a4:lara/views/new/DockGalleryView.swift"
], cwd=repo, text=True)


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


original = declaration(baseline, "private struct RemoteDockGalleryTheme:")
original = original.replace("private struct RemoteDockGalleryTheme:", "nonisolated struct BaselineDockGalleryTheme:")
ui_properties = [line for line in original.splitlines() if any(
    f"var {name}:" in line for name in ["localizedTitle", "localizedSubtitle", "color"]
)]
for line in ui_properties:
    original = original.replace(line + "\n", "")
support = declaration(baseline, "private static func isSupported(_ theme:")
support_body = support[support.index("{") + 1:-1].replace("theme.", "")
original = original[:-1] + "    var isSupportedPackage: Bool {" + support_body + "    }\n}"

# Only counted Core/adapter delegations may differ in the store. Its complete
# owned declaration and UI construction are compared with this normalized public
# reference. The executor is unchanged and is only inspected, never compiled.
current = view.read_text()
# Built-in value metadata is a separate, normalized public boundary. Inspect it
# without compiling any UI or native executor as part of this contract gate.
verify_sources(repo)
verify_media_filter_sources(repo)
verify_favorites_sources(repo)
verify_collection_sources(repo)
verify_selection_sources(repo)
verify_visit_order_sources(repo)
verify_selection_memory_sources(repo)
verify_session_sources(repo)
verify_localization_sources(repo)
owned_store_source = (repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryStore.swift").read_text()
owned_store_code = re.sub(r"//[^\n]*", "", owned_store_source)
owned_store = declaration(owned_store_code, "@MainActor\nfinal class EagleDockGalleryStore:")
assert owned_store_code.replace(owned_store, "", 1).split() == [
    "import", "Foundation", "import", "Combine"
], "Owned Store gained imports or external code"
assert "private final class RemoteDockGalleryStore:" not in current, "Screen still owns a Store class"
verify_gallery_services(repo)
for marker in ["@MainActor\nprivate final class RemoteDockGalleryStore:", "@MainActor\nprivate final class DockGalleryExecutor {"]:
    old = declaration(baseline, marker)
    new = owned_store if "Store" in marker else declaration(current, marker)
    if "Store" in marker:
        old = old.replace(support, "private static func isSupported(_ theme: RemoteDockGalleryTheme) -> Bool {\n        theme.isSupportedPackage\n    }")
        inventory = '''        let expected = Set((1...theme.frameCount).map { String(format: "frame%02d.png", $0) })
        let files = archive.entries.filter { !$0.isDirectory }
        guard Set(files.map(\\.path)) == expected else { throw URLError(.cannotDecodeContentData) }'''
        delegated = '''        let files = try EagleDockGalleryPackageInventory.frameFiles(
            in: archive.entries, frameCount: theme.frameCount
        )'''
        assert old.count(inventory) == 1, "Public inventory rule changed"
        old = old.replace(inventory, delegated)
        download = '''        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count == theme.byteCount,
              data.count <= 30 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(theme.sha256) == .orderedSame else {
            throw URLError(.secureConnectionFailed)
        }'''
        validated = '''        try EagleDockGalleryPackageValidation.validateDownload(
            data,
            httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
            expectedByteCount: theme.byteCount,
            expectedSHA256: theme.sha256
        )'''
        assert old.count(download) == 1, "Public download validation changed"
        old = old.replace(download, validated)
        decoded = '''                guard let image = UIImage(data: frameData),
                      image.cgImage?.width == theme.width,
                      image.cgImage?.height == theme.height else {'''
        checked = '''                guard let image = UIImage(data: frameData),
                      EagleDockGalleryFrameDimensions.matches(
                          width: image.cgImage?.width,
                          height: image.cgImage?.height,
                          expectedWidth: theme.width,
                          expectedHeight: theme.height
                      ) else {'''
        cached = '''            return image.cgImage?.width == theme.width && image.cgImage?.height == theme.height'''
        dimensions = '''            return EagleDockGalleryFrameDimensions.matches(
                width: image.cgImage?.width,
                height: image.cgImage?.height,
                expectedWidth: theme.width,
                expectedHeight: theme.height
            )'''
        assert old.count(decoded) == 1, "Public prepare image check changed"
        assert old.count(cached) == 1, "Public cache image check changed"
        old = old.replace(decoded, checked).replace(cached, dimensions)
        catalog = '''            let catalog = try JSONDecoder().decode(RemoteDockGalleryCatalog.self, from: data)
            guard catalog.schemaVersion == 1 else { throw URLError(.cannotParseResponse) }
            themes = catalog.themes.filter(Self.isSupported)'''
        selected = '''            themes = try EagleDockGalleryCatalog.decodeSupportedThemes(from: data)'''
        assert old.count(catalog) == 1, "Public catalog decode/selection changed"
        old = old.replace(catalog, selected)
        response_gate = '''            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= 512 * 1024 else { throw URLError(.badServerResponse) }'''
        response_check = '''            try EagleDockGalleryCatalogResponse.validate(
                data: data,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode
            )'''
        assert old.count(response_gate) == 1, "Public catalog response gate changed"
        old = old.replace(response_gate, response_check)
        catalog_url = '''    private let catalogURL = URL(string: "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/catalogs/dock-v1.json?catalog=21")!'''
        loader = '''    private let catalogLoader = EagleDockGalleryCatalogLoader()'''
        assert old.count(catalog_url) == 1, "Public catalog URL declaration changed"
        old = old.replace(catalog_url, loader)
        load_sequence = '''            var request = URLRequest(url: catalogURL)
            request.timeoutInterval = 25
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            try EagleDockGalleryCatalogResponse.validate(
                data: data,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode
            )
            themes = try EagleDockGalleryCatalog.decodeSupportedThemes(from: data)'''
        load_call = '''            themes = try await catalogLoader.load(force: force)'''
        assert old.count(load_sequence) == 1, "Public catalog request/data pipeline changed"
        old = old.replace(load_sequence, load_call)
        package_property = '''    private let packageDownloader = EagleDockGalleryPackageDownloader()'''
        assert old.count(loader) == 1, "Catalog loader property changed"
        old = old.replace(loader, loader + "\n" + package_property)
        package_sequence = '''        var request = URLRequest(url: theme.packageURL)
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        try EagleDockGalleryPackageValidation.validateDownload(
            data,
            httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
            expectedByteCount: theme.byteCount,
            expectedSHA256: theme.sha256
        )'''
        package_call = '''        let data = try await packageDownloader.download(theme)'''
        assert old.count(package_sequence) == 1, "Public package download pipeline changed"
        old = old.replace(package_sequence, package_call)
        archive_sequence = '''        let archive = try ZipArchive(data: data)
        let files = try EagleDockGalleryPackageInventory.frameFiles(
            in: archive.entries, frameCount: theme.frameCount
        )'''
        archive_call = '''        let archive = try EagleDockGalleryPackageArchive(
            data: data,
            frameCount: theme.frameCount,
            log: CurrentArchiveDiagnostics.log
        )
        let files = archive.files'''
        assert old.count(archive_sequence) == 1, "Public archive opening/inventory changed"
        old = old.replace(archive_sequence, archive_call)
        cache_property = '''    private let cacheDirectoryService = EagleDockGalleryCacheDirectory()'''
        assert old.count(package_property) == 1, "Package downloader property changed"
        old = old.replace(package_property, package_property + "\n" + cache_property)
        cache_method = declaration(baseline, "private func cacheDirectory(for theme:")
        cache_delegate = '''private func cacheDirectory(for theme: RemoteDockGalleryTheme) throws -> URL {
        try cacheDirectoryService.directory(for: theme)
    }'''
        assert old.count(cache_method) == 1, "Public cache-directory method changed"
        old = old.replace(cache_method, cache_delegate)
        cached_method = declaration(old, "private static func validFrames(in directory:")
        cached_sequence = '''        guard isSupported(theme) else { return false }
        return (1...theme.frameCount).allSatisfy { index in
            let url = directory.appendingPathComponent(String(format: "frame%02d.png", index))
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let image = UIImage(data: data) else { return false }'''
        cached_delegate = '''        EagleDockGalleryCachedFrames.areValid(in: directory, theme: theme) { data, theme in
            guard let image = UIImage(data: data) else { return false }'''
        assert cached_method.count(cached_sequence) == 1, "Public cached-frame traversal changed"
        assert old.count(cached_method) == 1, "Public cached-frame method changed"
        old = old.replace(cached_method, cached_method.replace(cached_sequence, cached_delegate))
        staging_sequence = '''        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\\(theme.id)-\\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)'''
        staging_delegate = '''        let staging = try EagleDockGalleryStagingDirectory.create(
            beside: destination,
            themeID: theme.id,
            fileManager: fm
        )'''
        assert old.count(staging_sequence) == 1, "Public staging creation changed"
        old = old.replace(staging_sequence, staging_delegate)
        frame_write = '''                try frameData.write(to: staging.appendingPathComponent(entry.path), options: .atomic)'''
        frame_write_delegate = '''                try EagleDockGalleryFrameWriter.write(frameData, framePath: entry.path, in: staging)'''
        assert old.count(frame_write) == 1, "Public atomic frame write changed"
        old = old.replace(frame_write, frame_write_delegate)
        preparation_start = '''        do {
            for entry in files {'''
        commit_start = '''        try EagleDockGalleryCacheCommit.commit(staging: staging, to: destination, fileManager: fm) {
            for entry in files {'''
        commit_finish = '''            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }'''
        assert old.count(preparation_start) == 1, "Public frame preparation scope changed"
        assert old.count(commit_finish) == 1, "Public replacement/cleanup scope changed"
        old = old.replace(preparation_start, commit_start).replace(commit_finish, "        }")
        image_guard = checked + '''
                    throw URLError(.cannotDecodeContentData)
                }'''
        image_delegate = '''                try EagleDockGalleryFrameImage.validate(frameData, theme: theme)'''
        image_cache = '''            guard let image = UIImage(data: data) else { return false }
''' + dimensions
        image_cache_delegate = '''            EagleDockGalleryFrameImage.isValid(data, theme: theme)'''
        assert old.count(image_guard) == 1, "Public frame image guard changed"
        assert old.count(image_cache) == 1, "Public cached image check changed"
        old = old.replace(image_guard, image_delegate).replace(image_cache, image_cache_delegate)
        normalized_cached_method = declaration(old, "private static func validFrames(in directory:")
        cache_validator_signature = "static func isValid(in directory: URL, theme: EagleDockGalleryTheme) -> Bool"
        cache_validator = normalized_cached_method.replace(
            "private static func validFrames(in directory: URL, theme: RemoteDockGalleryTheme) -> Bool",
            cache_validator_signature,
            1,
        )
        assert cache_validator.count(cache_validator_signature) == 1, "Normalized cache validation signature changed"
        expected_cache_source = '''import Foundation
@MainActor
struct EagleDockGalleryPackageCache {
    struct Location {
        let directory: URL
        let isValid: Bool
    }

    private let directories: EagleDockGalleryCacheDirectory

    nonisolated init(directories: EagleDockGalleryCacheDirectory = EagleDockGalleryCacheDirectory()) {
        self.directories = directories
    }

    func locate(_ theme: EagleDockGalleryTheme) throws -> Location {
        let directory = try directories.directory(for: theme)
        return Location(directory: directory, isValid: Self.isValid(in: directory, theme: theme))
    }

    ''' + cache_validator + '''
}'''
        cache_source = (repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryPackageCache.swift").read_text()
        cache_code = re.sub(r"//[^\n]*", "", cache_source)
        assert cache_code.split() == expected_cache_source.split(), "Cache probe/default/validation structure differs from normalized public rules"
        prepare_method = declaration(old, "func prepare(_ theme: RemoteDockGalleryTheme)")
        assert prepare_method.count(archive_call) == 1, "Normalized package archive stage changed"
        return_destination = "        return destination"
        assert prepare_method.count(return_destination) == 1, "Normalized package return changed"
        stage_start = prepare_method.index(archive_call)
        stage_end = prepare_method.index(return_destination, stage_start) + len(return_destination)
        package_stage = prepare_method[stage_start:stage_end]
        final_cache_check = "Self.validFrames(in: staging, theme: theme)"
        final_cache_delegate = "EagleDockGalleryPackageCache.isValid(in: staging, theme: theme)"
        assert package_stage.count(final_cache_check) == 1, "Normalized final frame gate changed"
        assert package_stage.count("CurrentArchiveDiagnostics.log") == 1, "Normalized archive diagnostics changed"
        expected_stage = package_stage.replace(final_cache_check, final_cache_delegate)
        expected_stage = expected_stage.replace("CurrentArchiveDiagnostics.log", "log")
        preparer_source = (repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparer.swift").read_text()
        code = re.sub(r"//[^\n]*", "", preparer_source)
        preparer_enum = declaration(code, "@MainActor\nenum EagleDockGalleryPackagePreparer")
        prepare_signature = '''static func prepare(
        _ data: Data,
        theme: EagleDockGalleryTheme,
        destination: URL,
        log: @escaping @Sendable (String) -> Void
    ) throws -> URL'''
        assert code.count(prepare_signature) == 1, "Package preparation signature/isolation changed"
        preparer_method = declaration(code, prepare_signature)
        actual_stage = preparer_method[preparer_method.index("{") + 1:-1].strip()
        assert actual_stage == expected_stage.strip(), "Extracted package-file sequence differs from normalized public body"
        assert preparer_enum.replace(preparer_method, "", 1).split() == [
            "@MainActor", "enum", "EagleDockGalleryPackagePreparer", "{", "}"
        ], "Package preparer gained state or additional methods"
        assert code.replace(preparer_enum, "", 1).split() == ["import", "Foundation"], "Package preparer gained imports or external code"
        package_stage_delegate = '''        return try EagleDockGalleryPackagePreparer.prepare(
            data,
            theme: theme,
            destination: destination,
            log: CurrentArchiveDiagnostics.log
        )'''
        assert old.count(package_stage) == 1, "Normalized complete package-file stage changed"
        old = old.replace(package_stage, package_stage_delegate)
        package_cache_property = "    private let packageCache = EagleDockGalleryPackageCache()"
        assert old.count(cache_property) == 1, "Normalized cache directory property changed"
        old = old.replace(cache_property, package_cache_property)
        cache_probe_sequence = '''        let destination = try cacheDirectory(for: theme)
        if Self.validFrames(in: destination, theme: theme) { return destination }'''
        cache_probe_delegate = '''        let cache = try packageCache.locate(theme)
        let destination = cache.directory
        if cache.isValid { return destination }'''
        assert old.count(cache_probe_sequence) == 1, "Normalized initial cache lookup/check changed"
        old = old.replace(cache_probe_sequence, cache_probe_delegate)
        for removed_method in (cache_delegate, normalized_cached_method):
            removable = "\n\n    " + removed_method
            assert old.count(removable) == 1, "Expected one normalized removed cache helper"
            assert removed_method not in new, "Store must no longer own cache helper implementation"
            old = old.replace(removable, "")
        normalized_prepare = declaration(old, "func prepare(_ theme: RemoteDockGalleryTheme)")
        coordination_body = normalized_prepare[normalized_prepare.index("{") + 1:-1].strip()
        location_probe = '''        let location = try cache.locate(theme)
        let destination = location.directory
        if location.isValid { return destination }'''
        assert normalized_prepare.count(cache_probe_delegate) == 1, "Normalized cache probe order changed"
        coordination_body = coordination_body.replace(cache_probe_delegate.strip(), location_probe.strip(), 1)
        callback_moves = (
            ("downloadingID = theme.id", "willDownload()"),
            ("defer { downloadingID = nil }", "defer { didFinish() }"),
            ("packageDownloader.download(theme)", "downloader.download(theme)"),
            ("CurrentArchiveDiagnostics.log", "diagnostics()"),
        )
        for before, after in callback_moves:
            assert coordination_body.count(before) == 1, "Normalized preparation hook/service boundary changed"
            coordination_body = coordination_body.replace(before, after, 1)
        expected_coordination_source = '''import Foundation
@MainActor
struct EagleDockGalleryPackagePreparation {
    private let downloader: EagleDockGalleryPackageDownloader
    private let cache: EagleDockGalleryPackageCache

    nonisolated init(
        downloader: EagleDockGalleryPackageDownloader = EagleDockGalleryPackageDownloader(),
        cache: EagleDockGalleryPackageCache = EagleDockGalleryPackageCache()
    ) {
        self.downloader = downloader
        self.cache = cache
    }

    func prepare(
        _ theme: EagleDockGalleryTheme,
        diagnostics: @MainActor @Sendable () -> (@Sendable (String) -> Void),
        willDownload: @MainActor @Sendable () -> Void,
        didFinish: @MainActor @Sendable () -> Void
    ) async throws -> URL {
        ''' + coordination_body + '''
    }
}'''
        coordination_source = (repo / "lara/EagleAdapters/DockGallery/EagleDockGalleryPackagePreparation.swift").read_text()
        coordination_code = re.sub(r"//[^\n]*", "", coordination_source)
        assert coordination_code.split() == expected_coordination_source.split(), "Preparation coordination/defaults/hooks differ from normalized public flow"
        old_services = package_property + "\n" + package_cache_property
        new_service = "    private let packagePreparation = EagleDockGalleryPackagePreparation()"
        assert old.count(old_services) == 1, "Normalized preparation services changed"
        old = old.replace(old_services, new_service, 1)
        coordination_delegate = '''func prepare(_ theme: RemoteDockGalleryTheme) async throws -> URL {
        return try await packagePreparation.prepare(
            theme,
            diagnostics: { CurrentArchiveDiagnostics.log },
            willDownload: { self.downloadingID = theme.id },
            didFinish: { self.downloadingID = nil }
        )
    }'''
        assert old.count(normalized_prepare) == 1, "Expected one normalized preparation method"
        old = old.replace(normalized_prepare, coordination_delegate, 1)
        old = old.replace("private final class RemoteDockGalleryStore:", "final class EagleDockGalleryStore:", 1)
        singleton = "    static let shared = RemoteDockGalleryStore()\n"
        assert old.count(singleton) == 1, "Expected one screen-owned shared instance"
        old = old.replace(singleton, "", 1).replace("RemoteDockGalleryTheme", "EagleDockGalleryTheme")
        old_dependencies = loader + "\n" + new_service
        owned_dependencies = '''    private let catalogLoader: EagleDockGalleryCatalogLoader
    private let packagePreparation: EagleDockGalleryPackagePreparation
    private let catalogFailureMessage: @MainActor @Sendable () -> String
    private let diagnostics: @MainActor @Sendable () -> (@Sendable (String) -> Void)

    init(
        catalogLoader: EagleDockGalleryCatalogLoader = EagleDockGalleryCatalogLoader(),
        packagePreparation: EagleDockGalleryPackagePreparation = EagleDockGalleryPackagePreparation(),
        catalogFailureMessage: @escaping @MainActor @Sendable () -> String,
        diagnostics: @escaping @MainActor @Sendable () -> (@Sendable (String) -> Void)
    ) {
        self.catalogLoader = catalogLoader
        self.packagePreparation = packagePreparation
        self.catalogFailureMessage = catalogFailureMessage
        self.diagnostics = diagnostics
    }'''
        assert old.count(old_dependencies) == 1, "Normalized Store service declarations changed"
        old = old.replace(old_dependencies, owned_dependencies, 1)
        original_failure = '''LaraL10n.text(
                en: "The online collection could not be loaded.",
                es: "No se pudo cargar la colección en línea."
            )'''
        assert old.count(original_failure) == 1, "Normalized catalog failure message changed"
        old = old.replace(original_failure, "catalogFailureMessage()", 1)
        original_diagnostics = "diagnostics: { CurrentArchiveDiagnostics.log }"
        assert old.count(original_diagnostics) == 1, "Normalized late diagnostics hook changed"
        old = old.replace(original_diagnostics, "diagnostics: diagnostics", 1)
        assert old.split() == new.split(), "Owned Store fields/defaults/hooks/load flow differ from normalized public Store"
    else:
        assert old == new, f"Unexpected behavior change in {marker}"
for line in ui_properties:
    assert line in current, "A UI presentation adapter changed"
assert "private typealias RemoteDockGalleryTheme = EagleDockGalleryTheme" in current
assert "associatedtype Theme" not in core.read_text()
assert "EagleDockGalleryApplyRequest<" not in core.read_text() + current
for source in [model.read_text(), core.read_text()]:
    assert [line for line in source.splitlines() if line.startswith("import ")] == ["import Foundation"]
    assert all(name not in source for name in ["LaraL10n", "laramgr", "SwiftUI", "UIKit", "RemoteDockGalleryTheme"])

flags = ["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"]
subprocess.run(["swiftc", *flags, "-typecheck", str(model), str(core)], check=True)
print("PASS: production Dock contract compiles without UI/Lara; store/executor and presentation adapters preserved", flush=True)
with tempfile.TemporaryDirectory(prefix="eagle-dock-model-") as directory:
    work = Path(directory)
    reference = work / "PublicDockModel.swift"
    reference.write_text("import Foundation\n" + original)
    for runner in ["verify_eagle_dock_model.swift", "verify_eagle_core_dock.swift"]:
        binary = work / runner.removesuffix(".swift")
        sources = [str(model), str(core), str(repo / "scripts" / runner)]
        if runner == "verify_eagle_dock_model.swift":
            sources.append(str(reference))
        subprocess.run(["swiftc", *flags, "-parse-as-library", *sources, "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=30)
