import Combine
import Foundation
import SwiftUI
import UIKit

private let iconThemeStorageRoot: URL = {
    let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return base
        .appendingPathComponent("Eagle", isDirectory: true)
        .appendingPathComponent("IconThemes", isDirectory: true)
}()
private let legacyIconThemeStorageRoot = URL(
    fileURLWithPath: "/var/mobile/.DO-NOT-DELETE-lara/IconThemes",
    isDirectory: true
)
private let rawThemesDir = iconThemeStorageRoot.appendingPathComponent("RawThemes", isDirectory: true)
private let processedThemesDir = iconThemeStorageRoot.appendingPathComponent("ProcessedThemes", isDirectory: true)
private let originalIconsDir = iconThemeStorageRoot.appendingPathComponent("OriginalIconsBackup", isDirectory: true)
private func clearIconCache() { LaraClearIconCache() }

enum EagleIconShape: String, CaseIterable, Identifiable {
    case original
    case circle
    case material

    static let storageKey = "eagle.iconThemes.shape"

    var id: String { rawValue }

    var liveValue: Int32 {
        switch self {
        case .original: return 0
        case .circle: return 1
        case .material: return 2
        }
    }

    var title: String {
        switch self {
        case .original:
            return LaraL10n.text(en: "Original", es: "Original")
        case .circle:
            return LaraL10n.text(en: "Circle", es: "Círculo")
        case .material:
            return "Material"
        }
    }

    var summary: String {
        switch self {
        case .original:
            return LaraL10n.text(
                en: "Keeps the familiar iOS shape.",
                es: "Conserva la forma familiar de iOS."
            )
        case .circle:
            return LaraL10n.text(
                en: "Round icons inspired by Pixel launchers.",
                es: "Iconos redondos inspirados en los Pixel."
            )
        case .material:
            return LaraL10n.text(
                en: "A compact Android-style rounded square.",
                es: "Un cuadrado redondeado compacto al estilo Android."
            )
        }
    }
}

struct LaraIconTheme: Identifiable, Equatable, Hashable {
    let name: String
    let iconCount: Int

    var id: String { name }
    var url: URL { rawThemesDir.appendingPathComponent(name, isDirectory: true) }
    var cacheURL: URL { processedThemesDir.appendingPathComponent(name, isDirectory: true) }
}

struct LaraThemedIcon: Codable {
    let appID: String
    let themeName: String

    var rawThemeIconURL: URL {
        rawThemesDir.appendingPathComponent(themeName).appendingPathComponent(appID + ".png")
    }

    func cachedThemeIconURL(fileName: String, shape: EagleIconShape, appVersion: String) -> URL {
        processedThemesDir
            .appendingPathComponent(themeName)
            .appendingPathComponent(shape.rawValue)
            .appendingPathComponent(appID + "----" + appVersion + "----" + fileName)
    }
}

struct LaraThemedApp: Identifiable, Hashable {
    let bundleIdentifier: String
    var name: String
    let version: String
    let bundleURL: URL
    var pngIconPaths: [String]
    var hiddenFromSpringboard: Bool

    var id: String { bundleIdentifier + "|" + bundleURL.path }

    struct BackedUpPNG {
        let bundleIdentifier: String
        let iconName: String
        let data: Data
    }

