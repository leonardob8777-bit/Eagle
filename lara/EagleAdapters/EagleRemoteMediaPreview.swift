import SwiftUI
import WebKit
import Combine

private struct EagleMediaPreviewsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var eagleMediaPreviewsEnabled: Bool {
        get { self[EagleMediaPreviewsEnabledKey.self] }
        set { self[EagleMediaPreviewsEnabledKey.self] = newValue }
    }
}

struct EagleRemoteMediaPreview<LoadingIndicator: View, ImageMotion: ViewModifier>: View {
    let url: URL?
    var animated = false
    var contentMode: ContentMode = .fill
    var showsRetry = true
    var compactPlaceholder = false
    var background = Color(uiColor: .tertiarySystemFill)
    var presentationMotion = false
    var onReady: ((Bool) -> Void)? = nil

    let loadingIndicator: () -> LoadingIndicator
    let imageMotion: (Bool) -> ImageMotion
    let localizedText: (String, String) -> String

    @StateObject private var loader = EagleRemoteMediaLoader()
    @State private var retryID = 0
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.eagleMediaPreviewsEnabled) private var previewsEnabled

    private var shouldLoad: Bool { visible && previewsEnabled && scenePhase == .active }

    var body: some View {
        ZStack {
            background

            if url != nil {
                switch loader.state {
                case .loading:
                    loadingView
                case .loaded(let data, let mimeType, let contentID):
                    loadedView(data: data, mimeType: mimeType, contentID: contentID)
                case .failed:
                    unavailableView
                }
            } else {
                unavailableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.26), value: previewPhase)
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            loader.release()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            EagleRemoteMediaLoader.clearCache()
            if !shouldLoad { loader.release() }
        }
        .task(id: "\(url?.absoluteString ?? "missing")-\(retryID)-\(shouldLoad)") {
            guard shouldLoad else {
                loader.release()
                return
            }
            guard let url else {
                onReady?(false)
                return
            }
            onReady?(false)
            await loader.load(url, forceRefresh: retryID > 0)
            guard !Task.isCancelled else { return }
            if case .loaded = loader.state {
                onReady?(true)
            } else {
                onReady?(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func loadedView(data: Data, mimeType: String, contentID: UUID) -> some View {
        if animated && shouldLoad && !reduceMotion {
            EagleAnimatedMediaView(
                data: data,
                mimeType: mimeType,
                contentMode: contentMode,
                contentID: contentID
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        } else if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .modifier(imageMotion(presentationMotion && shouldLoad))
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
        } else {
            unavailableView
        }
    }

    private var previewPhase: Int {
        switch loader.state {
        case .loading: return 0
        case .loaded: return 1
        case .failed: return 2
        }
    }

    private var loadingView: some View {
        VStack(spacing: 9) {
            loadingIndicator()
            if !compactPlaceholder {
                Text(localizedText("Loading preview…", "Cargando vista previa…"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 9) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            if !compactPlaceholder {
                Text(localizedText("Preview unavailable", "Vista previa no disponible"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            if showsRetry, url != nil {
                Button(localizedText("Try again", "Intentar de nuevo")) {
                    retryID += 1
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .multilineTextAlignment(.center)
        .padding(12)
    }
}

private struct EagleAnimatedMediaView: UIViewRepresentable {
    let data: Data
    let mimeType: String
    let contentMode: ContentMode
    let contentID: UUID

    final class Coordinator {
        var contentID: UUID?
        var mimeType = ""
        var fill = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.isUserInteractionEnabled = false
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        coordinator.contentID = nil
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let fill = contentMode == .fill
        guard context.coordinator.contentID != contentID ||
                context.coordinator.mimeType != mimeType ||
                context.coordinator.fill != fill else { return }
        context.coordinator.contentID = contentID
        context.coordinator.mimeType = mimeType
        context.coordinator.fill = fill

        let encoded = data.base64EncodedString()
        let objectFit = fill ? "cover" : "contain"
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>*{margin:0;padding:0}html,body{width:100%;height:100%;overflow:hidden;background:transparent}img{width:100%;height:100%;object-fit:\(objectFit)}</style>
        </head><body><img src="data:\(mimeType);base64,\(encoded)"></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
