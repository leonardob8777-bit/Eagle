#!/usr/bin/env python3
"""Verify exact built-in Dock metadata, host parity, and its isolated iOS UI adapter.

Only the Foundation enum and extracted built-in presentation declarations are
compiled. The full app, native access/applying engine, and Simulator are excluded.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile


PUBLIC_COMMIT = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW_PATH = "lara/views/new/DockGalleryView.swift"
MODEL_PATH = "lara/EagleCore/DockGallery/EagleDockGalleryBuiltInTheme.swift"
PUBLIC_MARKER = "private enum DockGalleryStyle: Int, CaseIterable, Identifiable"
OWNED_MARKER = "nonisolated enum EagleDockGalleryBuiltInTheme: Int, CaseIterable, Identifiable, Sendable"
UI_ALIAS = "private typealias DockGalleryStyle = EagleDockGalleryBuiltInTheme"
UI_EXTENSION = """private extension EagleDockGalleryBuiltInTheme {
    var title: String {
        let text = titleText
        if self == .springfield { return text.en }
        return LaraL10n.text(en: text.en, es: text.es)
    }

    var subtitle: String {
        let text = subtitleText
        return LaraL10n.text(en: text.en, es: text.es)
    }

    var accent: Color {
        let components = accentComponents
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}"""


def declaration(source, marker):
    assert source.count(marker) == 1, f"Expected exactly one declaration: {marker}"
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        assert end < len(source), f"Unbalanced declaration: {marker}"
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def compact(source):
    # Formatting is immaterial, but whitespace inside displayed strings is data.
    pieces = re.split(r'("(?:\\.|[^"\\])*")', source)
    return "".join(piece if index % 2 else re.sub(r"\s+", "", piece)
                   for index, piece in enumerate(pieces))


def replace_counted(source, old, new, count, label):
    assert source.count(old) == count, f"Counted built-in boundary changed: {label}"
    return source.replace(old, new)


def expected_metadata(public_enum):
    expected = replace_counted(public_enum, PUBLIC_MARKER, OWNED_MARKER, 1, "enum name/access/Sendable")
    localized_return = re.compile(
        r'return\s+LaraL10n\.text\(\s*en:\s*("[^"]*"),\s*es:\s*("[^"]*")\s*\)'
    )
    for name, count in (("title", 5), ("subtitle", 6)):
        original = declaration(expected, f"var {name}: String")
        transformed = replace_counted(
            original, f"var {name}: String", f"var {name}Text: (en: String, es: String)",
            1, f"{name} bilingual projection",
        )
        transformed, replacements = localized_return.subn(r"return (\1, \2)", transformed)
        assert replacements == count, f"Public {name} localization inventory changed"
        if name == "title":
            transformed = replace_counted(
                transformed, 'return "Springfield"', 'return ("Springfield", "Springfield")',
                1, "Springfield literal projection",
            )
        expected = replace_counted(expected, original, transformed, 1, f"{name} declaration")
    original = declaration(expected, "var accent: Color")
    transformed = replace_counted(
        original, "var accent: Color", "var accentComponents: (red: Double, green: Double, blue: Double)",
        1, "independent floating-point accent projection",
    )
    transformed, replacements = re.subn(
        r"return\s+Color\(red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+)\)",
        r"return (\1, \2, \3)", transformed,
    )
    assert replacements == 6, "Public floating-point Color constants changed"
    return replace_counted(expected, original, transformed, 1, "accent declaration")


def _verify_contract(public_enum, current, model):
    code = re.sub(r"//[^\n]*", "", model)
    actual = declaration(code, OWNED_MARKER)
    assert compact(actual) == compact(expected_metadata(public_enum)), (
        "Owned metadata differs from exact public cases/strings/assets/constants/static preview rules"
    )
    outside = code.replace(actual, "", 1)
    assert outside.split() == ["import", "Foundation"], "Built-in metadata gained imports or external code"
    assert current.count(UI_ALIAS) == 1, "The UI must use the exact owned built-in type alias"
    assert "enum DockGalleryStyle:" not in current, "The screen still declares its built-in model"
    ui = declaration(current, "private extension EagleDockGalleryBuiltInTheme")
    assert compact(ui) == compact(UI_EXTENSION), "UI title/subtitle/Color projection or Springfield bypass changed"
    return ui


def verify_sources(repo):
    """Import-safe source-only contract used by this and the wider model gate."""
    repo = Path(repo)
    public = subprocess.check_output(
        ["git", "show", f"{PUBLIC_COMMIT}:{VIEW_PATH}"], cwd=repo, text=True, timeout=55,
    )
    public_enum = declaration(public, PUBLIC_MARKER)
    current = (repo / VIEW_PATH).read_text()
    model = (repo / MODEL_PATH).read_text()
    ui = _verify_contract(public_enum, current, model)
    return {"public_enum": public_enum, "current": current, "model": model, "ui": ui}


def verify_memory_negatives(values):
    cases = [
        ("model", "case bubblegum = 15", "case bubblegum = 14"),
        ("model", 'return ("Bubblegum", "Chicle")', 'return ("Bubblegum", "Otra cosa")'),
        ("model", 'return ("Springfield", "Springfield")', 'return ("Springfield", "Ciudad")'),
        ("model", '"Pink and yellow bubbles"', '"Pinkandyellowbubbles"'),
        ("model", 'return "DockGalleryBubblegum"', 'return "AnotherAsset"'),
        ("model", "return (1.0, 0.18, 0.62)", "return (1.0, 45.0 / 255.0, 158.0 / 255.0)"),
        ("model", "return (255, 45, 158)", "return (255, 46, 158)"),
        ("model", "return false", "return true"),
        ("model", "        nil\n", '        "Animated"\n'),
        ("model", "guard let animationAssetPrefix else { return assetName }", "guard let animationAssetPrefix else { return assetName + String(date.timeIntervalSinceReferenceDate) }"),
        ("model", "import Foundation", "import Foundation\nimport UIKit"),
        ("current", UI_ALIAS, "private typealias DockGalleryStyle = DifferentTheme"),
        ("current", "if self == .springfield { return text.en }", "if self == .springfield { return LaraL10n.text(en: text.en, es: text.es) }"),
        ("current", "return Color(red: components.red, green: components.green, blue: components.blue)", "return Color(red: components.blue, green: components.green, blue: components.red)"),
    ]
    for field, old, new in cases:
        altered = values.copy()
        altered[field] = replace_counted(altered[field], old, new, 1, f"negative {field}")
        try:
            _verify_contract(altered["public_enum"], altered["current"], altered["model"])
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"Changed built-in source escaped rejection: {old}")
    return len(cases)


def runtime_projections(values):
    reference = replace_counted(
        values["public_enum"], PUBLIC_MARKER,
        "enum PublicDockGalleryStyle: Int, CaseIterable, Identifiable", 1, "public fixture name/access",
    )
    ui = replace_counted(
        values["ui"], "private extension EagleDockGalleryBuiltInTheme",
        "extension EagleDockGalleryBuiltInTheme", 1, "runtime UI extension access",
    )
    stubs = """import Foundation

nonisolated struct Color {
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated struct LocalizationInvocation: Equatable {
    let en: String
    let es: String
}

@MainActor
enum LaraL10n {
    static var language = "en"
    static var calls: [LocalizationInvocation] = []
    static func reset(language: String) {
        self.language = language
        calls = []
    }
    static func text(en: String, es: String) -> String {
        calls.append(LocalizationInvocation(en: en, es: es))
        return language == "es" ? es : en
    }
}

"""
    return stubs + reference + "\n\n" + ui + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true", help="Run only exact source and in-memory rejection checks")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    values = verify_sources(repo)
    negative_count = verify_memory_negatives(values)
    print(f"PASS: exact public-to-owned built-in metadata/UI source normalization; {negative_count} in-memory negative changes rejected", flush=True)
    if args.source_only:
        return
    flags = ["-swift-version", "5", "-default-isolation", "MainActor",
             "-strict-concurrency=complete", "-warnings-as-errors"]
    model = repo / MODEL_PATH
    runner = repo / "scripts/verify_eagle_dock_builtin_theme.swift"
    assert runner.is_file(), "The standalone built-in theme runner is required"
    with tempfile.TemporaryDirectory(prefix="eagle-dock-builtin-theme-") as directory:
        work = Path(directory)
        projections = work / "ExactBuiltInDockProjections.swift"
        projections.write_text(runtime_projections(values))
        binary = work / "verify-dock-builtin-theme"
        subprocess.run(
            ["swiftc", *flags, "-parse-as-library", str(model), str(projections), str(runner), "-o", str(binary)],
            check=True, timeout=55,
        )
        subprocess.run([str(binary)], check=True, timeout=55)

        # Preserve the real private alias/extension and use the real SwiftUI type.
        # This compiles no view, app manager, native code, or installation package.
        swiftui = work / "ExactBuiltInDockSwiftUI.swift"
        swiftui.write_text("import Foundation\nimport SwiftUI\n\n" + UI_ALIAS + "\n\n" + values["ui"] + "\n\n" + """@MainActor
private enum LaraL10n {
    static func text(en: String, es: String) -> String { en }
}

@MainActor
private func fixturePresentation(_ theme: DockGalleryStyle) -> (String, String, Color) {
    (theme.title, theme.subtitle, theme.accent)
}
""")
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, timeout=55).strip()
        subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "swiftc", *flags, "-typecheck",
             "-target", "arm64-apple-ios16.0", "-sdk", sdk, str(model), str(swiftui)],
            check=True, timeout=55,
        )
    print("PASS: actual built-in alias/private UI extension typechecks against the iOS SwiftUI SDK; host fixtures cleaned; no Simulator/full app/native engine/IPA", flush=True)


if __name__ == "__main__":
    main()
