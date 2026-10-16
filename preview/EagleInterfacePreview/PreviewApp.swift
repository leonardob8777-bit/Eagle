import SwiftUI
import UIKit

@main
@MainActor
struct EagleInterfacePreviewApp: App {
    @StateObject private var model = EagleInterfacePreviewModel()

    var body: some Scene {
        WindowGroup {
            EaglePreviewRoot(model: model)
                .preferredColorScheme(model.preferredColorScheme)
        }
    }
}

private enum PreviewScreen: String {
    case home, gallery, tests
}

private struct EaglePreviewRoot: View {
    @ObservedObject var model: EagleInterfacePreviewModel
    @State private var selectedScreen: PreviewScreen
    @State private var started = false
    @State private var playbackPaused = false

    init(model: EagleInterfacePreviewModel) {
        self.model = model
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--screen=") }
        let value = argument.map { String($0.dropFirst("--screen=".count)) } ?? "home"
        _selectedScreen = State(initialValue: PreviewScreen(rawValue: value) ?? .home)
    }

    var body: some View {
        TabView(selection: $selectedScreen) {
            NavigationStack {
                PreviewHome(model: model)
            }
            .tabItem { Label(model.t(en: "Home", es: "Inicio"), systemImage: "house.fill") }
            .tag(PreviewScreen.home)

            NavigationStack {
                PreviewGallery(model: model, playbackPaused: $playbackPaused)
            }
            .tabItem { Label(model.t(en: "Gallery", es: "Galería"), systemImage: "square.grid.2x2.fill") }
            .tag(PreviewScreen.gallery)

            NavigationStack {
                PreviewTests(model: model, playbackPaused: $playbackPaused)
            }
            .tabItem { Label(model.t(en: "Tests", es: "Pruebas"), systemImage: "slider.horizontal.3") }
            .tag(PreviewScreen.tests)
        }
        .tint(.primary)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.shield")
                Text(model.t(en: "Interface only · does not change the system",
                             es: "Solo interfaz · no modifica el sistema"))
                    .multilineTextAlignment(.center)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
            .accessibilityIdentifier("preview.scope")
        }
        .background(EagleNotificationInstaller().frame(width: 0, height: 0).allowsHitTesting(false))
        .task {
            guard !started else { return }
            started = true
            await model.initialLoad()
            if ProcessInfo.processInfo.arguments.contains("--qa") {
                await model.runQA()
            }
        }
    }
}

