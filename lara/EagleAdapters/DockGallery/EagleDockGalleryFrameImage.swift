import Foundation
import UIKit

/// Interprets frame images at Eagle's UIKit boundary, outside Foundation Core.
/// Decoding, pixel projections and failure behavior retain the public rules.
@MainActor
enum EagleDockGalleryFrameImage {
    static func validate(_ data: Data, theme: EagleDockGalleryTheme) throws {
        guard let image = UIImage(data: data), matches(image, theme: theme) else {
            throw URLError(.cannotDecodeContentData)
        }
    }

    static func isValid(_ data: Data, theme: EagleDockGalleryTheme) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        return matches(image, theme: theme)
    }

    static func matches(_ image: UIImage, theme: EagleDockGalleryTheme) -> Bool {
        EagleDockGalleryFrameDimensions.matches(
            width: image.cgImage?.width,
            height: image.cgImage?.height,
            expectedWidth: theme.width,
            expectedHeight: theme.height
        )
    }
}