    func loadPreviewIcon() -> UIImage? {
        guard let bundle = Bundle(path: bundleURL.path) else { return nil }
        if let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for name in files.reversed() {
                if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                    return image
                }
            }
        }
        if let name = bundle.infoDictionary?["CFBundleIconFile"] as? String,
           let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
            return image
        }
        return nil
    }

    func backupIconURL(fileName: String) -> URL {
        originalIconsDir.appendingPathComponent(bundleIdentifier + "----" + version + "----" + fileName)
    }

    func backedUpIconURL(fileName: String) -> URL? {
        let fm = FileManager.default
        let newURL = backupIconURL(fileName: fileName)
        let oldURL = originalIconsDir.appendingPathComponent(bundleIdentifier + "----" + fileName)

        if fm.fileExists(atPath: newURL.path) {
            return newURL
        } else if fm.fileExists(atPath: oldURL.path) {
            return oldURL
        }
        return nil
    }

    func backUpPNGIcons() {
        let fm = FileManager.default
        for pngIconPath in pngIconPaths {
            let legacyURL = originalIconsDir.appendingPathComponent(bundleIdentifier + "----" + pngIconPath)
            let newURL = backupIconURL(fileName: pngIconPath)
            let sourceURL = bundleURL.appendingPathComponent(pngIconPath)

            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            if fm.fileExists(atPath: newURL.path) {
                continue
            } else if fm.fileExists(atPath: legacyURL.path) {
                try? fm.moveItem(at: legacyURL, to: newURL)
            } else {
                try? fm.copyItem(at: sourceURL, to: newURL)
            }
        }
    }

    func restorePNGIcons() throws {
        for iconName in pngIconPaths {
            guard let originalURL = backedUpIconURL(fileName: iconName) else { continue }
            let iconURL = bundleURL.appendingPathComponent(iconName)
            let data = try Data(contentsOf: originalURL)
            let result = laramgr.shared.lara_overwritefile(target: iconURL.path, data: data)
            if !result.ok {
                throw NSError(domain: "IconThemer", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): \(result.message)"])
            }
        }
    }

    @discardableResult
    func setPNGIcons(icon: LaraThemedIcon, shape: EagleIconShape) throws -> Int {
        let fm = FileManager.default
        var changedFiles = 0
        for iconName in pngIconPaths {
            let iconURL = bundleURL.appendingPathComponent(iconName)
            guard fm.fileExists(atPath: iconURL.path) else { continue }

            let cachedIconURL = icon.cachedThemeIconURL(
                fileName: iconName,
                shape: shape,
                appVersion: version
            )
            var cachedIcon = try? Data(contentsOf: cachedIconURL)

            if cachedIcon == nil {
                let imgData = try Data(contentsOf: icon.rawThemeIconURL)
                guard let themeIcon = UIImage(data: imgData) else {
                    throw NSError(domain: "IconThemer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read themed icon image at \(icon.rawThemeIconURL.path)"])
                }

                let origImageData = try Data(contentsOf: iconURL)
                guard let origImage = UIImage(data: origImageData) else {
                    throw NSError(domain: "IconThemer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not read original icon image at \(iconURL.path)"])
                }

                let pixelSize = CGSize(
                    width: max(CGFloat(origImage.cgImage?.width ?? Int(origImage.size.width)), 8),
                    height: max(CGFloat(origImage.cgImage?.height ?? Int(origImage.size.height)), 8)
                )
                let rendered = renderThemeIcon(themeIcon, size: pixelSize, shape: shape)

                guard let processedImage = rendered.pngData() else {
                    throw NSError(
                        domain: "IconThemer",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): Could not render \(iconName) as a transparent PNG"]
                    )
                }

                try? FileManager.default.createDirectory(at: cachedIconURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try processedImage.write(to: cachedIconURL)
                cachedIcon = processedImage
            }

            guard let cachedIcon else { continue }
            try overwriteIcon(at: iconURL, data: cachedIcon)
            changedFiles += 1
        }
        return changedFiles
    }

    @discardableResult
    func setOriginalPNGIcons(shape: EagleIconShape) throws -> Int {
        guard shape != .original else {
            try restorePNGIcons()
            return 0
        }

        let fm = FileManager.default
        var changedFiles = 0
        for iconName in pngIconPaths {
            let iconURL = bundleURL.appendingPathComponent(iconName)
            guard fm.fileExists(atPath: iconURL.path),
                  let originalURL = backedUpIconURL(fileName: iconName) else { continue }

            let cachedIconURL = processedThemesDir
                .appendingPathComponent("OriginalShapes")
                .appendingPathComponent(shape.rawValue)
                .appendingPathComponent(bundleIdentifier)
                .appendingPathComponent(version)
                .appendingPathComponent(iconName)

            var cachedIcon = try? Data(contentsOf: cachedIconURL)
            if cachedIcon == nil {
                let originalData = try Data(contentsOf: originalURL)
                guard let originalImage = UIImage(data: originalData) else {
                    throw NSError(
                        domain: "IconThemer",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): Could not read the original \(iconName)"]
                    )
                }

                let pixelSize = CGSize(
                    width: max(CGFloat(originalImage.cgImage?.width ?? Int(originalImage.size.width)), 8),
                    height: max(CGFloat(originalImage.cgImage?.height ?? Int(originalImage.size.height)), 8)
                )
                let rendered = renderThemeIcon(originalImage, size: pixelSize, shape: shape)
                guard let processedImage = rendered.pngData() else {
                    throw NSError(
                        domain: "IconThemer",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): Could not render \(iconName) as a transparent PNG"]
                    )
                }

                try fm.createDirectory(
                    at: cachedIconURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try processedImage.write(to: cachedIconURL)
                cachedIcon = processedImage
            }

            guard let cachedIcon else { continue }
            try overwriteIcon(at: iconURL, data: cachedIcon)
            changedFiles += 1
        }
        return changedFiles
    }

    private func overwriteIcon(at iconURL: URL, data: Data) throws {
        guard SantanderChown.chown(path: iconURL.path, uid: 501, gid: 501) else {
            throw NSError(
                domain: "IconThemer",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): Could not prepare the icon file"]
            )
        }

        let overwrite = laramgr.shared.lara_overwritefile(target: iconURL.path, data: data)
        guard overwrite.ok else {
            throw NSError(
                domain: "IconThemer",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): \(overwrite.message)"]
            )
        }

        guard SantanderChown.chown(path: iconURL.path, uid: 33, gid: 33) else {
            throw NSError(
                domain: "IconThemer",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): Could not finalize the icon file"]
            )
        }

        guard let writtenData = try? Data(contentsOf: iconURL), writtenData == data else {
            throw NSError(
                domain: "IconThemer",
                code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        LaraL10n.text(
                            en: "\(bundleIdentifier): Eagle could not verify \(iconURL.lastPathComponent) after writing it",
                            es: "\(bundleIdentifier): Eagle no pudo verificar \(iconURL.lastPathComponent) después de escribirlo"
                        )
                ]
            )
        }
    }

    private func renderThemeIcon(_ image: UIImage, size: CGSize, shape: EagleIconShape) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let canvas = CGRect(origin: .zero, size: size)
            context.cgContext.clear(canvas)
            context.cgContext.interpolationQuality = .high

            let minimumEdge = min(size.width, size.height)
            let square = CGRect(
                x: (size.width - minimumEdge) / 2,
                y: (size.height - minimumEdge) / 2,
                width: minimumEdge,
                height: minimumEdge
            )

            let contentRect: CGRect
            let maskPath: UIBezierPath?

            switch shape {
            case .original:
                contentRect = square
                maskPath = nil
            case .circle:
                contentRect = square.insetBy(dx: minimumEdge * 0.035, dy: minimumEdge * 0.035)
                maskPath = UIBezierPath(ovalIn: contentRect)
            case .material:
                contentRect = square.insetBy(dx: minimumEdge * 0.035, dy: minimumEdge * 0.035)
                maskPath = UIBezierPath(
                    roundedRect: contentRect,
                    cornerRadius: contentRect.width * 0.18
                )
            }

            context.cgContext.saveGState()
            maskPath?.addClip()
            image.draw(in: aspectFillRect(for: image.size, inside: contentRect))
            context.cgContext.restoreGState()
        }
    }

    private func aspectFillRect(for sourceSize: CGSize, inside targetRect: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return targetRect }
        let scale = max(
            targetRect.width / sourceSize.width,
            targetRect.height / sourceSize.height
        )
        let renderedSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        return CGRect(
            x: targetRect.midX - renderedSize.width / 2,
            y: targetRect.midY - renderedSize.height / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }
}

