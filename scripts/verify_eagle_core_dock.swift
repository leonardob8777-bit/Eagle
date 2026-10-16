import Foundation

@MainActor
private final class RecordingDockPort: EagleDockGalleryPort {
    var calls: [String] = []
    var receivedRequest: EagleDockGalleryApplyRequest?
    var applyOutcome = EagleDockGalleryOutcome(succeeded: true, message: "existing apply result")

    func applyRemote(
        _ request: EagleDockGalleryApplyRequest
    ) async -> EagleDockGalleryOutcome {
        calls.append("apply")
        receivedRequest = request
        return applyOutcome
    }

    func restore() async -> EagleDockGalleryOutcome {
        calls.append("restore")
        return EagleDockGalleryOutcome(succeeded: false, message: "existing restore result")
    }
}

@main
private enum EagleDockGalleryCoreContract {
    @MainActor
    static func main() async {
        let port = RecordingDockPort()
        let core = EagleDockGalleryCore(port: port)
        let directory = URL(fileURLWithPath: "/tmp/eagle-dock-static")
        let theme = EagleDockGalleryTheme(
            id: "static-theme", version: 7, title: "Static theme", titleES: "Tema estático",
            subtitle: "Original package", subtitleES: "Paquete original", accent: "#20C0F0",
            previewURL: URL(string: "https://example.invalid/preview.png")!,
            animatedPreviewURL: nil,
            packageURL: URL(string: "https://example.invalid/theme.zip")!,
            sha256: String(repeating: "a", count: 64), byteCount: 4096,
            frameCount: 1, fps: 1, width: 1146, height: 318
        )
        let request = EagleDockGalleryApplyRequest(
            theme: theme,
            directory: directory,
            intensity: 0.72
        )

        let applied = await core.applyRemote(request)
        precondition(applied.succeeded && applied.message == "existing apply result")
        precondition(port.receivedRequest?.theme == theme)
        precondition(port.receivedRequest?.directory == directory)
        precondition(port.receivedRequest?.intensity == 0.72)

        // Do not introduce a new intensity clamp or reinterpret adapter failures.
        port.applyOutcome = EagleDockGalleryOutcome(succeeded: false, message: "existing failure")
        let failed = await core.applyRemote(EagleDockGalleryApplyRequest(
            theme: theme, directory: directory, intensity: -0.25
        ))
        precondition(!failed.succeeded && failed.message == "existing failure")
        precondition(port.receivedRequest?.intensity == -0.25)

        let restored = await core.restore()
        precondition(!restored.succeeded && restored.message == "existing restore result")
        precondition(port.calls == ["apply", "apply", "restore"])
        print("PASS: concrete Eagle theme, exact request fields and unchanged success/failure/restore outcomes")
    }
}
