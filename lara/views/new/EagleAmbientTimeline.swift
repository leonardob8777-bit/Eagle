import SwiftUI

/// A `TimelineView` for ambient motion (auroras, sheens, slow drifts). It draws at most 60 frames a
/// second, half of what a ProMotion screen would ask for and plenty for slow motion, and it pauses
/// while off screen (another screen pushed on top, another tab), as well as when `paused` is true.
/// Same look, less battery and heat.
struct EagleAmbientTimeline<Content: View>: View {
    var minimumInterval: Double = 1.0 / 60.0
    var paused = false
    @ViewBuilder let content: (TimelineViewDefaultContext) -> Content

    @State private var onScreen = false

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumInterval, paused: paused || !onScreen)) { context in
            content(context)
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}