struct LaraAppIconChange {
    let app: LaraThemedApp
    let icon: LaraThemedIcon?
}

struct EagleIconApplyResult {
    let errors: [String]
    let fileChangeCount: Int
}

struct EagleLiveIconResult {
    let shapedIconCount: Int
    let themedIconCount: Int
}

final class IconThemeManager: ObservableObject {
    static let shared = IconThemeManager()

    @Published var themes: [LaraIconTheme] = []
    @Published var selectedThemeNames: [String]
    @Published var installedApps: [LaraThemedApp] = []
    @Published var isApplying = false
    @Published var applyProgress: Double = 0
    @Published var applyMessage = ""
    @Published var isFixingUp = false
    @Published var fixupProgress: Double = 0
    @Published var fixupMessage = ""
    @Published var showFixupSheet = false
    @Published var selectedIconShape: EagleIconShape {
        didSet {
            UserDefaults.standard.set(selectedIconShape.rawValue, forKey: EagleIconShape.storageKey)
        }
    }
    private let mgr = laramgr.shared

    private let fm = FileManager.default
    private let selectedThemesKey = "lara.iconThemes.selectedThemes"
    private let iconOverridesKey = "lara.iconThemes.iconOverrides"
    private let pendingFixupKey = "lara.iconThemes.pendingFixup"
    private init() {
        self.selectedThemeNames = UserDefaults.standard.stringArray(forKey: selectedThemesKey) ?? []
        self.selectedIconShape = EagleIconShape(
            rawValue: UserDefaults.standard.string(forKey: EagleIconShape.storageKey) ?? ""
        ) ?? .original
        refreshThemes()
    }

    var hasPendingFixup: Bool {
        UserDefaults.standard.bool(forKey: pendingFixupKey)
    }

