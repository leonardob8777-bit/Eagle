#!/usr/bin/env python3
"""Verify owned localization, compatibility aliases and late Gallery language reads.

Runtime checks use temporary macOS bundles and volatile defaults only. They do
not install an app, access a device, change persisted preferences or use network.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from verify_eagle_core_module_build import declaration
from verify_eagle_gallery_services import verify_sources as verify_gallery_services

PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
LEGACY_PATH = "lara/config/LaraLanguage.swift"
OWNED_PATH = "lara/EagleCore/Localization/EagleLocalization.swift"
EXPECTED_BRIDGE = '''import Foundation

// Keep existing call sites and stored preferences compatible during migration.
typealias LaraLanguage = EagleLanguage
typealias LaraL10n = EagleLocalization
'''
EXPECTED_CALLBACK = '''catalogFailureMessage: {
            EagleLocalization.text(
                en: "The online collection could not be loaded.",
                es: "No se pudo cargar la colección en línea."
            )
        }'''


# Simplified Chinese (16 Oct, requested): exactly these additions are accepted on top of the public
# behavior; everything else must still match it.
CHINESE_EDITS = [
    ('    case spanish = "es"\n    case chinese = "zh-Hans"\n', '    case spanish = "es"\n'),
    ('        case .spanish: return "Español"\n        case .chinese: return "简体中文"\n', '        case .spanish: return "Español"\n'),
    ('        case .spanish: return "ES"\n        case .chinese: return "中文"\n', '        case .spanish: return "ES"\n'),
    ('''    /// Chinese text for an English string, installed by the app at launch (the table lives outside
    /// the core module). Until then, Chinese falls back to English.
    nonisolated(unsafe) static var chineseText: (String) -> String = { $0 }

    static func text(en: String, es: String) -> String {
        switch language {
        case .spanish: return es
        case .chinese: return chineseText(en)
        case .english: return en
        }
    }''', '''    static func text(en: String, es: String) -> String {
        language == .spanish ? es : en
    }'''),
]


def without_chinese(source):
    for added, original in CHINESE_EDITS:
        assert source.count(added) == 1, "Chinese localization edit changed: " + added[:60]
        source = source.replace(added, original)
    return source


def rename_types(source, language, localization):
    assert source.count("LaraLanguage") == 4, "Public language references changed"
    assert source.count("LaraL10n") == 1, "Public localization declaration changed"
    return source.replace("LaraLanguage", language).replace("LaraL10n", localization)


def verify_sources(repo):
    public = subprocess.run(
        ["git", "show", f"{PUBLIC_COMMIT}:{LEGACY_PATH}"],
        cwd=repo, check=True, capture_output=True, text=True, timeout=55,
    ).stdout
    owned = without_chinese((repo / OWNED_PATH).read_text())
    assert owned == rename_types(public, "EagleLanguage", "EagleLocalization"), \
        "Owned language, preference, text or bundle lookup behavior differs from public Eagle"
    bridge = (repo / LEGACY_PATH).read_text()
    assert bridge == EXPECTED_BRIDGE, "Legacy language implementation is not an exact alias bridge"
    bootstrap = verify_gallery_services(repo)
    callback = declaration(bootstrap, "catalogFailureMessage:")
    assert callback == EXPECTED_CALLBACK, "Gallery stopped reading the owned language lazily"
    assert 'static let storageKey = "lara.interfaceLanguage"' in owned
    assert [line for line in owned.splitlines() if line.startswith("import ")] == ["import Foundation"]
    assert "Lara" not in owned and owned.count("lara") == 1, \
        "Owned localization regained a legacy dependency (only the persisted key is retained)"
    return public, callback


def main():
    repo = Path(__file__).resolve().parents[1]
    public, callback = verify_sources(repo)
    print("PASS: complete public localization parity, exact aliases and direct Gallery connection", flush=True)
    with tempfile.TemporaryDirectory(prefix="eagle-localization-") as directory:
        work = Path(directory)
        reference = work / "PublicLocalization.swift"
        reference.write_text(rename_types(public, "PublicLanguage", "PublicLocalization"))
        connection = work / "GalleryMessage.swift"
        connection.write_text(
            "enum GalleryMessage {\n"
            "    @MainActor static let failure: @MainActor @Sendable () -> String = "
            + callback.split(":", 1)[1].strip() + "\n}\n"
        )
        executable = work / "LocalizationChecks"
        subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-swift-version", "5",
            "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors",
            str(repo / OWNED_PATH), str(repo / LEGACY_PATH), str(reference), str(connection),
            str(repo / "scripts/verify_eagle_localization.swift"), "-o", str(executable),
        ], check=True, timeout=55)
        # Separate processes avoid Bundle resource caches masking the missing-bundle branch.
        for mode in ("resources", "missing"):
            bundle = work / f"{mode}.app/Contents"
            binary = bundle / "MacOS/LocalizationChecks"
            binary.parent.mkdir(parents=True)
            shutil.copy2(executable, binary)
            with (bundle / "Info.plist").open("wb") as output:
                plistlib.dump({
                    "CFBundleIdentifier": "test.eagle.localization." + uuid.uuid4().hex,
                    "CFBundleExecutable": "LocalizationChecks",
                    "CFBundlePackageType": "APPL",
                    "CFBundleDevelopmentRegion": "en",
                }, output)
            if mode == "resources":
                for language, translated in (("en", "Translated ✓"), ("es", "Must not be looked up")):
                    resources = bundle / "Resources" / (language + ".lproj")
                    resources.mkdir(parents=True)
                    (resources / "Localizable.strings").write_text(
                        '"Original key" = "' + translated + '";\n', encoding="utf-8"
                    )
            subprocess.run([str(binary), mode], check=True, timeout=55)
    print("PASS: temporary bundles removed; no persistent preference writes or device operations", flush=True)


if __name__ == "__main__":
    main()
