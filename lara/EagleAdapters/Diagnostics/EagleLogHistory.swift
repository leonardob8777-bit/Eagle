import Combine

/// In-memory history only. Delivery queues and file logging belong to callers.
@MainActor
final class EagleLogHistory: ObservableObject {
    @Published var text: String = ""

    func append(_ message: String) {
        text += message + "\n"
        if text.utf8.count > 256 * 1024 { text = String(text.suffix(128 * 1024)) }
    }
}
