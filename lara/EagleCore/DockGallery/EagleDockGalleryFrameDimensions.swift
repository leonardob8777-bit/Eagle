/// The public frame-dimension equality rule, independent of image decoding.
/// Keep height reads lazy so a failed width check retains its short circuit.
nonisolated enum EagleDockGalleryFrameDimensions {
    static func matches(
        width: Int?,
        height: @autoclosure () -> Int?,
        expectedWidth: Int,
        expectedHeight: @autoclosure () -> Int
    ) -> Bool {
        width == expectedWidth && height() == expectedHeight()
    }
}
