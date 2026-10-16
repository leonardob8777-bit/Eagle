import Foundation

/// Decides whether the welcome (intro and updates) is due: once per installation of Eagle.
///
/// iOS places every install of the app in a new bundle container: a first install, an IPA installed
/// over an existing Eagle, or a reinstall. The container's path stays the same across normal launches,
/// so pairing it with the version identifies one installation. App data (and a plain "seen" flag)
/// survives an install over an existing copy, which is why the old fixed key never showed the welcome
/// to people who updated in place.
enum EagleWelcomeInstall {
    private static let seenKey = "eagle.welcome.seenInstallation"

    static var current: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        let container = Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent
        return "\(container)|\(version)|\(build)"
    }

    /// True until the welcome has been completed (Get started) for this installation.
    static var needsWelcome: Bool {
        UserDefaults.standard.string(forKey: seenKey) != current
    }

    static func markSeen() {
        UserDefaults.standard.set(current, forKey: seenKey)
    }
}