private struct PreviewHome: View {
    @ObservedObject var model: EagleInterfacePreviewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image("EagleBrandMark")
                        .resizable().renderingMode(.template).scaledToFit()
                        .frame(width: 54, height: 54)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EAGLE").font(.system(size: 38, weight: .bold, design: .serif))
                        Text("PREVIEW").font(.caption.weight(.semibold)).tracking(4)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.title2).foregroundStyle(.secondary)
                }
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 10) {
                    Text(model.t(en: "Eagle, up close.", es: "Eagle, de cerca."))
                        .font(.largeTitle.weight(.bold))
                    Text(model.t(
                        en: "A separate space to try the interface, local previews and original notifications.",
                        es: "Un espacio separado para probar la interfaz, vistas previas locales y notificaciones originales."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                preparationCard

                HStack(spacing: 12) {
                    capability("wifi.slash", model.t(en: "Offline", es: "Sin red"))
                    capability("iphone", model.t(en: "App only", es: "Solo app"))
                    capability("checkmark.shield", model.t(en: "Separate", es: "Separada"))
                }

                PreviewSettings(model: model)

                Text(model.t(
                    en: "This demo does not prepare device access or modify the iPhone Dock or Dynamic Island. It is separate from your installed Eagle.",
                    es: "Esta demo no prepara acceso al dispositivo ni modifica el Dock o la isla del iPhone. Está separada de tu Eagle instalado."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarHidden(true)
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: model.demoState == .ready ? "checkmark.shield.fill" : "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 48, height: 48)
                    .background(Color.green.opacity(0.11), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t(en: "Local preparation demo", es: "Demo de preparación local"))
                        .font(.headline)
                    Text(preparationStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if model.demoState == .preparing {
                    EagleRainbowSpinner(size: 22)
                }
            }

            Group {
                if model.demoState == .preparing {
                    EagleRainbowProgressBar(value: model.progress)
                } else {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 6)
                }
            }
            .frame(height: 8)

            Button {
                Task { await model.runPreparationDemo() }
            } label: {
                Label(preparationButton, systemImage: model.demoState == .ready ? "arrow.clockwise" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(Color.black)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 18))
                    .opacity(model.demoState == .preparing ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(model.demoState == .preparing)
            .accessibilityIdentifier("home.prepare")
        }
        .padding(20)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 28))
    }

    private var preparationStatus: String {
        switch model.demoState {
        case .idle: return model.t(en: "Visual simulation · no device access", es: "Simulación visual · sin acceso al dispositivo")
        case .preparing: return model.t(en: "Preparing the visual demo…", es: "Preparando la demo visual…")
        case .ready: return model.t(en: "Demo ready · interface only", es: "Demo lista · solo interfaz")
        }
    }

    private var preparationButton: String {
        switch model.demoState {
        case .idle: return model.t(en: "Try preparation", es: "Probar preparación")
        case .preparing: return model.t(en: "Preparing demo…", es: "Preparando demo…")
        case .ready: return model.t(en: "Try again", es: "Volver a probar")
        }
    }

    private func capability(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PreviewSettings: View {
    @ObservedObject var model: EagleInterfacePreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.t(en: "Your view", es: "Tu presentación"), systemImage: "circle.lefthalf.filled")
                .font(.headline)
            Picker(model.t(en: "Language", es: "Idioma"), selection: $model.language) {
                Text("Español").tag("es")
                Text("English").tag("en")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.language")

            Picker(model.t(en: "Appearance", es: "Apariencia"), selection: $model.appearance) {
                Text(model.t(en: "System", es: "Sistema")).tag("system")
                Text(model.t(en: "Light", es: "Claro")).tag("light")
                Text(model.t(en: "Dark", es: "Oscuro")).tag("dark")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")
        }
        .padding(18)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct PreviewGallery: View {
    @ObservedObject var model: EagleInterfacePreviewModel
    @Binding var playbackPaused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker(model.t(en: "Preview target", es: "Presentación"), selection: $model.selectedTarget) {
                    Text("Dock").tag(PreviewTarget.dock)
                    Text(model.t(en: "Island", es: "Isla")).tag(PreviewTarget.island)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("gallery.target")

                TimelineView(.animation(minimumInterval: 1.0 / 12.0,
                                        paused: playbackPaused || reduceMotion || scenePhase != .active)) { context in
                    PreviewStage(model: model, date: context.date)
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentTitle).font(.title2.weight(.bold))
                        Text(model.t(en: "Presentation inside this app", es: "Presentación dentro de esta app"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let theme = model.currentTheme {
                        Button { model.toggleSaved(id: theme.id) } label: {
                            Image(systemName: model.saved.contains(theme.id) ? "heart.fill" : "heart")
                                .font(.title3).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.t(en: "Save preview", es: "Guardar vista previa"))
                    }
                }

                PreviewGalleryFilter(model: model)

                if model.visibleThemes.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: model.filter == .saved ? "heart" : "square.grid.2x2")
                            .font(.title2)
                        Text(model.t(en: "No previews in this filter.", es: "No hay vistas previas en este filtro."))
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(model.visibleThemes) { theme in
                            PreviewThemeCard(model: model, theme: theme)
                        }
                    }
                }

                positionControls

                Button {
                    Task { await model.prepareSelectedTheme() }
                } label: {
                    HStack(spacing: 9) {
                        if model.busy { ProgressView().tint(Color(uiColor: .systemBackground)) }
                        else { Image(systemName: "play.rectangle") }
                        Text(model.t(en: "Prepare preview", es: "Preparar vista previa"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
                    .opacity(model.busy || model.currentTheme == nil ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(model.busy || model.currentTheme == nil)
                .accessibilityIdentifier("gallery.prepare")

                if !model.status.isEmpty {
                    Label(model.status, systemImage: model.frameURLs.isEmpty ? "info.circle" : "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup(model.t(en: "6 built-in Eagle designs", es: "6 diseños integrados de Eagle")) {
                    VStack(spacing: 12) {
                        ForEach(EagleDockGalleryBuiltInTheme.allCases) { theme in
                            HStack {
                                let color = theme.accentComponents
                                Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                                    .frame(width: 12, height: 12)
                                Text(model.t(en: theme.titleText.en, es: theme.titleText.es)).font(.subheadline)
                                Spacer()
                                Text("#\(theme.id)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 14)
                }
                .font(.subheadline.weight(.medium))

                Text(model.t(
                    en: "Local example packages are validated by Eagle’s file pipeline. Nothing is applied outside this app.",
                    es: "Los paquetes locales de ejemplo pasan por la validación de archivos de Eagle. No se aplica nada fuera de esta app."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(model.t(en: "Gallery Preview", es: "Galería Preview"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentTitle: String {
        guard let theme = model.currentTheme else { return model.t(en: "Local collection", es: "Colección local") }
        return model.t(en: theme.title, es: theme.titleES)
    }

    private var positionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.t(en: "Preview position", es: "Posición de la vista previa")).font(.headline)
                Spacer()
                Text("0.5 pt").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button { model.resetPreview() } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 40, height: 40)
                }
                .buttonStyle(.plain).disabled(model.busy)
                .accessibilityLabel(model.t(en: "Reset preview", es: "Restablecer vista previa"))
            }
            HStack(spacing: 10) {
                direction("arrow.left", en: "Move left", es: "Mover a la izquierda", dx: -0.5, dy: 0, id: "left")
                direction("arrow.up", en: "Move up", es: "Mover arriba", dx: 0, dy: -0.5, id: "up")
                direction("arrow.down", en: "Move down", es: "Mover abajo", dx: 0, dy: 0.5, id: "down")
                direction("arrow.right", en: "Move right", es: "Mover a la derecha", dx: 0.5, dy: 0, id: "right")
            }
            Text(String(format: "X %.1f · Y %.1f", Double(model.positionX), Double(model.positionY)))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("gallery.position")
        }
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
    }

    private func direction(_ symbol: String, en: String, es: String,
                           dx: CGFloat, dy: CGFloat, id: String) -> some View {
        Button { model.move(dx: dx, dy: dy) } label: {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.t(en: en, es: es))
        .accessibilityIdentifier("gallery.move.\(id)")
    }
}

private struct PreviewGalleryFilter: View {
    @ObservedObject var model: EagleInterfacePreviewModel

    var body: some View {
        Picker(model.t(en: "Theme filter", es: "Filtro de temas"), selection: $model.filter) {
            Text(model.t(en: "All", es: "Todo")).tag(PreviewFilter.all)
            Text("Live").tag(PreviewFilter.live)
            Text(model.t(en: "Static", es: "Estático")).tag(PreviewFilter.still)
            Text(model.t(en: "Saved", es: "Guardado")).tag(PreviewFilter.saved)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("gallery.filter")
    }
}

private struct PreviewThemeCard: View {
    @ObservedObject var model: EagleInterfacePreviewModel
    let theme: EagleDockGalleryTheme

    var body: some View {
        Button { model.selectTheme(id: theme.id) } label: {
            VStack(alignment: .leading, spacing: 11) {
                ZStack(alignment: .topLeading) {
                    PreviewLocalImage(url: model.previewURL(for: theme))
                        .aspectRatio(1146.0 / 318.0, contentMode: .fit)
                        .clipShape(Capsule())
                        .padding(.horizontal, 13).padding(.vertical, 33)
                    Text(theme.frameCount > 1 ? "LIVE" : model.t(en: "STATIC", es: "ESTÁTICO"))
                        .font(.system(size: 9, weight: .semibold)).tracking(1)
                        .foregroundStyle(.secondary).padding(12)
                }
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                Text(model.t(en: theme.title, es: theme.titleES))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(model.selectedThemeID == theme.id ? 0.8 : 0), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityIdentifier("gallery.theme.\(theme.id)")
        .accessibilityLabel(model.t(en: theme.title, es: theme.titleES))
        .accessibilityAddTraits(model.selectedThemeID == theme.id ? .isSelected : [])
    }
}

private struct PreviewStage: View {
    @ObservedObject var model: EagleInterfacePreviewModel
    let date: Date

    var body: some View {
        VStack(spacing: 20) {
            if model.selectedTarget == .island {
                HStack(spacing: 12) {
                    Text("9:41").font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    surface
                        .frame(width: 152, height: 44)
                        .clipShape(Capsule())
                        .offset(x: model.positionX, y: model.positionY)
                    Spacer(minLength: 0)
                    statusIcons
                }
                .frame(height: 92)
            } else {
                HStack {
                    Text("9:41").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    statusIcons
                }
                surface
                    .aspectRatio(1146.0 / 318.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .offset(x: model.positionX, y: model.positionY)
                    .padding(.horizontal, 5)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.selectedTarget == .dock
                            ? model.t(en: "Dock preview inside the app", es: "Dock de presentación dentro de la app")
                            : model.t(en: "Island preview inside the app", es: "Isla de presentación dentro de la app"))
        .accessibilityIdentifier("gallery.preview")
    }

    private var surface: some View {
        PreviewLocalImage(url: model.currentFrame(at: date))
            .animation(.easeInOut(duration: 0.18), value: model.selectedThemeID)
            .animation(.easeOut(duration: 0.16), value: model.positionX)
            .animation(.easeOut(duration: 0.16), value: model.positionY)
    }

    private var statusIcons: some View {
        HStack(spacing: 5) {
            Image(systemName: "cellularbars")
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
        }
        .font(.system(size: 10, weight: .semibold))
        .accessibilityHidden(true)
    }
}

@MainActor
private enum PreviewImageCache {
    static let images: NSCache<NSURL, UIImage> = {
        let result = NSCache<NSURL, UIImage>()
        result.countLimit = 24
        return result
    }()

    static func image(at url: URL?) -> UIImage? {
        guard let url, url.isFileURL else { return nil }
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
}

private struct PreviewLocalImage: View {
    let url: URL?

    var body: some View {
        Group {
            if let image = PreviewImageCache.image(at: url) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .clipped()
    }
}

private struct PreviewTests: View {
    @ObservedObject var model: EagleInterfacePreviewModel
    @Binding var playbackPaused: Bool
    @State private var repeated = 0
    @State private var licenseText = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t(en: "Try every gesture.", es: "Prueba cada gesto."))
                        .font(.title.weight(.bold))
                    Text(model.t(
                        en: "These are Eagle’s original app-window notifications. Tap, hold and drag the card to compare the behavior.",
                        es: "Son las notificaciones originales de Eagle dentro de la app. Toca, mantén y arrastra la tarjeta para comparar su comportamiento."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(model.t(en: "Notification result", es: "Resultado del aviso")).font(.headline)
                    HStack(spacing: 10) {
                        noticeButton(.success, symbol: "checkmark.circle.fill", en: "Success", es: "Éxito", id: "tests.success")
                        noticeButton(.error, symbol: "exclamationmark.circle.fill", en: "Error", es: "Error", id: "tests.error")
                        noticeButton(.information, symbol: "info.circle.fill", en: "Info", es: "Info", id: "tests.info")
                    }
                    Button {
                        repeated += 1
                        EagleNotifications.shared.result(repeated.isMultiple(of: 2),
                            title: "Eagle Preview · \(repeated)",
                            message: model.t(en: "Repeated UI-only notice.", es: "Aviso repetido de prueba visual."))
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(model.t(en: "Repeat immediately", es: "Repetir inmediatamente")).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(repeated)").font(.subheadline.monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tests.repeat")
                    Button {
                        EagleNotifications.shared.dismiss()
                    } label: {
                        Label(model.t(en: "Dismiss notice", es: "Cerrar aviso"), systemImage: "xmark")
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tests.dismiss")
                }
                .padding(18)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))

                PreviewSettings(model: model)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(model.t(en: "Pause animated previews", es: "Pausar vistas previas animadas"), isOn: $playbackPaused)
                        .tint(.primary)
                    Text(model.t(en: "Playback also pauses when this app is not active.",
                                 es: "El movimiento también se pausa cuando esta app no está activa."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        model.appearance = colorScheme == .dark ? "light" : "dark"
                    } label: {
                        Label(model.t(en: "Compare light / dark background", es: "Comparar fondo claro / oscuro"),
                              systemImage: "circle.lefthalf.filled")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tests.background")
                }
                .padding(18)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))

                if let result = model.qaResult {
                    Label("QA · \(result)", systemImage: result == "PASS" ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption.monospaced()).foregroundStyle(result == "PASS" ? Color.green : Color.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t(en: "About this preview", es: "Acerca de esta prueba")).font(.headline)
                    Text(model.t(
                        en: "A separate Eagle preview with local examples. Original interface origins: Eagle / Lara. Notification inspiration: expo-dynamic-notifications by rit3zh. License notices are included.",
                        es: "Una vista previa separada de Eagle con ejemplos locales. Origen de la interfaz: Eagle / Lara. Inspiración de avisos: expo-dynamic-notifications de rit3zh. Se incluyen avisos de licencia."))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.t(
                        en: "Provided without warranty. Corresponding sources are supplied with the IPA.",
                        es: "Se distribuye sin garantía. Las fuentes correspondientes se entregan junto a la IPA."))
                        .font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup(model.t(en: "Read license notices", es: "Leer avisos de licencia")) {
                        ScrollView {
                            Text(licenseText)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                        .frame(height: 280)
                        .onAppear {
                            guard licenseText.isEmpty else { return }
                            licenseText = ["LICENSE.txt", "NOTICE_Dynamic_Notifications.txt"].compactMap { name in
                                guard let url = Bundle.main.url(forResource: name, withExtension: nil,
                                                                subdirectory: "PreviewResources/Licenses") else { return nil }
                                return try? String(contentsOf: url, encoding: .utf8)
                            }.joined(separator: "\n\n")
                            if licenseText.isEmpty {
                                licenseText = model.t(en: "See the license files in the supplied Sources.zip.",
                                                      es: "Consulta las licencias del Sources.zip entregado.")
                            }
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(model.t(en: "Interface tests", es: "Pruebas de interfaz"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func noticeButton(_ kind: EagleNoticeKind, symbol: String, en: String, es: String, id: String) -> some View {
        Button {
            EagleNotifications.shared.show(title: "Eagle Preview",
                message: model.t(en: "A visual test only. No system changes.", es: "Solo una prueba visual. Sin cambios del sistema."),
                kind: kind)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(kind.color).font(.title2)
                Text(model.t(en: en, es: es)).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
