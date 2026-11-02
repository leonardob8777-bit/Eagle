import Foundation

/// PosterBoard's data-container UUID, found once while Eagle is prepared and then kept, as Coconut
/// and Pocket Poster do. With it saved, wallpapers can be added through the `.Trash` route without
/// preparing Eagle again. Only the UUID is kept, never any access.
nonisolated enum EaglePosterBoardUUID {
    static let storageKey = "eagle.posterBoard.containerUUID"

    private static let containersRoot = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application", isDirectory: true)

    /// The saved UUID, if any.
    static var saved: String? {
        // Kept exactly as iOS names the folder: the device's file system is case-sensitive.
        UserDefaults.standard.string(forKey: storageKey).flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
    }

    /// Wallpapers can be added without preparing Eagle: a UUID is saved and this iOS version
    /// supports Pocket Poster's saved-UUID route.
    static var allowsInstallWithoutPreparing: Bool {
        saved != nil && supportsSavedUUID()
    }

    /// Pocket Poster's published range for the saved-UUID `.Trash` route (as in Coconut).
    static func supportsSavedUUID(
        version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        version.majorVersion == 17
            || (version.majorVersion == 18 &&
                (version.minorVersion < 7 || (version.minorVersion == 7 && version.patchVersion < 5)))
            || (version.majorVersion == 26 && version.minorVersion < 2)
    }

    /// Reads PosterBoard's UUID from the containers directory, which needs Eagle's prepared access,
    /// and saves it when found. Returns the UUID read now, or nil without access.
    @discardableResult
    static func discoverAndSave() -> String? {
        guard let found = discover() else { return nil }
        if saved != found {
            UserDefaults.standard.set(found, forKey: storageKey)
        }
        return found
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func discover() -> String? {
        let fm = FileManager.default
        guard let containers = try? fm.contentsOfDirectory(
            at: containersRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        for container in containers {
            guard UUID(uuidString: container.lastPathComponent) != nil else { continue }
            let metadata = container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let dict = NSDictionary(contentsOf: metadata),
                  dict["MCMMetadataIdentifier"] as? String == "com.apple.PosterBoard" else { continue }
            return container.lastPathComponent
        }
        return nil
    }
}
