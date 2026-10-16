import Foundation

/// Eagle-owned request for an already-prepared Dock Gallery package.
/// Package I/O and the protected executor remain behind their existing adapters.
nonisolated struct EagleDockGalleryApplyRequest: Sendable {
    let theme: EagleDockGalleryTheme
    let directory: URL
    let intensity: Double
}

struct EagleDockGalleryOutcome {
    let succeeded: Bool
    let message: String
}

@MainActor
protocol EagleDockGalleryPort {
    func applyRemote(
        _ request: EagleDockGalleryApplyRequest
    ) async -> EagleDockGalleryOutcome

    func restore() async -> EagleDockGalleryOutcome
}

@MainActor
struct EagleDockGalleryCore<Port: EagleDockGalleryPort> {
    private let port: Port

    init(port: Port) {
        self.port = port
    }

    func applyRemote(
        _ request: EagleDockGalleryApplyRequest
    ) async -> EagleDockGalleryOutcome {
        await port.applyRemote(request)
    }

    func restore() async -> EagleDockGalleryOutcome {
        await port.restore()
    }
}
