#!/usr/bin/env python3
"""Read-only final consistency audit for the separate offline preview outputs."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import stat
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory(archive):
    names = archive.namelist()
    assert len(names) == len(set(names)), "Duplicate ZIP entries"
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        assert not path.is_absolute() and ".." not in path.parts, "Unsafe ZIP path"
        assert not stat.S_ISLNK(entry.external_attr >> 16), "ZIP symlink"
    assert archive.testzip() is None, "Invalid ZIP CRC"
    return set(names)


def verify(output):
    manifest = json.loads((output / "PreviewBuildManifest.json").read_text())
    assert manifest["bundle_id"] == "com.leonardobaptiste.eagle.interfacepreview"
    assert manifest["platform"] == "device"
    assert (manifest["core_sources"], manifest["adapter_sources"], manifest["compiled_input_count"]) == (17, 5, 27)
    assert manifest["binary_audit"]["architecture"] == "arm64"
    assert manifest["binary_audit"]["entitlements"] == "none"
    assert manifest["binary_audit"]["native_engine_symbol_audit"] == "passed"
    ipa = output / manifest["ipa"]["filename"]
    assert sha(ipa.read_bytes()) == manifest["ipa"]["sha256"]
    prefix = "Payload/EagleInterfacePreview.app/"
    with zipfile.ZipFile(ipa) as archive:
        names = inventory(archive)
        expected = {prefix + item["path"] for item in manifest["bundle_files"]}
        assert names == expected and len(names) == 12, "Unexpected IPA members"
        for item in manifest["bundle_files"]:
            data = archive.read(prefix + item["path"])
            assert sha(data) == item["sha256"] and len(data) == item["byte_count"]
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        assert info["CFBundleIdentifier"] == manifest["bundle_id"]
        assert (info["CFBundleShortVersionString"], info["CFBundleVersion"]) == ("0.1.0", "1")
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
        assert info["UIDeviceFamily"] == [1]
        assert not any(name.endswith((".mobileprovision", ".dylib", ".c", ".h")) for name in names)
    source = output / manifest["corresponding_sources"]["filename"]
    assert sha(source.read_bytes()) == manifest["corresponding_sources"]["sha256"]
    with zipfile.ZipFile(source) as archive:
        names = inventory(archive)
        for item in [*manifest["sources"], *manifest["asset_input_hashes"]]:
            assert sha(archive.read(item["path"])) == item["sha256"], "Source input hash mismatch"
        assert {name for name in names if name.endswith(".swift")} == {item["path"] for item in manifest["sources"]}
        assert "lara/views/new/EagleRainbowLoadingView.swift" not in names
        assert not any(name.endswith((".c", ".h", ".m", ".a", ".dylib", ".ipa")) for name in names)
        assert {"LICENSE", "lara/licenses/NOTICE_Dynamic_Notifications.txt"}.issubset(names)
    qa = json.loads((output / "QA/PreviewQA.json").read_text())
    assert qa["result"] == "PASS" and len(qa["checks"]) == 33
    assert qa["scope"] == "interface-and-local-data-only"
    assert qa["nativeEngineIncluded"] is False and qa["systemChanges"] is False
    print("PASS: device IPA identity, 12 exact bundle files/CRCs/hashes, 27 corresponding Swift inputs, asset hashes, safe ZIP inventories/licenses and 33 local QA checks")
    print("Limits: no physical-device/gesture validation, no full Eagle or native compatibility claim")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    verify(parser.parse_args().output)
