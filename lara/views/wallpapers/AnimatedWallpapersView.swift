import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers
import CryptoKit

struct LaraMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let fm = FileManager.default
            let folder = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Wallpaper Drafts", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            try fm.copyItem(at: received.file, to: destination)
            return LaraMovie(url: destination)
        }
    }
}

private enum WallpaperMode: String, CaseIterable, Identifiable {
    case explore
    case create

    var id: String { rawValue }
    var title: String {
        self == .explore
            ? LaraL10n.text(en: "Explore", es: "Explorar")
            : LaraL10n.text(en: "Create", es: "Crear")
    }
}

struct AnimatedWallpapersView: View {
    @ObservedObject private var mgr = laramgr.shared
    @StateObject private var installer = AnimatedWallpaperInstaller()

    @State private var pickerItem: PhotosPickerItem?
    @State private var movieURL: URL?
    @State private var player: AVPlayer?
    @AppStorage("eagle.wallpapers.autoReverses")
    private var autoReverses = false
    @State private var loadingSelection = false
    @State private var message: String?
    @AppStorage("eagle.wallpapers.mode")
    private var mode: WallpaperMode = .explore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Picker(LaraL10n.text(en: "Mode", es: "Modo"), selection: $mode) {
                ForEach(WallpaperMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)

            if mode == .explore {
                WallpaperGalleryView()
            } else {
                creatorView
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "Wallpapers", es: "Fondos"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { selectedMode in
            if selectedMode == .explore {
                player?.pause()
            } else {
                player?.play()
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            load(item)
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: message) { value in
            guard let value else { return }
            let installed = installer.didInstall
            EagleNotifications.shared.show(title: LaraL10n.text(en: "Animated wallpapers", es: "Fondos animados"),
                message: value, kind: installed ? .success : .information,
                actionTitle: installed ? LaraL10n.text(en: "Open Wallpapers", es: "Abrir Fondos") : nil,
                action: installed ? { installer.openWallpaperPicker() } : nil)
            message = nil
        }
        .onChange(of: installer.resultMessage) { result in
            if let result { message = result }
        }
    }

    private var creatorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                preview

                if movieURL != nil {
                    options
                }

                actionArea
                attribution
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if movieURL != nil || !mgr.sbxready {
                EagleApplyBar(ready: mgr.sbxready) {
                    installArea
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LaraL10n.text(
                en: "Your video, on the Lock Screen",
                es: "Tu video, en la pantalla de bloqueo"
            ))
                .font(.title2.weight(.bold))
            Text(LaraL10n.text(
                en: "Pick a short clip. Eagle adapts it and adds it to the iOS wallpaper collection.",
                es: "Elige un clip corto. Eagle lo adapta y lo agrega a la colección de fondos de iOS."
            ))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .eagleHeaderCard()
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.black)

            if player == nil {
                previewAurora
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .allowsHitTesting(false)
            }

            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .onAppear {
                        player.isMuted = true
                        player.play()
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 38, weight: .medium))
                    Text(LaraL10n.text(en: "Select a video", es: "Selecciona un video"))
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.82))
            }

            VStack(spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption.weight(.medium))
                Text("9:41")
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .padding(.top, 38)
            .allowsHitTesting(false)
        }
        .aspectRatio(9.0 / 17.5, contentMode: .fit)
        .frame(maxWidth: 286)
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.13), radius: 20, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(movieURL == nil
            ? LaraL10n.text(en: "Empty preview", es: "Vista previa vacía")
            : LaraL10n.text(en: "Animated wallpaper preview", es: "Vista previa del fondo animado"))
    }

    // Slow, soft aurora that orbits behind the empty preview so the mock feels
    // alive. Hidden once a real video is loaded; frozen with Reduce Motion.
    private var previewAurora: some View {
        EagleAmbientTimeline(paused: reduceMotion) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let spin = reduceMotion
                ? 0
                : (seconds / 16).truncatingRemainder(dividingBy: 1) * 360

            ZStack {
                auroraBlob(Color(red: 0.30, green: 0.80, blue: 1.00), size: 220, x: -60, y: -150)
                auroraBlob(Color(red: 0.62, green: 0.40, blue: 1.00), size: 240, x: 70, y: -20)
                auroraBlob(Color(red: 1.00, green: 0.42, blue: 0.72), size: 200, x: -50, y: 150)
            }
            .rotationEffect(.degrees(spin))
            .blur(radius: 45)
            .opacity(0.5)
        }
    }

    private func auroraBlob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }

    private var options: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $autoReverses) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LaraL10n.text(en: "Smooth loop", es: "Repetición suave"))
                        .font(.body.weight(.medium))
                    Text(LaraL10n.text(
                        en: "The video plays backward before starting over.",
                        es: "El video vuelve hacia atrás antes de comenzar otra vez."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)
            .padding(18)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Label(movieURL == nil
                    ? LaraL10n.text(en: "Choose video", es: "Elegir video")
                    : LaraL10n.text(en: "Choose another video", es: "Elegir otro video"),
                    systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EagleSecondaryButtonStyle())
            .disabled(installer.isWorking || loadingSelection)
        }
    }

    /// "Add to Wallpapers" and its progress, in the screen's fixed bottom bar.
    @ViewBuilder
    private var installArea: some View {
        VStack(spacing: 12) {
            if installer.isWorking {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(installer.progressLabel)
                            .font(.footnote.weight(.medium))
                        Spacer()
                        Text("\(Int(installer.progress * 100))%")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: installer.progress)

                    Button(LaraL10n.text(en: "Cancel", es: "Cancelar"), role: .cancel) {
                        installer.cancel()
                    }
                    .font(.footnote.weight(.medium))
                }
                .transition(.opacity)
            }

            if let movieURL {
                Button {
                    installer.install(video: movieURL, autoReverses: autoReverses)
                } label: {
                    HStack {
                        if installer.isWorking {
                            ProgressView()
                                .tint(EagleVisualTheme.actionText)
                        }
                        Text(installer.isWorking
                            ? LaraL10n.text(en: "Preparing wallpaper…", es: "Preparando fondo…")
                            : LaraL10n.text(en: "Add to Wallpapers", es: "Agregar a Fondos"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EagleApplyButtonStyle(busy: installer.isWorking))
                .disabled(!mgr.sbxready || installer.isWorking)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: installer.isWorking)
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LaraL10n.text(
                en: "Up to 12 seconds. Audio is not included.",
                es: "Hasta 12 segundos. El audio no se incluye."
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Link(LaraL10n.text(en: "Powered by Pocket Poster", es: "Tecnología basada en Pocket Poster"), destination: URL(string: "https://github.com/leminlimez/Pocket-Poster")!)
                .font(.footnote.weight(.medium))
        }
        .padding(.top, 4)
    }

    private func load(_ item: PhotosPickerItem) {
        loadingSelection = true
        Task {
            do {
                guard let movie = try await item.loadTransferable(type: LaraMovie.self) else {
                    throw AnimatedWallpaperError.invalidVideo
                }
                let durationTime = try await AVURLAsset(url: movie.url).load(.duration)
                let duration = CMTimeGetSeconds(durationTime)
                guard duration.isFinite, duration > 0 else {
                    throw AnimatedWallpaperError.invalidVideo
                }
                guard duration <= AnimatedWallpaperBuilder.maximumDuration else {
                    throw AnimatedWallpaperError.videoTooLong
                }

                await MainActor.run {
                    player?.pause()
                    movieURL = movie.url
                    player = AVPlayer(url: movie.url)
                    player?.isMuted = true
                    player?.play()
                    loadingSelection = false
                    pickerItem = nil
                }
            } catch {
                await MainActor.run {
                    loadingSelection = false
                    pickerItem = nil
                    message = error.localizedDescription
                }
            }
        }
    }
}

enum AnimatedWallpaperError: LocalizedError {
    case invalidVideo
    case videoTooLong
    case cancelled
    case noFrames
    case posterBoardNotFound
    case posterBoardUnavailable
    case installationFailed
    case invalidDescriptor
    case descriptorAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidVideo:
            return LaraL10n.text(en: "That video could not be read. Try another file.", es: "No se pudo leer ese video. Prueba con otro archivo.")
        case .videoTooLong:
            return LaraL10n.text(en: "The video must be 12 seconds or shorter.", es: "El video debe durar 12 segundos o menos.")
        case .cancelled:
            return LaraL10n.text(en: "Preparation was canceled.", es: "La preparación fue cancelada.")
        case .noFrames:
            return LaraL10n.text(en: "No frames could be extracted from the video.", es: "No se pudieron extraer imágenes del video.")
        case .posterBoardNotFound:
            return LaraL10n.text(en: "Eagle could not find the system wallpaper collection.", es: "Eagle no pudo encontrar la colección de fondos del sistema.")
        case .posterBoardUnavailable:
            return LaraL10n.text(en: "The wallpaper collection is not ready on this device yet.", es: "La colección de fondos todavía no está preparada en este dispositivo.")
        case .installationFailed:
            return LaraL10n.text(en: "The wallpaper could not be installed. The existing collection was not changed.", es: "El fondo no pudo instalarse. No se modificó la colección existente.")
        case .invalidDescriptor:
            return LaraL10n.text(en: "The package does not contain every file PosterBoard needs.", es: "El paquete no contiene todos los archivos que PosterBoard necesita.")
        case .descriptorAlreadyExists:
            return LaraL10n.text(en: "This wallpaper already exists, but its current copy is invalid.", es: "Este fondo ya existe, pero su copia actual no es válida.")
        }
    }
}

