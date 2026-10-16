import Foundation

/// Restores persisted selection without accessing native execution or storage directly.
@MainActor
enum EagleIslandGalleryRecovery {
    static func restore<Style: RawRepresentable>(
        readSelectedRaw: () -> Int,
        writeSelectedRaw: (Int) -> Void,
        readSelectedID: () -> String,
        writeSelectedID: (String) -> Void,
        styleForRaw: (Int) -> Style?,
        isAvailable: (Style) -> Bool,
        defaultStyle: () -> Style,
        remoteStyle: () -> Style,
        artworkID: (Style) -> String,
        readActiveFlags: () -> Int,
        readActiveMode: () -> Int,
        readActiveLiveID: () -> String,
        activeArtworkID: () -> String?
    ) where Style.RawValue == Int {
        if let oldStyle = styleForRaw(readSelectedRaw()),
           !isAvailable(oldStyle) {
            writeSelectedRaw(defaultStyle().rawValue)
            if readSelectedID() == artworkID(oldStyle) {
                writeSelectedID("")
            }
        }
        guard readSelectedID().isEmpty else { return }
        if (readActiveFlags() & 1) != 0 && readActiveMode() == remoteStyle().rawValue {
            // Remote identity must survive before the catalog has arrived.
            writeSelectedID(readActiveLiveID())
        } else if let active = activeArtworkID() { writeSelectedID(active) }
        else {
            let style = styleForRaw(readSelectedRaw()) ?? defaultStyle()
            writeSelectedID(artworkID(style))
        }
    }
}
