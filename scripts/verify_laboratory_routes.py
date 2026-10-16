#!/usr/bin/env python3
"""Exercise production Home search/channel policy without native device access."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
home = (root / "lara/views/new/LaraHomeView.swift").read_text()
policy = (root / "lara/config/EagleFeaturePolicy.swift").read_text()
language = (root / "lara/EagleCore/Localization/EagleLocalization.swift").read_text() + "\n" + (root / "lara/config/LaraLanguage.swift").read_text()

def block(source, marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

# Presentation wiring checks complement the executable search tests below.
assert "if EagleFeaturePolicy.allows(.advancedSystemTools, channel: currentChannel) {\n                        laboratoryTools" in home
assert "showingLaboratory = true" in block(home, "private var laboratoryTools:")
assert '.sheet(isPresented: $showingLaboratory) {\n                LaboratoryToolsView()\n                    .environmentObject(mgr)' in home
assert "if route == .advancedSettings {\n            Button { showingSettings = true }" in home
assert "SettingsView().environmentObject(mgr)" in block(home, "private func toolDestination(")

methods = "\n".join(block(home, marker).replace("private var", "var", 1) for marker in [
    "private var normalizedToolQuery:", "private var availableToolRoutes:", "private var filteredToolRoutes:",
])
route = block(home, "private enum LaraHomeToolRoute:").replace("private enum", "enum", 1)
# Scene types are irrelevant to routing; retain the complete production policy.
stubs = "enum EagleSceneAuraMode { case glow, pulse, rainbow, tint }; enum EagleSceneAuraTarget { case island, dock }\n"
test = r'''
for channel in EagleReleaseChannel.allCases {
    var search = Search(currentChannel: channel)
    let labExpected = channel == .experimental
    precondition(search.availableToolRoutes.contains(.advancedSettings) == labExpected)
    precondition(!search.availableToolRoutes.contains(.eagleSystem))
    for term in ["Laboratory", " laboratorio ", "LAB", "RemoteCall", "kernelcache"] {
        search.toolSearchQuery = term
        precondition(search.filteredToolRoutes.contains(.advancedSettings) == labExpected, term)
    }
    for term in ["Hide Dock", "galería", "wallpapers"] {
        search.toolSearchQuery = term
        precondition(!search.filteredToolRoutes.isEmpty, term)
    }
    search.toolSearchQuery = "  "
    precondition(search.filteredToolRoutes.isEmpty)
}
precondition(EagleFeaturePolicy.channel(from: "corrupt") == .stable)
print("PASS: Laboratory accessible/searchable only in Laboratory; existing routes preserved; unknown channels fail closed")
'''
with tempfile.TemporaryDirectory(prefix="eagle-laboratory-qa-") as directory:
    directory = Path(directory)
    source = directory / "main.swift"
    source.write_text("import SwiftUI\n" + language + stubs + policy + route +
                      "\nstruct Search { var currentChannel: EagleReleaseChannel; var toolSearchQuery = \"\"\n" + methods + "\n}\n" + test)
    executable = directory / "routes"
    subprocess.run(["xcrun", "swiftc", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
