#!/usr/bin/env python3
"""Compare Island Apply/Restore coordination with public methods; no native calls."""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile
from verify_eagle_dock_apply_flow import declaration, replace_once, compact

PUBLIC = "823ab22c60ac6289314577034085784b8fdc24a4"
VIEW = "lara/views/new/IslandGalleryPresentation.swift"
CORE = "lara/EagleCore/IslandGallery/EagleIslandGalleryActionFlow.swift"
MARKERS = ["private func apply(_ item: IslandGalleryArtwork)", "private func restore()"]
BRIDGES = ['''private func apply(_ item: IslandGalleryArtwork) {
        EagleIslandGalleryActionFlow.apply(
            item,
            isApplying: { applying },
            select: { select($0) },
            setApplying: { applying = $0 },
            liveTheme: { $0.liveTheme },
            applyLive: { await IslandGalleryExecutor.shared.applyLive($0, shadowIntensity: shadowIntensity) },
            applyStyle: { await IslandGalleryExecutor.shared.apply($0.style, shadowIntensity: shadowIntensity) },
            feedback: { UINotificationFeedbackGenerator().notificationOccurred($0.succeeded ? .success : .error) },
            notify: { EagleNotifications.shared.result($0.succeeded, title: "Island Gallery", message: $0.message) }
        )
    }''', '''private func restore() {
        EagleIslandGalleryActionFlow.restore(
            isApplying: { applying },
            setApplying: { applying = $0 },
            execute: { await IslandGalleryExecutor.shared.restore() },
            feedback: { UINotificationFeedbackGenerator().notificationOccurred($0.succeeded ? .success : .error) },
            notify: { EagleNotifications.shared.result($0.succeeded, title: "Island Gallery", message: $0.message) }
        )
    }''']
HEADERS = ['''static func apply<Artwork, Theme, Response>(
        _ item: Artwork,
        isApplying: () -> Bool,
        select: (Artwork) -> Void,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        liveTheme: @escaping @MainActor @Sendable (Artwork) -> Theme?,
        applyLive: @escaping @MainActor @Sendable (Theme) async -> Response,
        applyStyle: @escaping @MainActor @Sendable (Artwork) async -> Response,
        feedback: @escaping @MainActor @Sendable (Response) -> Void,
        notify: @escaping @MainActor @Sendable (Response) -> Void
    )''', '''static func restore<Response>(
        isApplying: () -> Bool,
        setApplying: @escaping @MainActor @Sendable (Bool) -> Void,
        execute: @escaping @MainActor @Sendable () async -> Response,
        feedback: @escaping @MainActor @Sendable (Response) -> Void,
        notify: @escaping @MainActor @Sendable (Response) -> Void
    )''']


def originals():
    repo = Path(__file__).resolve().parents[1]
    public = subprocess.check_output(["git", "show", f"{PUBLIC}:{VIEW}"], cwd=repo, text=True)
    return [declaration(public, marker) for marker in MARKERS]


def inline_action_flow(view):
    from verify_eagle_visual_base import inline_island_apply_visuals
    view = inline_island_apply_visuals(view)
    for bridge, original in zip(BRIDGES, originals()):
        view = replace_once(view, bridge, original)
    return view


def expected_core():
    methods = []
    for i, method in enumerate(originals()):
        substitutions = [
            (MARKERS[i], HEADERS[i]), ("guard !applying", "guard !isApplying()"),
            ("applying = true", "setApplying(true)"), ("applying = false", "setApplying(false)"),
            ("UINotificationFeedbackGenerator().notificationOccurred(response.succeeded ? .success : .error)", "feedback(response)"),
            ('EagleNotifications.shared.result(response.succeeded, title: "Island Gallery", message: response.message)', "notify(response)"),
        ]
        if i == 0:
            substitutions += [
                ("let response: IslandGalleryApplyResult", "let response: Response"),
                ("item.liveTheme", "liveTheme(item)"),
                ('''IslandGalleryExecutor.shared.applyLive(
                    theme,
                    shadowIntensity: shadowIntensity
                )''', "applyLive(theme)"),
                ('''IslandGalleryExecutor.shared.apply(
                    item.style,
                    shadowIntensity: shadowIntensity
                )''', "applyStyle(item)"),
            ]
        else:
            substitutions.append(("IslandGalleryExecutor.shared.restore()", "execute()"))
        for before, after in substitutions:
            method = replace_once(method, before, after)
        methods.append(method)
    return "import Foundation\n@MainActor\nenum EagleIslandGalleryActionFlow {\n" + "\n".join(methods) + "\n}\n"


