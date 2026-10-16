#!/usr/bin/env python3
"""Validate the locally built private Aura IPA; never installs or publishes."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import plistlib
import stat
import subprocess
import tempfile
import time
import zipfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def app_intents_version(data):
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            assert key not in result, "Duplicate App Intents metadata key"
            result[key] = value
        return result
    value = json.loads(data, object_pairs_hook=unique_pairs)
    assert value == {"toolsVersion": "17F113", "version": "3.0"}, "App Intents metadata changed"
    return value


def verify_metadata_gate():
    for data in (b'{"toolsVersion":"17F113","version":"3.0"}',
                 b'{"version":"3.0","toolsVersion":"17F113"}'):
        app_intents_version(data)
    for data in (b'{}', b'[]', b'null', b'{"toolsVersion":"17F113","version":"4.0"}',
                 b'{"toolsVersion":"other","version":"3.0"}', b'{"toolsVersion":"17F113","version":3}',
                 b'{"toolsVersion":"17F113","version":"3.0","extra":true}',
                 b'{"toolsVersion":"17F113","version":"3.0","version":"3.0"}'):
        try:
            app_intents_version(data)
        except AssertionError:
            continue
        raise AssertionError("Invalid App Intents metadata accepted")


def verify_trained_shortcuts(current, previous, locale):
    """Only Apple's eight-byte training timestamp may vary in these pinned models."""
    decode = lambda data: subprocess.check_output(
        ["/usr/bin/compression_tool", "-decode", "-a", "lzfse"], input=data)
    new, old = decode(current), decode(previous)
    expected_size, timestamp = {"en": (8320, 8256), "es": (8848, 8784), "zh-Hans": (968, 904)}[locale]
    assert len(new) == len(old) == expected_size
    assert new[:timestamp] == old[:timestamp]
    assert new[timestamp + 8:] == old[timestamp + 8:]
    old_time = int.from_bytes(old[timestamp:timestamp + 8], "little")
    new_time = int.from_bytes(new[timestamp:timestamp + 8], "little")
    assert 1792000000 <= old_time <= new_time <= int(time.time()) + 60