nonisolated private final class AnimatedWallpaperCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false

    func reset() {
        lock.lock()
        cancellationRequested = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }
}

final class AnimatedWallpaperInstaller: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressLabel = LaraL10n.text(en: "Preparing", es: "Preparando")
    @Published private(set) var resultMessage: String?
    @Published private(set) var didInstall = false

    private let cancellation = AnimatedWallpaperCancellation()

    func install(video: URL, autoReverses: Bool) {
        guard !isWorking, laramgr.shared.sbxready else { return }

        cancellation.reset()

        didInstall = false
        resultMessage = nil
        isWorking = true
        progress = 0
        progressLabel = LaraL10n.text(en: "Analyzing video", es: "Analizando video")

        let screenSize = AnimatedWallpaperBuilder.recommendedPixelSize()

        let cancellation = cancellation
        Task.detached(priority: .userInitiated) { [self, cancellation] in
            var buildRoot: URL?
            do {
                let build = try await AnimatedWallpaperBuilder.build(
                    video: video,
                    autoReverses: autoReverses,
                    targetSize: screenSize,
                    isCancelled: { cancellation.isCancelled },
                    progress: { [self] value, label in
                        Task { @MainActor in
                            self.progress = value * 0.88
                            self.progressLabel = label
                        }
                    }
                )
                buildRoot = build.workingRoot

                if cancellation.isCancelled { throw AnimatedWallpaperError.cancelled }
                await MainActor.run {
                    self.progress = 0.92
                    self.progressLabel = LaraL10n.text(en: "Adding to Wallpapers", es: "Agregando a Fondos")
                }

                _ = try PosterBoardWriter.install(descriptor: build.descriptorURL)

                await MainActor.run {
                    let refreshed = PosterBoardWriter.refreshCollections()
                    globallogger.log("(wallpaper) collection refresh requested, success=\(refreshed)")
                    self.progress = 1
                    self.progressLabel = LaraL10n.text(en: "Done", es: "Listo")
                    self.isWorking = false
                    self.didInstall = true
                    self.resultMessage = LaraL10n.text(
                        en: "Imported and verified. Open Wallpapers, select the new wallpaper, then close Wallpapers from the app switcher if it does not appear immediately.",
                        es: "Importado y verificado. Abre Fondos, selecciona el fondo nuevo y, si no aparece de inmediato, cierra Fondos desde el selector de apps."
                    )
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.didInstall = false
                    self.resultMessage = error.localizedDescription
                }
            }

            if let buildRoot {
                try? FileManager.default.removeItem(at: buildRoot)
            }
        }
    }

    func cancel() {
        cancellation.cancel()
        progressLabel = LaraL10n.text(en: "Canceling", es: "Cancelando")
    }

    @discardableResult
    func openWallpaperPicker() -> Bool {
        let opened = "com.apple.PosterBoard".withCString { launch_app($0) } == 0
        globallogger.log("(wallpaper) PosterBoard launch success=\(opened)")
        if !opened {
            didInstall = false
            resultMessage = LaraL10n.text(
                en: "Eagle imported the wallpaper, but Wallpapers could not be opened. Open Wallpapers manually and select the new item.",
                es: "Eagle importó el fondo, pero no pudo abrir Fondos. Abre Fondos manualmente y selecciona el elemento nuevo."
            )
        }
        return opened
    }

}