    var iconOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: iconOverridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: iconOverridesKey) }
    }

    var selectedThemes: [LaraIconTheme] {
        selectedThemeNames.compactMap { name in
            themes.first(where: { $0.name == name })
        }
    }

    var preferredIcons: [String: LaraThemedIcon] {
        var result: [String: LaraThemedIcon] = [:]
        for theme in selectedThemes {
            if let icons = try? fm.contentsOfDirectory(at: theme.url, includingPropertiesForKeys: nil) {
                for icon in icons {
                    let appID = appIDFromIcon(url: icon)
                    result[appID] = LaraThemedIcon(appID: appID, themeName: theme.name)
                }
            }
        }
        for (bundleID, themeName) in iconOverrides {
            result[bundleID] = LaraThemedIcon(appID: bundleID, themeName: themeName)
        }
        return result
    }
    
    func icon_logmsg(_ message: String) {
        DispatchQueue.main.async {
            self.mgr.log += "(icon) " + message + "\n"
            globallogger.log("(icon) " + message)
        }
    }

    func unzip_logmsg(_ message: String) {
        DispatchQueue.main.async {
            self.mgr.log += "(zip) " + message + "\n"
            globallogger.log("(zip) " + message)
        }
    }

    func theme(named name: String) -> LaraIconTheme? {
        themes.first(where: { $0.name == name })
    }

    func saveSelection() {
        UserDefaults.standard.set(selectedThemeNames, forKey: selectedThemesKey)
    }

    func toggleThemeSelection(_ theme: LaraIconTheme) {
        if let idx = selectedThemeNames.firstIndex(of: theme.name) {
            selectedThemeNames.remove(at: idx)
        } else {
            selectedThemeNames.append(theme.name)
        }
        saveSelection()
    }

    func removeOverride(for bundleID: String) {
        var overrides = iconOverrides
        overrides[bundleID] = nil
        iconOverrides = overrides
    }

    func setOverride(bundleID: String, themeName: String) {
        var overrides = iconOverrides
        overrides[bundleID] = themeName
        iconOverrides = overrides
    }

    func createDirectoriesIfNeeded() {
        try? fm.createDirectory(at: rawThemesDir, withIntermediateDirectories: true, attributes: nil)
        try? fm.createDirectory(at: processedThemesDir, withIntermediateDirectories: true, attributes: nil)
        try? fm.createDirectory(at: originalIconsDir, withIntermediateDirectories: true, attributes: nil)
        migrateReadableLegacyThemesIfNeeded()
    }

    private func migrateReadableLegacyThemesIfNeeded() {
        guard ((try? fm.contentsOfDirectory(at: rawThemesDir, includingPropertiesForKeys: nil)) ?? []).isEmpty else {
            return
        }

        let legacyRawThemes = legacyIconThemeStorageRoot.appendingPathComponent("RawThemes", isDirectory: true)
        guard let legacyThemes = try? fm.contentsOfDirectory(
            at: legacyRawThemes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for legacyTheme in legacyThemes where legacyTheme.hasDirectoryPath {
            let destination = rawThemesDir.appendingPathComponent(
                legacyTheme.lastPathComponent,
                isDirectory: true
            )
            guard !fm.fileExists(atPath: destination.path) else { continue }
            try? fm.copyItem(at: legacyTheme, to: destination)
        }
    }

    func refreshThemes() {
        createDirectoriesIfNeeded()
        let contents = (try? fm.contentsOfDirectory(at: rawThemesDir, includingPropertiesForKeys: nil)) ?? []
        themes = contents
            .filter { $0.hasDirectoryPath }
            .map { url in
                LaraIconTheme(name: url.lastPathComponent, iconCount: ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "png" }.count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        selectedThemeNames.removeAll { selected in
            !themes.contains(where: { $0.name == selected })
        }
        saveSelection()
    }

    func refreshApps() throws {
        let systemApplicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplicationsURL = URL(fileURLWithPath: "/var/containers/Bundle/Application", isDirectory: true)
        var dotAppDirs: [URL] = []

        dotAppDirs += (try? fm.contentsOfDirectory(at: systemApplicationsURL, includingPropertiesForKeys: nil)) ?? []
        let userAppsDir = (try? fm.contentsOfDirectory(at: userApplicationsURL, includingPropertiesForKeys: nil)) ?? []
        for folder in userAppsDir {
            let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            if let dotApp = contents.first(where: { $0.pathExtension.lowercased() == "app" }) {
                dotAppDirs.append(dotApp)
            }
        }

        var apps: [LaraThemedApp] = []
        for bundleURL in dotAppDirs {
            let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
            guard fm.fileExists(atPath: infoPlistURL.path) else { continue }
            guard let infoPlist = NSDictionary(contentsOf: infoPlistURL) as? [String: AnyObject],
                  let bundleID = infoPlist["CFBundleIdentifier"] as? String else { continue }

            var app = LaraThemedApp(
                bundleIdentifier: bundleID,
                name: (infoPlist["CFBundleDisplayName"] as? String) ?? (infoPlist["CFBundleName"] as? String) ?? bundleURL.lastPathComponent,
                version: (infoPlist["CFBundleShortVersionString"] as? String) ?? (infoPlist["CFBundleVersion"] as? String) ?? "1",
                bundleURL: bundleURL,
                pngIconPaths: [],
                hiddenFromSpringboard: false
            )

            app.pngIconPaths = resolvedPNGIconPaths(
                infoPlist: infoPlist,
                bundleURL: bundleURL,
                bundleID: bundleID
            )
            if let tags = infoPlist["SBAppTags"] as? [String], tags.contains("hidden") {
                app.hiddenFromSpringboard = true
            }

            app.pngIconPaths = Array(NSOrderedSet(array: app.pngIconPaths)) as? [String] ?? app.pngIconPaths
            apps.append(app)
        }

        installedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func resolvedPNGIconPaths(
        infoPlist: [String: AnyObject],
        bundleURL: URL,
        bundleID: String
    ) -> [String] {
        var declaredNames: [String] = []

        for iconsKey in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = infoPlist[iconsKey] as? [String: AnyObject],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: AnyObject],
               let files = primary["CFBundleIconFiles"] as? [String] {
                declaredNames += files
            }
        }
        if let file = infoPlist["CFBundleIconFile"] as? String {
            declaredNames.append(file)
        }
        if let files = infoPlist["CFBundleIconFiles"] as? [String] {
            declaredNames += files
        }
        if bundleID == "com.apple.mobiletimer" {
            declaredNames.append("circle_borderless@2x~iphone.png")
        }

        let bundlePNGs = ((try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
        var resolved: [String] = []

        for declaredName in declaredNames {
            let normalizedName = URL(fileURLWithPath: declaredName).lastPathComponent
            let stem = URL(fileURLWithPath: normalizedName).deletingPathExtension().lastPathComponent

            let matches = bundlePNGs.filter { candidate in
                let candidateStem = candidate.deletingPathExtension().lastPathComponent
                return candidate.lastPathComponent == normalizedName ||
                    candidateStem == stem ||
                    candidateStem.hasPrefix(stem + "@") ||
                    candidateStem.hasPrefix(stem + "~")
            }
            resolved += matches.map(\.lastPathComponent)
        }

        return Array(NSOrderedSet(array: resolved)) as? [String] ?? resolved
    }

    func icons(forAppIDs appIDs: [String], from theme: LaraIconTheme) -> [UIImage?] {
        appIDs.map { try? icon(forAppID: $0, from: theme) }
    }

    func icon(forAppID appID: String, from theme: LaraIconTheme) throws -> UIImage {
        let path = theme.url.appendingPathComponent(appID + ".png").path
        guard let image = UIImage(contentsOfFile: path) else {
            throw NSError(domain: "IconThemer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not open image"])
        }
        return image
    }

    func availableOverrideChoices(for bundleID: String) -> [(theme: LaraIconTheme, image: UIImage)] {
        themes.compactMap { theme in
            guard let image = try? icon(forAppID: bundleID, from: theme) else { return nil }
            return (theme, image)
        }
    }

    func importTheme(from importURL: URL) throws {
        try importTheme(from: importURL, preferredName: nil)
    }

    func importTheme(from importURL: URL, preferredName: String?) throws {
        createDirectoriesIfNeeded()

        let workingURL = importURL.resolvingSymlinksInPath()
        let derivedThemeName = workingURL.deletingPathExtension().lastPathComponent
        let finalThemeName = sanitizedThemeName(preferredName ?? derivedThemeName)
        let isDirectory = try workingURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true

        let sourceDirectory: URL
        var temporaryDirectory: URL?
        defer {
            if let temporaryDirectory {
                try? fm.removeItem(at: temporaryDirectory)
            }
        }

        if isDirectory {
            sourceDirectory = try resolveThemeSourceDirectory(from: workingURL)
        } else {
            let ext = workingURL.pathExtension.lowercased()
            guard ext == "theme" || ext == "zip" else {
                throw NSError(domain: "IconThemer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Unsupported theme import type: \(workingURL.lastPathComponent)"])
            }

            let tempDir = fm.temporaryDirectory.appendingPathComponent("theme_import_\(UUID().uuidString)", isDirectory: true)
            temporaryDirectory = tempDir
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

            let extractDir = tempDir.appendingPathComponent("Extracted", isDirectory: true)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
            let archivePath = tempDir.appendingPathComponent("import.\(ext)")
            try Data(contentsOf: workingURL).write(to: archivePath)
            try unzipFile(at: archivePath, to: extractDir)
            sourceDirectory = try resolveThemeSourceDirectory(from: extractDir)
        }

        try installThemeIcons(from: sourceDirectory, themeName: finalThemeName)
        finishThemeImport(named: finalThemeName)
    }

    private func finishThemeImport(named themeName: String) {
        let updateState = {
            self.refreshThemes()
            if !self.selectedThemeNames.contains(themeName) {
                self.selectedThemeNames.append(themeName)
                self.saveSelection()
            }
        }
        if Thread.isMainThread {
            updateState()
        } else {
            DispatchQueue.main.sync(execute: updateState)
        }
    }

    @discardableResult
    func importSingleIcon(data: Data, for bundleID: String) throws -> LaraIconTheme {
        createDirectoriesIfNeeded()
        guard !bundleID.isEmpty,
              let image = UIImage(data: data),
              let pngData = image.pngData() else {
            throw NSError(
                domain: "IconThemer",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                    en: "This file is not a readable PNG image.",
                    es: "Este archivo no es una imagen PNG válida."
                )]
            )
        }

        let themeName = "My Icons"
        let themeURL = rawThemesDir.appendingPathComponent(themeName, isDirectory: true)
        try fm.createDirectory(at: themeURL, withIntermediateDirectories: true, attributes: nil)
        try pngData.write(to: themeURL.appendingPathComponent(bundleID + ".png"), options: .atomic)
        try? fm.removeItem(at: processedThemesDir.appendingPathComponent(themeName, isDirectory: true))

        setOverride(bundleID: bundleID, themeName: themeName)
        refreshThemes()
        guard let theme = theme(named: themeName) else {
            throw NSError(
                domain: "IconThemer",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                    en: "Eagle saved the icon but could not refresh My Icons.",
                    es: "Eagle guardó el icono, pero no pudo actualizar Mis iconos."
                )]
            )
        }
        return theme
    }

    private func installThemeIcons(from sourceDirectory: URL, themeName: String) throws {
        let themeURL = rawThemesDir.appendingPathComponent(themeName, isDirectory: true)
        let sourceIcons = validIconPNGs(in: sourceDirectory)

        guard !sourceIcons.isEmpty else {
            throw NSError(
                domain: "IconThemer",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                    en: "No PNG icons were found. Expected files named `<bundle-id>.png`.",
                    es: "No se encontraron iconos PNG. Se esperaban archivos llamados `<bundle-id>.png`."
                )]
            )
        }

        try? fm.removeItem(at: themeURL)
        try? fm.removeItem(at: processedThemesDir.appendingPathComponent(themeName, isDirectory: true))
        try fm.createDirectory(at: themeURL, withIntermediateDirectories: true, attributes: nil)

        var importedCount = 0
        for icon in sourceIcons {
            guard let data = try? Data(contentsOf: icon), UIImage(data: data) != nil else {
                icon_logmsg("skipped unreadable image: \(icon.lastPathComponent)")
                continue
            }

            let appID = appIDFromIcon(url: icon)
            guard !appID.isEmpty else { continue }
            let destination = themeURL.appendingPathComponent(appID + ".png")
            try? fm.removeItem(at: destination)
            do {
                try data.write(to: destination, options: .atomic)
                importedCount += 1
                icon_logmsg("copied icon: \(appID)")
            } catch {
                icon_logmsg("copy fail: \(appID) -> \(error.localizedDescription)")
            }
        }

        if importedCount == 0 {
            try? fm.removeItem(at: themeURL)
            throw NSError(
                domain: "IconThemer",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                    en: "The package contained PNG files, but none could be read as app icons.",
                    es: "El paquete contenía archivos PNG, pero ninguno se pudo leer como icono de app."
                )]
            )
        }
    }

    func removeTheme(_ theme: LaraIconTheme) throws {
        try? fm.removeItem(at: theme.cacheURL)
        try fm.removeItem(at: theme.url)
        selectedThemeNames.removeAll { $0 == theme.name }
        saveSelection()

        var overrides = iconOverrides
        overrides = overrides.filter { $0.value != theme.name }
        iconOverrides = overrides

        refreshThemes()
    }

    func neededChanges() throws -> [LaraAppIconChange] {
        if installedApps.isEmpty {
            try refreshApps()
        }

        let preferredIcons = preferredIcons
        return installedApps
            .filter { !$0.hiddenFromSpringboard && !$0.pngIconPaths.isEmpty }
            .map { app in
                if let themedIcon = preferredIcons[app.bundleIdentifier] {
                    return LaraAppIconChange(app: app, icon: themedIcon)
                }

                var bundleComponents = app.bundleIdentifier.components(separatedBy: ".")
                if bundleComponents.count > 2 {
                    bundleComponents.removeLast()
                    let parentBundleID = bundleComponents.joined(separator: ".")
                    if let themedIcon = preferredIcons[parentBundleID] {
                        return LaraAppIconChange(app: app, icon: themedIcon)
                    }
                }

                return LaraAppIconChange(app: app, icon: nil)
            }
    }

    @discardableResult
    func applyThemes() throws -> EagleIconApplyResult {
        createDirectoriesIfNeeded()
        let changes = try neededChanges()
        let chosenShape = selectedIconShape
        let changeCount = max(Double(changes.count), 1.0)
        var errors: [String] = []
        var changedCount = 0

        DispatchQueue.main.async {
            self.isApplying = true
            self.applyProgress = 0
            self.applyMessage = LaraL10n.text(
                en: "Preparing icon changes…",
                es: "Preparando los iconos…"
            )
        }

        defer {
            DispatchQueue.main.async {
                self.isApplying = false
            }
        }

        for (index, change) in changes.enumerated() {
            autoreleasepool {
                DispatchQueue.main.async {
                    self.applyProgress = Double(index) / changeCount
                    self.applyMessage = LaraL10n.text(
                        en: "Applying \(change.app.name)",
                        es: "Aplicando \(change.app.name)"
                    )
                }

                do {
                    if let icon = change.icon {
                        change.app.backUpPNGIcons()
                        try? fm.createDirectory(at: processedThemesDir.appendingPathComponent(icon.themeName), withIntermediateDirectories: true, attributes: nil)
                        changedCount += try change.app.setPNGIcons(icon: icon, shape: chosenShape)
                    } else {
                        try change.app.restorePNGIcons()
                    }
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
        }

        DispatchQueue.main.async {
            self.applyProgress = 1.0
            self.applyMessage = LaraL10n.text(
                en: "Refreshing the icon cache…",
                es: "Actualizando la caché de iconos…"
            )
        }
        clearIconCache()

        UserDefaults.standard.set(changedCount > 0, forKey: pendingFixupKey)
        return EagleIconApplyResult(errors: errors, fileChangeCount: changedCount)
    }

    func applyLiveIcons(completion: @escaping (Result<EagleLiveIconResult, Error>) -> Void) {
        let finish: (Result<EagleLiveIconResult, Error>) -> Void = { result in
            DispatchQueue.main.async {
                self.isApplying = false
                completion(result)
            }
        }

        let applyWithSession: (RemoteCall) -> Void = { process in
            let targetPID = process.pid
            let currentPID = "SpringBoard".withCString { find_process_pid($0) }
            guard targetPID > 0,
                  currentPID == targetPID,
                  process.creatingExtraThread else {
                let reason = "Live icons SpringBoard session identity failed " +
                    "(target \(targetPID), current \(currentPID), isolated \(process.creatingExtraThread))"
                self.mgr.quarantineRemoteCall(reason: reason)
                finish(.failure(NSError(
                    domain: "IconThemer",
                    code: 14,
                    userInfo: [NSLocalizedDescriptionKey: reason]
                )))
                return
            }

            let iconPaths = self.preferredLiveIconPaths()
            let shape = self.selectedIconShape.liveValue
            let label = "Live Icons \(UUID().uuidString)"
            guard self.mgr.beginExclusiveRemoteCall(label: label, expectedSession: process) else {
                finish(.failure(NSError(
                    domain: "IconThemer",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                        en: "Another protected SpringBoard operation is active. Wait and try again.",
                        es: "Hay otra operación protegida de SpringBoard activa. Espera e inténtalo de nuevo."
                    )]
                )))
                return
            }

            DispatchQueue.main.async {
                self.isApplying = true
                self.applyProgress = 0.86
                self.applyMessage = LaraL10n.text(
                    en: "Applying the live Home Screen style…",
                    es: "Aplicando el estilo en vivo…"
                )
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let shaped: Int
                let themed: Int
                if shape == EagleIconShape.original.liveValue {
                    shaped = Int(eagle_apply_live_icon_shape(process, shape))
                    themed = Int(eagle_apply_live_icon_theme(process, iconPaths, shape))
                } else {
                    themed = Int(eagle_apply_live_icon_theme(process, iconPaths, shape))
                    shaped = Int(eagle_apply_live_icon_shape(process, shape))
                }

                let healthy = process.isHealthy
                let timedOut = process.lastCallTimedOut
                let error = process.lastError
                let pidAfter = "SpringBoard".withCString { find_process_pid($0) }

                DispatchQueue.main.async {
                    self.mgr.endExclusiveRemoteCall(label: label)
                }

                guard pidAfter == targetPID else {
                    self.mgr.quarantineRemoteCall(
                        reason: "SpringBoard restarted during live icon apply"
                    )
                    finish(.failure(NSError(
                        domain: "IconThemer",
                        code: 16,
                        userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                            en: "SpringBoard restarted during live icon apply. Nothing was reported as applied.",
                            es: "SpringBoard se reinició durante la aplicación de iconos. Nada se marcó como aplicado."
                        )]
                    )))
                    return
                }

                guard healthy, !timedOut, error?.isEmpty != false else {
                    self.mgr.quarantineRemoteCall(
                        reason: error ?? "Live icon RemoteCall transport became unhealthy"
                    )
                    finish(.failure(NSError(
                        domain: "IconThemer",
                        code: 17,
                        userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                            en: "The live icon call became unhealthy. Close and reopen Eagle before another test.",
                            es: "La llamada de iconos dejó de estar estable. Cierra y abre Eagle antes de otra prueba."
                        )]
                    )))
                    return
                }

                guard shaped > 0 else {
                    finish(.failure(NSError(
                        domain: "IconThemer",
                        code: 13,
                        userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                            en: "SpringBoard did not expose any Home Screen app icons. Unlock the phone, return to the Home Screen once, reopen Eagle, and try again.",
                            es: "SpringBoard no mostró iconos de apps. Desbloquea el iPhone, ve una vez a la pantalla de inicio, vuelve a Eagle e inténtalo de nuevo."
                        )]
                    )))
                    return
                }

                finish(.success(EagleLiveIconResult(
                    shapedIconCount: shaped,
                    themedIconCount: max(themed, 0)
                )))
            }
        }

        DispatchQueue.main.async {
            self.isApplying = true
            self.applyProgress = 0.78
            self.applyMessage = LaraL10n.text(
                en: "Connecting to SpringBoard…",
                es: "Conectando con SpringBoard…"
            )
        }

        guard mgr.dsready else {
            finish(.failure(NSError(
                domain: "IconThemer",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: LaraL10n.text(
                    en: "Complete Eagle setup before applying live icons.",
                    es: "Completa la preparación de Eagle antes de aplicar iconos en vivo."
                )]
            )))
            return
        }

        mgr.prepareFreshRemoteCall(process: "SpringBoard", timeout: 20) { process, error in
            if let process {
                applyWithSession(process)
            } else {
                let detail = error?.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(.failure(NSError(
                    domain: "IconThemer",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false
                        ? detail!
                        : LaraL10n.text(
                            en: "Eagle could not start the live SpringBoard session.",
                            es: "Eagle no pudo iniciar la sesión en vivo con SpringBoard."
                        )]
                )))
            }
        }
    }

    private func preferredLiveIconPaths() -> [String: String] {
        let icons = preferredIcons
        var paths: [String: String] = [:]

        for (bundleID, icon) in icons where fm.fileExists(atPath: icon.rawThemeIconURL.path) {
            paths[bundleID] = icon.rawThemeIconURL.path
        }

        for app in installedApps where paths[app.bundleIdentifier] == nil {
            var components = app.bundleIdentifier.components(separatedBy: ".")
            guard components.count > 2 else { continue }
            components.removeLast()
            let parentID = components.joined(separator: ".")
            if let parentPath = paths[parentID] {
                paths[app.bundleIdentifier] = parentPath
            }
        }
        return paths
    }

    func startPendingFixupIfPossible() {
        guard hasPendingFixup, !isFixingUp, laramgr.shared.sbxready else { return }
        showFixupSheet = true
        startPendingFixup()
    }

    func startPendingFixup() {
        guard hasPendingFixup, !isFixingUp else { return }
        if installedApps.isEmpty {
            try? refreshApps()
        }

        isFixingUp = true
        fixupProgress = 0
        fixupMessage = LaraL10n.text(
            en: "Restoring original app icons…",
            es: "Restaurando los iconos originales…"
        )

        let apps = installedApps.filter { !$0.hiddenFromSpringboard && !$0.pngIconPaths.isEmpty }
        let appCount = max(Double(apps.count), 1.0)

        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            for (index, app) in apps.enumerated() {
                DispatchQueue.main.async {
                    self.fixupProgress = Double(index) / appCount
                    self.fixupMessage = LaraL10n.text(
                        en: "Finishing \(app.name)",
                        es: "Terminando \(app.name)"
                    )
                }
                do {
                    try app.restorePNGIcons()
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            DispatchQueue.main.async {
                self.fixupProgress = 1.0
                self.fixupMessage = errors.isEmpty
                    ? LaraL10n.text(
                        en: "Your icons are ready and your apps should work normally.",
                        es: "Tus iconos están listos y las apps deberían funcionar normalmente."
                    )
                    : errors.joined(separator: "\n\n")
                self.isFixingUp = false
                UserDefaults.standard.set(false, forKey: self.pendingFixupKey)
            }
        }
    }

    func dismissFixupSheet() {
        showFixupSheet = false
    }

    func clearSelectionsForFullReset() {
        selectedThemeNames = []
        saveSelection()
        iconOverrides = [:]
    }

    private func iconFileEnding(iconFilename: String) -> String {
        let baseName = URL(fileURLWithPath: iconFilename).deletingPathExtension().lastPathComponent
        let commonSuffixes = [
            "-large@3x~iphone", "-large@2x~iphone", "-large@3x", "-large@2x",
            "@3x~iphone", "@2x~iphone", "@3x~ipad", "@2x~ipad",
            "-large", "-small", "@3x", "@2x", "~iphone", "~ipad",
        ]
        if let suffix = commonSuffixes.first(where: { baseName.hasSuffix($0) }) {
            return suffix
        }
        return ""
    }

    private func appIDFromIcon(url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: iconFileEnding(iconFilename: url.lastPathComponent), with: "")
    }

    private func resolveThemeSourceDirectory(from url: URL) throws -> URL {
        icon_logmsg("resolve theme directory: \(url.path)")

        if url.lastPathComponent == "IconBundles" {
            icon_logmsg("using root iconbundles")
            return url
        }

        let iconBundlesURL = url.appendingPathComponent("IconBundles", isDirectory: true)
        if fm.fileExists(atPath: iconBundlesURL.path) {
            icon_logmsg("found direct iconbundles: \(iconBundlesURL.path)")
            return iconBundlesURL
        }

        if let subdir = try findIconBundlesDirectory(in: url) {
            icon_logmsg("found iconbundles in a subdirectory: \(subdir.path)")
            return subdir
        }

        if let pngDir = findFirstDirectoryContainingPNGs(in: url) {
            icon_logmsg("found png directory: \(pngDir.path)")
            return pngDir
        }

        icon_logmsg("failed to find theme directory")

        throw NSError(domain: "IconThemer", code: 10, userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not find icons in \(url.lastPathComponent). Expected PNGs named <bundle-id>.png."
            ]
        )
    }

    private func findFirstDirectoryContainingPNGs(in root: URL) -> URL? {
        icon_logmsg("scanning root: \(root.path)")

        var bestDirectory: URL?
        var bestIconCount = 0

        func consider(_ directory: URL) {
            let icons = validIconPNGs(in: directory)
            guard icons.count > bestIconCount else { return }
            bestDirectory = directory
            bestIconCount = icons.count
        }

        consider(root)

        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            icon_logmsg("failed to create enumerator")
            return nil
        }

        for case let url as URL in enumerator {
            guard !isArchiveMetadataURL(url),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            consider(url)
        }

        if let bestDirectory {
            icon_logmsg("selected icon directory: \(bestDirectory.path) (\(bestIconCount) valid PNGs)")
        } else {
            icon_logmsg("no directories found containing readable PNG icons")
        }
        return bestDirectory
    }

    private func validIconPNGs(in directory: URL) -> [URL] {
        let candidates = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates.filter { url in
            guard !isArchiveMetadataURL(url),
                  url.pathExtension.lowercased() == "png",
                  let data = try? Data(contentsOf: url),
                  UIImage(data: data) != nil else {
                return false
            }
            return true
        }
    }

    private func isArchiveMetadataURL(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        return components.contains("__MACOSX") ||
            url.lastPathComponent == ".DS_Store" ||
            url.lastPathComponent.hasPrefix("._")
    }

    private func sanitizedThemeName(_ name: String) -> String {
        let invalidCharacterSet = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.illegalCharacters)
            .union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalidCharacterSet).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported Theme" : cleaned
    }

    private func findIconBundlesDirectory(in root: URL) throws -> URL? {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "IconBundles" {
                return fileURL
            }
        }
        return nil
    }

    func unzipFile(at source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        let archive = try ZipArchive(data: try Data(contentsOf: source))
        unzip_logmsg("zip entries: \(archive.entries.count)")

        for entry in archive.entries {
            unzip_logmsg("entry: \(entry.path)")

            let normalizedPath = entry.path.replacingOccurrences(of: "\\", with: "/")
            let pathComponents = normalizedPath.split(separator: "/").map(String.init)
            if pathComponents.contains("__MACOSX") ||
                pathComponents.last == ".DS_Store" ||
                pathComponents.last?.hasPrefix("._") == true {
                unzip_logmsg("skip archive metadata: \(normalizedPath)")
                continue
            }
            let outputURL = destination.appendingPathComponent(normalizedPath)

            unzip_logmsg("output: \(outputURL.path)")

            guard !normalizedPath.contains("..") else {
                unzip_logmsg("skip path traversal: \(normalizedPath)")
                continue
            }

            if entry.isDirectory {
                do {
                    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                } catch {
                    unzip_logmsg("mkdir fail: \(error.localizedDescription)")
                }

            } else {

                do {
                    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let extracted = try archive.extract(entry)
                    unzip_logmsg("extracted size: \(extracted.count)")
                    
                    try extracted.write(to: outputURL)
                    unzip_logmsg("wrote to file")
                } catch { unzip_logmsg("extract fail: \(entry.path) to \(error.localizedDescription)") }
            }
        }

        unzip_logmsg("contents:")

        if let e = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil) { for case let fileURL as URL in e { unzip_logmsg(fileURL.path) } }
    }
    
    private func findNextZipHeader(
        in data: Data,
        start: Int
    ) -> Int? {

        guard start < data.count - 4 else { return nil }

        for i in start..<(data.count - 4) {

            let sig = data.subdata(in: i..<i + 4)
                .withUnsafeBytes {
                    UInt32(littleEndian: $0.load(as: UInt32.self))
                }

            if sig == 0x04034b50 {
                return i
            }

            if sig == 0x02014b50 {
                return i
            }

            if sig == 0x06054b50 {
                return i
            }
        }

        return nil
    }
}

struct IconThemeFixupView: View {
    @ObservedObject var manager = IconThemeManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: manager.isFixingUp ? "gear" : "checkmark.seal")
                    .font(.system(size: 64))
                    .foregroundStyle(manager.isFixingUp ? .orange : .green)

                Text(manager.isFixingUp ? "Fixing apps..." : "Fixup complete")
                    .font(.title2.bold())

                Text(manager.fixupMessage.isEmpty ? "Reopen Eagle after respring and initialize SBX so icon backups can be restored." : manager.fixupMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ProgressView(value: manager.fixupProgress, total: 1.0)
                    .padding(.horizontal)

                Spacer()

                Button(manager.isFixingUp ? "Please wait" : "Close") {
                    manager.dismissFixupSheet()
                }
                .buttonStyle(.borderedProminent)
                // The contrasting colour on the black/white fill, grey while disabled.
                .eagleProminentLabel()
                .disabled(manager.isFixingUp)
                .padding(.bottom)
            }
            .navigationTitle("Icon Fixup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