def main():
    verify_metadata_gate()
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", choices=["state", "operations", "presentation", "boundary", "request", "session", "step", "profiles", "circle", "status-bar", "launch", "release-candidate", "polished-candidate"], default="state")
    parser.add_argument("--polished-build", choices=["94", "95"], default="94")
    args = parser.parse_args()
    status_fix = args.package == "status-bar"
    polished = args.package == "polished-candidate"
    polished_build = args.polished_build
    assert polished or polished_build == "94", "Build override is only for polished candidates"
    candidate = args.package == "release-candidate" or polished
    launch = args.package == "launch" or candidate
    if status_fix or launch:
        # The status correction inherits the complete Circle integration gates.
        args.package = "circle"
    state = repo / "artifacts/Eagle-Core-Aura-State-Test-20261012/Eagle-1.0.5-92-Core-Aura-State-Test.ipa"
    operations = repo / "artifacts/Eagle-Core-Aura-Operations-Test-20261012/Eagle-1.0.5-92-Core-Aura-Operations-Test.ipa"
    presentation = repo / "artifacts/Eagle-Core-Aura-Presentation-Test-20261013/Eagle-1.0.5-92-Core-Aura-Presentation-Test.ipa"
    boundary = repo / "artifacts/Eagle-Core-Aura-Boundary-Test-20261015/Eagle-1.0.5-92-Core-Aura-Boundary-Test.ipa"
    request = repo / "artifacts/Eagle-Core-Aura-Request-Test-20261015/Eagle-1.0.5-92-Core-Aura-Request-Test.ipa"
    session = repo / "artifacts/Eagle-Core-Aura-Session-Test-20261015/Eagle-1.0.5-92-Core-Aura-Session-Test.ipa"
    step = repo / "artifacts/Eagle-Core-Aura-Step-Test-20261015/Eagle-1.0.5-92-Core-Aura-Step-Test.ipa"
    profiles = repo / "artifacts/Eagle-Core-Aura-Profiles-Test-20261015/Eagle-1.0.5-92-Core-Aura-Profiles-Test.ipa"
    circle = repo / "artifacts/Eagle-Core-Circle-Test-20261015/Eagle-1.0.5-92-Core-Circle-Test.ipa"
    visual_base = repo.parent / "2026-10-14/s-se-puede-esto-es-lo/outputs/Eagle-1.0.5-92-fondo-salida.ipa"
    artifact = {"state": state, "operations": operations, "presentation": presentation, "boundary": boundary, "request": request, "session": session, "step": step, "profiles": profiles, "circle": circle}[args.package]
    if status_fix:
        artifact = repo / "artifacts/Eagle-Core-StatusBar-Test-20261015/Eagle-1.0.5-92-Core-StatusBar-Test.ipa"
    if launch:
        artifact = repo / "artifacts/Eagle-Core-Launch-Test-20261015/Eagle-1.0.5-92-Core-Launch-Test.ipa"
    if candidate:
        artifact = repo / "artifacts/Eagle-1.0.6-93-Test-20261015/Eagle-1.0.6-93-Test.ipa"
    if polished:
        artifact = repo / f"artifacts/Eagle-1.0.6-{polished_build}-Test-20261016/Eagle-1.0.6-{polished_build}-Test.ipa"
    if args.package in ("operations", "presentation", "boundary", "request", "session", "step", "profiles", "circle"):
        assert digest(state) == "de64e0d5fd3da874ca14ac79fe1f658cd6e5aaabede544b8108a3944b3152487"
    if args.package in ("presentation", "boundary", "request", "session", "step", "profiles", "circle"):
        assert digest(operations) == "3583cd94fb7cf5961fe061b8a9260aa38f9d4089eb21bd5d29fc92b2cd0307dc"
    if args.package in ("boundary", "request", "session", "step", "profiles", "circle"):
        assert digest(presentation) == "1d0f8a87c83d57ee0547baaa3b490ffca5d99758818e5a51b90bd492766e7ef7"
        assert digest(visual_base) == "f05a70a536db811b7fa0285ee419a053842efa63edec8a5ff94c429965a18269"
    if args.package in ("request", "session", "step", "profiles", "circle"):
        assert digest(boundary) == "afde6a765efd4bc181c8e9883f31cf9935a83a59f8fba1907d246a81f8698b75"
    if args.package in ("session", "step", "profiles", "circle"):
        assert digest(request) == "8f92d9737136c2a4556bb024fd912ed8b4a8e2ea7266677dc4ab9a4e7f5842ed"
    if args.package in ("step", "profiles", "circle"):
        assert digest(session) == "ef40621f93b72d00995df43f6197f39c8baafa7285d731e7442355d7dea97e7e"
    if args.package in ("profiles", "circle"):
        assert digest(step) == "93b35a0461391c933d046162c0729b255465293f072bff4b588dea4167ba0c4a"
    if args.package == "circle":
        assert digest(profiles) == "9195df3af2bd9710d36eea33f4923f2f7691651862407a0ac64961c392675fbe"
        visual_base = repo.parent / "2026-10-14/s-se-puede-esto-es-lo/outputs/Eagle-1.0.5-92-circulo-app.ipa"
        assert digest(visual_base) == "6f2d57f8c8949f68ef5fc5fca97cb86387b6e3f1a021966416f2ee259ccdd832"
        if status_fix:
            assert digest(circle) == "d166cfa1d860dd9969f5c41e6673f7d210571ca68af7949b78f3ac9756dc940f"
            visual_base = circle
        if launch:
            assert digest(circle) == "d166cfa1d860dd9969f5c41e6673f7d210571ca68af7949b78f3ac9756dc940f"
            visual_base = repo.parent / "2026-10-14/s-se-puede-esto-es-lo/outputs/Eagle-1.0.5-92-logo-apertura.ipa"
            assert digest(visual_base) == "27ed012b6ab47af23ebe1cd1e32d20556f9df3b6bc8265bd2dae7b35a74a208d"
    if polished:
        visual_base = repo.parent / "2026-10-14/s-se-puede-esto-es-lo/outputs/Eagle-1.0.6-93-chino-pulido.ipa"
        assert digest(visual_base) == "40ce3fba11d83e3c635bd574ad34fd0e8f5c81e615497132c3bde6036c725f5c"
        if polished_build == "95":
            visual_base = repo / "artifacts/Eagle-1.0.6-94-Test-20261016/Eagle-1.0.6-94-Test.ipa"
            assert digest(visual_base) == "156273032a07c708abe5da4293b957e1b3dd574a582e7197002cf77ffbe070e5"
    previous = repo / "artifacts/Eagle-Core-Island-Flows-Test-20261011/Eagle-1.0.5-92-Core-Island-Flows-Test.ipa"
    assert digest(previous) == "ed3b72d068db492cb06b6a7a3fee273a21422e2e07ba3a4cbdc12deae50f9417"
    assert digest(artifact) == digest(repo / "build/Eagle.ipa")
    log = (artifact.parent / "build.log").read_text()
    for expected in ["Prepare support matrices passed (34/34).", "Kernel pointer guards passed.", "** BUILD SUCCEEDED **"]:
        assert expected in log, expected
    with zipfile.ZipFile(artifact) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert len(set(names)) == len(names)
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            assert not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename
            assert path.parts[0] == "Payload"
            assert len(path.parts) == 1 or path.parts[1] == "Eagle.app"
            assert not stat.S_ISLNK(entry.external_attr >> 16)
        info = plistlib.loads(archive.read("Payload/Eagle.app/Info.plist"))
        assert info["CFBundleIdentifier"] == "com.leonardobaptiste.laracustom"
        assert (info["CFBundleShortVersionString"], info["CFBundleVersion"]) == (("1.0.6", polished_build if polished else "93") if candidate else ("1.0.5", "92"))
        assert info["CFBundleExecutable"] == "Eagle"
        if launch:
            assert info["UILaunchScreen"]["UIColorName"] == "EagleLaunchBackground"
            if polished:
                assert "UIImageName" not in info["UILaunchScreen"], "Polished launch uses its animated mark, not a duplicate static mark"
            else:
                assert info["UILaunchScreen"]["UIImageName"] == "EagleLaunchMark"
            assert info["UIStatusBarHidden"] is True
        if args.package in ("boundary", "request", "session", "step", "profiles", "circle"):
            with zipfile.ZipFile(visual_base) as previous_visual:
                assert set(names) == set(previous_visual.namelist()), "Visual base resources were added or removed"
                changed = [name for name in names if archive.read(name) != previous_visual.read(name)]
                metadata = "Payload/Eagle.app/Metadata.appintents/version.json"
                if args.package in ("session", "step", "profiles", "circle") and metadata in changed:
                    # Xcode emitted identical values in a different JSON key order.
                    # Do not rewrite/re-sign the artifact or allow other resource changes.
                    assert app_intents_version(archive.read(metadata)) == app_intents_version(previous_visual.read(metadata))
                    changed.remove(metadata)
                if candidate:
                    plist_name = "Payload/Eagle.app/Info.plist"
                    old_info = plistlib.loads(previous_visual.read(plist_name))
                    expected_info = dict(old_info, CFBundleShortVersionString="1.0.6", CFBundleVersion=polished_build if polished else "93")
                    assert info == expected_info, "Unexpected bundle metadata change"
                    if plist_name in changed:
                        changed.remove(plist_name)
                    for locale in (("en", "es", "zh-Hans") if polished else ("en", "es")):
                        nlu_name = f"Payload/Eagle.app/{locale}.lproj/nlu.appintents/nlu.lzfse"
                        if nlu_name in changed:
                            verify_trained_shortcuts(archive.read(nlu_name), previous_visual.read(nlu_name), locale)
                            changed.remove(nlu_name)
                    ssu_name = "Payload/Eagle.app/Metadata.appintents/root.ssu.yaml"
                    if polished and ssu_name in changed:
                        import yaml
                        def normalize_locales(value):
                            if isinstance(value, dict):
                                return {k: normalize_locales(v) for k, v in value.items()}
                            if isinstance(value, list):
                                items = [normalize_locales(v) for v in value]
                                if items and all(isinstance(v, dict) and "locale" in v for v in items):
                                    assert len({v["locale"] for v in items}) == len(items)
                                    return sorted(items, key=lambda v: v["locale"])
                                return items
                            return value
                        assert normalize_locales(yaml.safe_load(archive.read(ssu_name))) == normalize_locales(yaml.safe_load(previous_visual.read(ssu_name)))
                        changed.remove(ssu_name)
                    assets_name = "Payload/Eagle.app/Assets.car"
                    if assets_name in changed:
                        # CoreUI containers can differ bytewise with identical renditions.
                        # Compare every asset's digest, dimensions, appearance and metadata.
                        with tempfile.TemporaryDirectory(prefix="eagle-assets-compare-") as asset_temp:
                            inspections = []
                            for i, source in enumerate([archive, previous_visual]):
                                car = Path(asset_temp) / f"{i}.car"
                                car.write_bytes(source.read(assets_name))
                                inspections.append(json.loads(subprocess.check_output(["assetutil", "--info", str(car)])))
                            assert inspections[0] == inspections[1], "Asset rendition content changed"
                        changed.remove(assets_name)
                assert set(changed) <= {"Payload/Eagle.app/Eagle", "Payload/Eagle.app/_CodeSignature/CodeResources"}, \
                    "Resource changed beyond executable/signature: " + str(changed)
            for name in ("EagleWelcomeIntro.mp4", "EagleWelcomeIntro.m4a", "EagleWelcomeScene.html"):
                assert archive.read("Payload/Eagle.app/" + name) == (repo / "lara/other" / name).read_bytes()
            file_list = repo / "build/DerivedData/Build/Intermediates.noindex/lara.build/Release-iphoneos/lara.build/Objects-normal/arm64e/Eagle.SwiftFileList"
            from verify_eagle_core_project_membership import APP_VALIDATION_RELATIVE_PATHS
            compiled = {line.strip('"') for line in file_list.read_text().splitlines()}
            assert all(str(repo / source) in compiled for source in APP_VALIDATION_RELATIVE_PATHS)
            if launch:
                assert str(repo / "lara/views/new/EagleLaunchSplash.swift") in compiled
                assert str(repo / "lara/views/new/EagleBackdrop.swift") in compiled
            if candidate:
                assert str(repo / "lara/views/new/EagleScreenBackdrop.swift") in compiled
            if polished:
                assert str(repo / "lara/config/EagleChineseText.swift") in compiled
                for resource in ["Localizable.strings", "InfoPlist.strings"]:
                    assert "Payload/Eagle.app/zh-Hans.lproj/" + resource in names
            if args.package == "circle":
                for source in ["EagleBeta10WelcomeView.swift", "EagleAppShellView.swift", "EagleArrival.swift",
                               "EagleTouchPoint.swift", "EaglePressableStyle.swift", "EagleAmbientTimeline.swift",
                               "EagleSymbolMotion.swift", "EagleScrollDepth.swift"]:
                    assert str(repo / "lara/views/new" / source) in compiled, source
    # ditto preserves archive permissions for strict signature verification.
    with tempfile.TemporaryDirectory(prefix="eagle-aura-ipa-check-") as temporary:
        subprocess.run(["ditto", "-x", "-k", str(artifact), temporary], check=True)
        app = Path(temporary) / "Payload/Eagle.app"
        signatures = []
        for target in [app / "Frameworks/libgrabkernel2.dylib", app / "Frameworks/libxpf.dylib", app]:
            subprocess.run(["codesign", "--verify", "--strict", "--verbose=2", str(target)], check=True, capture_output=True)
            details = subprocess.run(["codesign", "-d", "--verbose=4", str(target)], check=True, capture_output=True, text=True)
            assert "Signature=adhoc" in details.stderr
            signatures.append(target.name)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)
        entitlements = subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL)
        assert plistlib.loads(entitlements) == plistlib.loads((repo / "Config/lara.entitlements").read_bytes())
        uuid = subprocess.check_output(["dwarfdump", "--uuid", str(app / "Eagle")], text=True).split()[:3]
        built = repo / "build/DerivedData/Build/Products/Release-iphoneos/Eagle.app/Eagle"
        assert uuid == subprocess.check_output(["dwarfdump", "--uuid", str(built)], text=True).split()[:3]
        assert uuid[2] == "(arm64e)"
    print(json.dumps({"ipa": str(artifact), "bytes": artifact.stat().st_size, "sha256": digest(artifact),
                      "bundle": info["CFBundleIdentifier"], "version": f'{info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]})', "uuid": uuid[1],
                      "architecture": uuid[2], "verified_adhoc_signatures": signatures,
                      "zip_integrity": "passed", "previous_ipa": "unchanged", "temporary_extraction": "removed",
                      "visual_resources": f"reference resources preserved; bundle build {polished_build}" if polished else "logo-apertura resources preserved; all asset renditions identical; version changed to 1.0.6 (93)" if candidate else "identical to logo-apertura IPA" if launch else "identical to Core Circle IPA" if status_fix else "identical to circulo-app IPA" if args.package == "circle" else "identical to October 15 visual IPA" if args.package in ("boundary", "request", "session", "step", "profiles") else "historical package",
                      "app_intents_metadata": "SSU content preserved (locale order may differ); NLU models differ only at checked 8-byte training timestamps" if polished else "SSU and models preserved; only the checked 8-byte training timestamp differs in each NLU model" if candidate else "same exact version/tool values; JSON key order may differ" if args.package in ("session", "step", "profiles", "circle") else "historical package",
                      "installation": "not performed"}, indent=2))


if __name__ == "__main__":
    main()