struct PosterBoardInstallResult {
    let destination: URL
    let wasCreated: Bool
}

nonisolated enum PosterBoardWriter {
    static let collectionsExtension = "com.apple.WallpaperKit.CollectionsPoster"
    static let mercuryExtension = "com.apple.MercuryPoster"
    static let photosExtension = "com.apple.PhotosUIPrivate.PhotosPosterProvider"

    @discardableResult
    static func install(
        descriptor: URL,
        extensionIdentifier: String = collectionsExtension,
        preserveDescriptorName: Bool = false
    ) throws -> PosterBoardInstallResult {
        let fm = FileManager.default
        guard let containerID = posterBoardContainerID() else {
            throw AnimatedWallpaperError.posterBoardNotFound
        }
        log("(wallpaper) Lara resolved the PosterBoard container on-device")

        let sourceFingerprint = try descriptorFingerprint(at: descriptor)

        let version = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17 ? "61" : "59"
        let target = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application")
            .appendingPathComponent(containerID, isDirectory: true)
            .appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent(extensionIdentifier, isDirectory: true)
            .appendingPathComponent("descriptors", isDirectory: true)

        guard fm.fileExists(atPath: target.deletingLastPathComponent().path) else {
            throw AnimatedWallpaperError.posterBoardUnavailable
        }

        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let destinationName = preserveDescriptorName
            ? descriptor.lastPathComponent
            : UUID().uuidString.uppercased()
        let destination = target.appendingPathComponent(destinationName, isDirectory: true)

        if fm.fileExists(atPath: destination.path) {
            let existingFingerprint = try descriptorFingerprint(at: destination)
            guard existingFingerprint == sourceFingerprint else {
                throw AnimatedWallpaperError.descriptorAlreadyExists
            }
            // Older Eagle builds copied descriptors directly. Re-import an
            // identical entry through the bridge so PosterBoard receives the
            // filesystem move it uses to discover a new descriptor.
            try fm.removeItem(at: destination)
            do {
                try importThroughLaraBridge(
                    descriptor: descriptor,
                    destination: destination,
                    targetDirectory: target,
                    expectedFingerprint: sourceFingerprint
                )
                return PosterBoardInstallResult(destination: destination, wasCreated: true)
            } catch {
                try? fm.copyItem(at: descriptor, to: destination)
                throw error
            }
        }

        try importThroughLaraBridge(
            descriptor: descriptor,
            destination: destination,
            targetDirectory: target,
            expectedFingerprint: sourceFingerprint
        )
        return PosterBoardInstallResult(destination: destination, wasCreated: true)
    }

    @MainActor
    static func refreshCollections() -> Bool {
        let flagsWritten = requestPosterBoardRefresh()
        var languageRefreshRequested = false

        if #available(iOS 18.0, *),
           let language = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first,
           let settingsUtilities = objc_getClass("IPSettingsUtilities") as? NSObject {
            // setLanguage: returns void on some builds, so a nil perform result
            // does not mean the selector was not invoked.
            _ = settingsUtilities.perform(
                NSSelectorFromString("setLanguage:"),
                with: language
            )
            languageRefreshRequested = true
        }

        return flagsWritten || languageRefreshRequested
    }

    /// Matches Nugget's current PosterBoard refresh request. Preserve every
    /// existing preference and update only the two cache/file-protection flags.
    private static func requestPosterBoardRefresh() -> Bool {
        guard let containerID = posterBoardContainerID() else { return false }

        let preferences = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application")
            .appendingPathComponent(containerID, isDirectory: true)
            .appendingPathComponent("Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist")

        do {
            var values: [String: Any] = [:]
            var format: PropertyListSerialization.PropertyListFormat = .binary
            if let existing = try? Data(contentsOf: preferences), !existing.isEmpty {
                values = try PropertyListSerialization.propertyList(
                    from: existing,
                    options: [],
                    format: &format
                ) as? [String: Any] ?? [:]
            }

            values["PBF_LOCALE_DID_CHANGE"] = false
            values["PBF_RESET_FILE_PROTECTIONS"] = true
            let encoded = try PropertyListSerialization.data(
                fromPropertyList: values,
                format: format == .openStep ? .binary : format,
                options: 0
            )
            try encoded.write(to: preferences, options: .atomic)
            log("(wallpaper) requested PosterBoard cache and file-protection refresh")
            return true
        } catch {
            log("(wallpaper) PosterBoard refresh request failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func descriptorFingerprint(at descriptor: URL) throws -> DescriptorFingerprint {
        let fm = FileManager.default
        let requiredFiles = [
            "com.apple.posterkit.provider.descriptor.identifier",
            "com.apple.posterkit.role.identifier",
            "providerInfo.plist"
        ]
        guard requiredFiles.allSatisfy({
            fm.fileExists(atPath: descriptor.appendingPathComponent($0).path)
        }),
        fm.fileExists(atPath: descriptor.appendingPathComponent("versions", isDirectory: true).path),
        let enumerator = fm.enumerator(
            at: descriptor,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AnimatedWallpaperError.invalidDescriptor
        }

        var files: [DescriptorFileFingerprint] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = String(file.path.dropFirst(descriptor.path.count + 1))
            files.append(DescriptorFileFingerprint(
                relativePath: relativePath,
                byteCount: UInt64(max(values.fileSize ?? 0, 0)),
                sha256: try sha256(of: file)
            ))
        }
        files.sort { $0.relativePath < $1.relativePath }
        guard files.count >= 4, files.reduce(UInt64(0), { $0 + $1.byteCount }) > 64 else {
            throw AnimatedWallpaperError.invalidDescriptor
        }
        return DescriptorFingerprint(files: files)
    }

    /// Adapted from Pocket Poster's GPL-3.0 `SymHandler`/`applyTendies`
    /// implementation: https://github.com/leminlimez/Pocket-Poster
    /// Pocket Poster imports descriptors by moving them through a `.Trash`
    /// symlink aimed at PosterBoard's descriptor store. Eagle can resolve that
    /// store on-device after Lara opens temporary access, so the same proven
    /// import path can run without a PC or a separately supplied app hash.
    private static func importThroughLaraBridge(
        descriptor: URL,
        destination: URL,
        targetDirectory: URL,
        expectedFingerprint: DescriptorFingerprint
    ) throws {
        let fm = FileManager.default
        let documents = ProcessInfo.processInfo.environment["LC_HOME_PATH"]
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("Documents", isDirectory: true) }
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documents else {
            throw AnimatedWallpaperError.installationFailed
        }

        let bridge = documents.appendingPathComponent(".Trash", isDirectory: false)
        let staging = documents.appendingPathComponent(
            destination.lastPathComponent,
            isDirectory: true
        )
        var bridgeCreated = false
        var importCompleted = false

        defer {
            if !importCompleted {
                try? fm.removeItem(at: destination)
            }
            try? fm.removeItem(at: staging)
            if bridgeCreated {
                try? fm.removeItem(at: bridge)
            }
        }

        if let attributes = try? fm.attributesOfItem(atPath: bridge.path) {
            guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
                throw AnimatedWallpaperError.installationFailed
            }
            try fm.removeItem(at: bridge)
        }

        try fm.createSymbolicLink(
            at: bridge,
            withDestinationURL: targetDirectory
        )
        bridgeCreated = true

        try fm.copyItem(at: descriptor, to: staging)
        var resultingURL: NSURL?
        try fm.trashItem(at: staging, resultingItemURL: &resultingURL)

        guard fm.fileExists(atPath: destination.path) else {
            throw AnimatedWallpaperError.installationFailed
        }
        let importedFingerprint = try descriptorFingerprint(at: destination)
        guard importedFingerprint == expectedFingerprint else {
            throw AnimatedWallpaperError.invalidDescriptor
        }

        importCompleted = true
        log(
            "(wallpaper) Lara bridge imported and verified \(destination.lastPathComponent)"
        )
    }

    private static func sha256(of file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    private static func log(_ message: String) {
        Task { @MainActor in
            globallogger.log(message)
        }
    }

    private static func posterBoardContainerID() -> String? {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application", isDirectory: true)
        guard let containers = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return nil
        }

        for container in containers {
            let metadata = container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let dict = NSDictionary(contentsOf: metadata),
                  let identifier = dict["MCMMetadataIdentifier"] as? String else { continue }
            if identifier == "com.apple.PosterBoard" {
                return container.lastPathComponent
            }
        }
        return nil
    }

    private struct DescriptorFingerprint: Equatable {
        let files: [DescriptorFileFingerprint]
    }

    private struct DescriptorFileFingerprint: Equatable {
        let relativePath: String
        let byteCount: UInt64
        let sha256: Data
    }
}

