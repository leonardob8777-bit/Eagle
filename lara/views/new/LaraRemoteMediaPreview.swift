import SwiftUI

typealias LaraRemoteMediaPreview = EagleRemoteMediaPreview<EagleRainbowSpinner, EagleGalleryPresentationMotion>

extension EnvironmentValues {
    var laraMediaPreviewsEnabled: Bool {
        get { eagleMediaPreviewsEnabled }
        set { eagleMediaPreviewsEnabled = newValue }
    }
}

extension EagleRemoteMediaPreview where LoadingIndicator == EagleRainbowSpinner, ImageMotion == EagleGalleryPresentationMotion {
    init(
        url: URL?,
        animated: Bool = false,
        contentMode: ContentMode = .fill,
        showsRetry: Bool = true,
        compactPlaceholder: Bool = false,
        background: Color = Color(uiColor: .tertiarySystemFill),
        presentationMotion: Bool = false,
        onReady: ((Bool) -> Void)? = nil
    ) {
        self.init(
            url: url,
            animated: animated,
            contentMode: contentMode,
            showsRetry: showsRetry,
            compactPlaceholder: compactPlaceholder,
            background: background,
            presentationMotion: presentationMotion,
            onReady: onReady,
            loadingIndicator: { EagleRainbowSpinner(size: 22) },
            imageMotion: { EagleGalleryPresentationMotion(active: $0) },
            localizedText: { en, es in LaraL10n.text(en: en, es: es) }
        )
    }
}