def verify_texts(view, core):
    assert hashlib.sha256(inline_action_flow(view).encode()).hexdigest() == \
        "14980a7289e455ad29a73117a445606900b266b0202f4d99eb00dbedde3a3f7c", "Unrelated screen edit"
    assert compact(core) == compact(expected_core()), "Action sequencing/signatures differ from public bodies"


def verify_sources(repo):
    view, core = [(repo / p).read_text() for p in (VIEW, CORE)]
    verify_texts(view, core)
    assert hashlib.sha256((repo / "lara/views/new/IslandGalleryView.swift").read_bytes()).hexdigest() == \
        "0659ee8112772cbcd0d418f7da0840b638be60e0e60b5798116050a91d1196ec", "Inherited executor changed"
    cases = [
        (0, "select: { select($0) }", "select: { _ in }"),
        (0, "liveTheme: { $0.liveTheme }", "liveTheme: { _ in nil }"),
        (0, "applyLive($0, shadowIntensity: shadowIntensity)", "applyLive($0, shadowIntensity: 1)"),
        (0, "apply($0.style, shadowIntensity: shadowIntensity)", "apply($0.style, shadowIntensity: 0)"),
        (0, "execute: { await IslandGalleryExecutor.shared.restore() }", "execute: { fatalError() }"),
        (1, "select(item)\n        setApplying(true)", "setApplying(true)\n        select(item)"),
        (1, "if let theme = liveTheme(item)", "if let theme = Optional<Theme>.none"),
        (1, "applyStyle(item)", "applyStyle(item)\n            // mutation\n            return"),
        (1, "@MainActor\nenum", "nonisolated enum"),
    ]
    # Mutate each shared pattern independently in Apply and Restore.
    for index in (0, 1):
        for before, after in (
            ("guard !isApplying()", "guard isApplying()"),
            ("Task { @MainActor in", "Task.detached { @MainActor in"),
            ("setApplying(false)\n            feedback(response)", "feedback(response)\n            setApplying(false)"),
            ("notify(response)", "// notify removed"),
        ):
            method = declaration(core, "static func apply<" if index == 0 else "static func restore<")
            changed = replace_once(core, method, replace_once(method, before, after))
            try:
                verify_texts(view, changed)
            except AssertionError:
                continue
            raise AssertionError("Accepted action method mutation")
    for index, before, after in cases:
        texts = [view, core]
        texts[index] = replace_once(texts[index], before, after)
        try:
            verify_texts(*texts)
        except AssertionError:
            continue
        raise AssertionError(f"Accepted mutation {before}")
    try:
        verify_texts(view + "\n// unrelated\n", core)
    except AssertionError:
        print(f"PASS: both public action bodies, exact screen reversal, unchanged executor; {len(cases)+9} rejected mutations", flush=True)
        return
    raise AssertionError("Accepted unrelated screen mutation")


def main():
    repo = Path(__file__).resolve().parents[1]
    verify_sources(repo)
    hosts = []
    for name, methods in (("PublicHost", originals()), ("OwnedHost", BRIDGES)):
        methods = "\n".join(methods)
        for before, after in (("IslandGalleryExecutor.shared", "executor"),
                              ("UINotificationFeedbackGenerator()", "feedbackGenerator"),
                              ("EagleNotifications.shared", "notifications")):
            methods = methods.replace(before, after)
        # The fixture host is a class, unlike the production SwiftUI value. Make
        # self explicit in both versions without changing accesses or callbacks.
        methods = re.sub(r"\b(applying|select|shadowIntensity|executor|feedbackGenerator|notifications)\b(?!:)",
                         r"self.\1", methods)
        hosts.append("@MainActor final class " + name + ": Host {\n"
                     "override func start(_ item: IslandGalleryArtwork?) {\n"
                     "if let item { apply(item) } else { restore() }\n}\n" + methods + "\n}\n")
    fixture = (repo / "scripts/verify_eagle_island_action_flow.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="eagle-island-actions-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(fixture + "\n" + "\n".join(hosts))
        for mode in ("-Onone", "-O"):
            binary = Path(temporary) / ("debug" if mode == "-Onone" else "release")
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                            "-warnings-as-errors", "-parse-as-library", mode, str(repo / CORE),
                            str(source), "-o", str(binary)], check=True, timeout=55)
            subprocess.run([str(binary)], check=True, timeout=55)


if __name__ == "__main__":
    main()