nonisolated enum AnimatedWallpaperBuilder {
    static let maximumDuration = 12.0
    static let maximumFrames = 300

    struct BuildResult: Sendable {
        let workingRoot: URL
        let descriptorURL: URL
    }

    @MainActor static func recommendedPixelSize() -> CGSize {
        let native = UIScreen.main.nativeBounds.size
        let shortEdge = min(native.width, native.height)
        let longEdge = max(native.width, native.height)
        let targetShort = min(shortEdge, 1080)
        let scale = targetShort / shortEdge
        return CGSize(width: targetShort, height: floor(longEdge * scale))
    }

    static func build(
        video: URL,
        autoReverses: Bool,
        targetSize: CGSize,
        isCancelled: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> BuildResult {
        let fm = FileManager.default
        let workingRoot = fm.temporaryDirectory.appendingPathComponent("EaglePoster-\(UUID().uuidString)", isDirectory: true)
        let descriptorURL = workingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: descriptorURL, withIntermediateDirectories: true)

        do {
            let identifier = Int.random(in: 10_000...99_999)
            let wallpaperName = "9183.Custom-810w-1080h@2x~ipad.wallpaper"
            let contents = descriptorURL.appendingPathComponent("versions/1/contents", isDirectory: true)
            let wallpaper = contents.appendingPathComponent(wallpaperName, isDirectory: true)
            let backgroundName = "9183.Custom_Background-810w-1080h@2x~ipad.ca"
            let floatingName = "9183.Custom_Floating-810w-1080h@2x~ipad.ca"
            let background = wallpaper.appendingPathComponent(backgroundName, isDirectory: true)
            let floating = wallpaper.appendingPathComponent(floatingName, isDirectory: true)
            let assets = background.appendingPathComponent("assets", isDirectory: true)
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            try fm.createDirectory(at: floating, withIntermediateDirectories: true)

            try Data("\(identifier)".utf8).write(to: descriptorURL.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"))
            try Data("PRPosterRoleLockScreen".utf8).write(to: descriptorURL.appendingPathComponent("com.apple.posterkit.role.identifier"))
            guard let providerInfo = Data(base64Encoded: providerInfoBase64) else {
                throw AnimatedWallpaperError.installationFailed
            }
            try providerInfo.write(to: descriptorURL.appendingPathComponent("providerInfo.plist"))

            let userInfo: [String: Any] = [
                "posterEnvironmentOverrides": Data("{}".utf8),
                "wallpaperRepresentingFileName": wallpaperName,
                "wallpaperRepresentingIdentifier": identifier
            ]
            try plistData(userInfo).write(to: contents.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo"))

            let wallpaperPlist: [String: Any] = [
                "appearanceAware": true,
                "assets": [
                    "lockAndHome": [
                        "default": [
                            "backgroundAnimationFileName": backgroundName,
                            "floatingAnimationFileNameKey": floatingName,
                            "identifier": identifier,
                            "name": "Lavender",
                            "type": "LayeredAnimation"
                        ]
                    ]
                ],
                "contentVersion": 2.01,
                "family": "Marble",
                "identifier": identifier,
                "logicalScreenClass": "810w-1080h@2x~ipad",
                "name": "Lavender",
                "preferredProminentColor": ["dark": "#000000", "default": "#FFFFFF"],
                "version": 1
            ]
            try plistData(wallpaperPlist).write(to: wallpaper.appendingPathComponent("Wallpaper.plist"))

            let width = max(1, Int(targetSize.width.rounded()))
            let height = max(1, Int(targetSize.height.rounded()))
            try emptyFloatingCAML(width: width, height: height).data(using: .utf8)!.write(to: floating.appendingPathComponent("main.caml"))
            try indexXML(width: width, height: height).data(using: .utf8)!.write(to: floating.appendingPathComponent("index.xml"))

            progress(0.03, LaraL10n.text(en: "Reading video", es: "Leyendo el video"))
            let asset = AVURLAsset(url: video)
            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            guard duration.isFinite, duration > 0 else { throw AnimatedWallpaperError.invalidVideo }
            guard duration <= maximumDuration else { throw AnimatedWallpaperError.videoTooLong }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw AnimatedWallpaperError.invalidVideo
            }

            let nominalFrameRate = try await track.load(.nominalFrameRate)
            let sourceFPS = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
            let requestedFPS = min(30, max(15, sourceFPS))
            let frameCount = min(maximumFrames, max(2, Int(floor(duration * requestedFPS))))
            let effectiveFPS = Double(frameCount) / duration
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: targetSize.width * 1.15, height: targetSize.height * 1.15)

            var frameValues = ""
            for index in 0..<frameCount {
                if isCancelled() { throw AnimatedWallpaperError.cancelled }
                try autoreleasepool {
                    let seconds = min(duration - 0.001, Double(index) / effectiveFPS)
                    let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
                    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                    guard let data = jpegAspectFill(cgImage, size: targetSize) else {
                        throw AnimatedWallpaperError.noFrames
                    }
                    try data.write(to: assets.appendingPathComponent("\(index).jpg"))
                    frameValues += "\t\t\t<CGImage src=\"assets/\(index).jpg\"/>\n"
                }
                progress(
                    Double(index + 1) / Double(frameCount),
                    LaraL10n.text(
                        en: "Processing frame \(index + 1) of \(frameCount)",
                        es: "Procesando cuadro \(index + 1) de \(frameCount)"
                    )
                )
            }

            guard !frameValues.isEmpty else { throw AnimatedWallpaperError.noFrames }
            let animationDuration = Double(frameCount) / effectiveFPS
            let main = animatedCAML(
                width: width,
                height: height,
                duration: animationDuration,
                autoReverses: autoReverses,
                values: frameValues
            )
            try main.data(using: .utf8)!.write(to: background.appendingPathComponent("main.caml"))
            try indexXML(width: width, height: height).data(using: .utf8)!.write(to: background.appendingPathComponent("index.xml"))

            return BuildResult(workingRoot: workingRoot, descriptorURL: descriptorURL)
        } catch {
            try? fm.removeItem(at: workingRoot)
            throw error
        }
    }

    static func build(
        stillImage: UIImage,
        floatingImage: UIImage? = nil,
        name: String,
        targetSize: CGSize
    ) throws -> BuildResult {
        let fm = FileManager.default
        let workingRoot = fm.temporaryDirectory.appendingPathComponent("EagleStill-\(UUID().uuidString)", isDirectory: true)
        let descriptorURL = workingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: descriptorURL, withIntermediateDirectories: true)

        do {
            let identifier = Int.random(in: 100_000...999_999)
            let wallpaperName = "9183.Eagle-810w-1080h@2x~ipad.wallpaper"
            let contents = descriptorURL.appendingPathComponent("versions/1/contents", isDirectory: true)
            let wallpaper = contents.appendingPathComponent(wallpaperName, isDirectory: true)
            let backgroundName = "9183.Eagle_Background-810w-1080h@2x~ipad.ca"
            let floatingName = "9183.Eagle_Floating-810w-1080h@2x~ipad.ca"
            let background = wallpaper.appendingPathComponent(backgroundName, isDirectory: true)
            let floating = wallpaper.appendingPathComponent(floatingName, isDirectory: true)
            let assets = background.appendingPathComponent("assets", isDirectory: true)
            let floatingAssets = floating.appendingPathComponent("assets", isDirectory: true)
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            try fm.createDirectory(at: floating, withIntermediateDirectories: true)

            try Data("\(identifier)".utf8).write(to: descriptorURL.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"))
            try Data("PRPosterRoleLockScreen".utf8).write(to: descriptorURL.appendingPathComponent("com.apple.posterkit.role.identifier"))
            guard let providerInfo = Data(base64Encoded: providerInfoBase64) else {
                throw AnimatedWallpaperError.installationFailed
            }
            try providerInfo.write(to: descriptorURL.appendingPathComponent("providerInfo.plist"))

            let userInfo: [String: Any] = [
                "posterEnvironmentOverrides": Data("{}".utf8),
                "wallpaperRepresentingFileName": wallpaperName,
                "wallpaperRepresentingIdentifier": identifier
            ]
            try plistData(userInfo).write(to: contents.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo"))

            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Eagle Composer" : name
            let wallpaperPlist: [String: Any] = [
                "appearanceAware": true,
                "assets": [
                    "lockAndHome": [
                        "default": [
                            "backgroundAnimationFileName": backgroundName,
                            "floatingAnimationFileNameKey": floatingName,
                            "identifier": identifier,
                            "name": displayName,
                            "type": "LayeredAnimation"
                        ]
                    ]
                ],
                "contentVersion": 2.01,
                "family": "Eagle",
                "identifier": identifier,
                "logicalScreenClass": "810w-1080h@2x~ipad",
                "name": displayName,
                "preferredProminentColor": ["dark": "#000000", "default": "#FFFFFF"],
                "version": 1
            ]
            try plistData(wallpaperPlist).write(to: wallpaper.appendingPathComponent("Wallpaper.plist"))

            let width = max(1, Int(targetSize.width.rounded()))
            let height = max(1, Int(targetSize.height.rounded()))
            if let floatingImage,
               let subject = pngAspectFill(floatingImage, size: targetSize) {
                try fm.createDirectory(at: floatingAssets, withIntermediateDirectories: true)
                try subject.write(to: floatingAssets.appendingPathComponent("subject.png"))
                try depthFloatingCAML(width: width, height: height)
                    .data(using: .utf8)!
                    .write(to: floating.appendingPathComponent("main.caml"))
            } else {
                try emptyFloatingCAML(width: width, height: height)
                    .data(using: .utf8)!
                    .write(to: floating.appendingPathComponent("main.caml"))
            }
            try indexXML(width: width, height: height).data(using: .utf8)!.write(to: floating.appendingPathComponent("index.xml"))

            guard let cgImage = stillImage.cgImage,
                  let frame = jpegAspectFill(cgImage, size: targetSize) else {
                throw AnimatedWallpaperError.noFrames
            }
            try frame.write(to: assets.appendingPathComponent("0.jpg"))
            try frame.write(to: assets.appendingPathComponent("1.jpg"))
            let values = "\t\t\t<CGImage src=\"assets/0.jpg\"/>\n\t\t\t<CGImage src=\"assets/1.jpg\"/>\n"
            let main = animatedCAML(
                width: width,
                height: height,
                duration: 8,
                autoReverses: false,
                values: values
            )
            try main.data(using: .utf8)!.write(to: background.appendingPathComponent("main.caml"))
            try indexXML(width: width, height: height).data(using: .utf8)!.write(to: background.appendingPathComponent("index.xml"))

            return BuildResult(workingRoot: workingRoot, descriptorURL: descriptorURL)
        } catch {
            try? fm.removeItem(at: workingRoot)
            throw error
        }
    }

    private static func plistData(_ object: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    private static func jpegAspectFill(_ image: CGImage, size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            let source = UIImage(cgImage: image)
            let sourceSize = source.size
            let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: 0.72)
    }

    private static func pngAspectFill(_ image: UIImage, size: CGSize) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let sourceSize = image.size
            guard sourceSize.width > 0, sourceSize.height > 0 else { return }
            let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let origin = CGPoint(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.pngData()
    }

    private static func indexXML(width: Int, height: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>assetManifest</key><string>assetManifest.caml</string>
            <key>documentHeight</key><real>\(height)</real>
            <key>documentResizesToView</key><true/>
            <key>documentWidth</key><real>\(width)</real>
            <key>dynamicGuidesEnabled</key><true/>
            <key>geometryFlipped</key><false/>
            <key>guidesEnabled</key><true/>
            <key>interactiveMouseEventsEnabled</key><true/>
            <key>interactiveShowsCursor</key><true/>
            <key>interactiveTouchEventsEnabled</key><false/>
            <key>loopEnd</key><real>0.0</real>
            <key>loopStart</key><real>0.0</real>
            <key>loopingEnabled</key><false/>
            <key>multitouchDisablesMouse</key><false/>
            <key>multitouchEnabled</key><false/>
            <key>presentationMouseEventsEnabled</key><true/>
            <key>presentationShowsCursor</key><true/>
            <key>presentationTouchEventsEnabled</key><false/>
            <key>rootDocument</key><string>main.caml</string>
            <key>savesWindowFrame</key><false/>
            <key>scalesToFitInPlayer</key><true/>
            <key>showsTouches</key><true/>
            <key>snappingEnabled</key><true/>
            <key>timelineMarkers</key><string>[(null)]</string>
            <key>touchesColor</key><string>1 1 0 0.8</string>
            <key>unitsInPixelsInPlayer</key><true/>
        </dict>
        </plist>
        """
    }

    private static func emptyFloatingCAML(width: Int, height: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
          <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_BACKGROUND" position="\(width / 2) \(height / 2)">
            <sublayers>
              <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" anchorPoint="0 0" bounds="0 0 0 0" contentsFormat="RGBA8" cornerCurve="circular" name="_CENTER_BACKGROUND" position="\(width / 2) \(height / 2)"/>
            </sublayers>
            \(stateMarkup)
          </CALayer>
        </caml>
        """
    }

    private static func depthFloatingCAML(width: Int, height: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
          <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_FLOATING" position="\(width / 2) \(height / 2)">
            <sublayers>
              <CATransformLayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Eagle Depth" position="\(width / 2) \(height / 2)">
                <sublayers>
                  <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Eagle Subject" position="\(width / 2) \(height / 2)">
                    <contents type="CGImage" src="assets/subject.png"/>
                  </CALayer>
                </sublayers>
              </CATransformLayer>
            </sublayers>
            \(stateMarkup)
          </CALayer>
        </caml>
        """
    }

    private static func animatedCAML(width: Int, height: Int, duration: Double, autoReverses: Bool, values: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
          <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_FLOATING" position="\(width / 2) \(height / 2)">
            <sublayers>
              <CATransformLayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" allowsHitTesting="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Eagle Motion" position="\(width / 2) \(height / 2)">
                <sublayers>
                  <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Eagle Video" position="\(width / 2) \(height / 2)">
                    <contents type="CGImage" src="assets/0.jpg"/>
                    <animations>
                      <animation type="CAKeyframeAnimation" calculationMode="linear" keyPath="contents" beginTime="1e-100" duration="\(duration)" removedOnCompletion="0" repeatCount="inf" repeatDuration="0" speed="1" timeOffset="0" autoreverses="\(autoReverses ? 1 : 0)">
                        <values>
        \(values)                        </values>
                      </animation>
                    </animations>
                  </CALayer>
                </sublayers>
              </CATransformLayer>
            </sublayers>
            \(stateMarkup)
          </CALayer>
        </caml>
        """
    }

    private static let stateMarkup = """
    <states>
      <LKState name="Locked"><elements/></LKState>
      <LKState name="Unlock"><elements/></LKState>
      <LKState name="Sleep"><elements/></LKState>
    </states>
    <stateTransitions>
      <LKStateTransition fromState="*" toState="Unlock"><elements/></LKStateTransition>
      <LKStateTransition fromState="Unlock" toState="*"><elements/></LKStateTransition>
      <LKStateTransition fromState="*" toState="Locked"><elements/></LKStateTransition>
      <LKStateTransition fromState="Locked" toState="*"><elements/></LKStateTransition>
      <LKStateTransition fromState="*" toState="Sleep"><elements/></LKStateTransition>
      <LKStateTransition fromState="Sleep" toState="*"><elements/></LKStateTransition>
    </stateTransitions>
    """

    private static let providerInfoBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwVFhogVSRudWxs0w0ODxASFFdOUy5rZXlzWk5TLm9iamVjdHNWJGNsYXNzoRGAAqETgAOABV8QHGtDb25maWd1cmF0aW9uTGFzdFVzZURhdGVLZXnSFw8YGVdOUy50aW1lI0HGwARI1HUUgATSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzVk5TRGF0ZaIdH1hOU09iamVjdNIbHCEiXxATTlNNdXRhYmxlRGljdGlvbmFyeaMjJB9fEBNOU011dGFibGVEaWN0aW9uYXJ5XE5TRGljdGlvbmFyeQAIABEAGgAkACkAMgA3AEkATABRAFMAWgBgAGcAbwB6AIEAgwCFAIcAiQCLAKoArwC3AMAAwgDHANIA2wDiAOUA7gDzAQkBDQEjAAAAAAAAAgEAAAAAAAAAJQAAAAAAAAAAAAAAAAAAATA="
}
