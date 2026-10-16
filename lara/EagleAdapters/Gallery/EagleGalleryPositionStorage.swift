import Foundation

extension EagleGalleryPosition {
    nonisolated static func saved(_ surface: String) -> Self {
        Self(
            x: UserDefaults.standard.double(
                forKey: "eagle.\(surface)Gallery.positionX"
            ),
            y: UserDefaults.standard.double(
                forKey: "eagle.\(surface)Gallery.positionY"
            )
        )
    }
}
