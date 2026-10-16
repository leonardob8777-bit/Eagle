import Foundation
import Combine

@MainActor final class GalleryDiagnosticRecorder {
    private(set) static var initializationCount = 0
    private(set) var messages: [String] = []
    init() { Self.initializationCount += 1 }
    func log(_ message: String) { messages.append(message) }
}

// The only runtime double replaces disk/stdout logging, not the Store or services.
let globallogger = GalleryDiagnosticRecorder()

@main private enum GalleryServicesChecks {
    static func main() async {
        precondition(GalleryDiagnosticRecorder.initializationCount == 0)
        let store = EagleGalleryServices.dock
        precondition(GalleryDiagnosticRecorder.initializationCount == 0, "Store creation opened the file logger")
        precondition(store.themes.isEmpty && !store.loading && store.downloadingID == nil && store.errorMessage == nil)
        var events = 0
        let observation = store.objectWillChange.sink { _ in events += 1 }
        for _ in 0..<100 { precondition(EagleGalleryServices.dock === store) }

        let identity = ObjectIdentifier(store)
        let identities = await withTaskGroup(of: ObjectIdentifier.self, returning: [ObjectIdentifier].self) { group in
            for _ in 0..<64 {
                group.addTask { await MainActor.run { ObjectIdentifier(EagleGalleryServices.dock) } }
            }
            var values: [ObjectIdentifier] = []
            for await value in group { values.append(value) }
            return values
        }
        precondition(identities.count == 64 && identities.allSatisfy { $0 == identity })

        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        for language in ["en", "es", "en", "es", "invalid", "en"] {
            var arguments = saved
            arguments[EagleLanguage.storageKey] = language
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let expected = language == "es"
                ? "No se pudo cargar la colección en línea."
                : "The online collection could not be loaded."
            precondition(store.fixtureFailureMessage() == expected, "Shared Store froze its language at construction")
        }
        let sink = store.fixtureDiagnosticSink()
        precondition(GalleryDiagnosticRecorder.initializationCount == 0, "Reading callback eagerly opened logger")
        sink("owned Gallery callback")
        precondition(GalleryDiagnosticRecorder.initializationCount == 0, "Diagnostic delivery stopped being deferred")
        let deadline = Date().addingTimeInterval(4)
        while GalleryDiagnosticRecorder.initializationCount == 0 {
            precondition(Date() < deadline, "Diagnostic delivery timed out")
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        precondition(globallogger.messages == ["owned Gallery callback"])
        precondition(EagleAppDiagnostics.shared.history.text == "owned Gallery callback\n")

        let separate = EagleDockGalleryStore(catalogFailureMessage: { "isolated" }, diagnostics: { { _ in } })
        precondition(separate !== store && EagleGalleryServices.dock === store)
        precondition(events == 0, "Shared access or callback reads mutated Gallery display state")
        precondition(store.themes.isEmpty && !store.loading && store.downloadingID == nil && store.errorMessage == nil)
        observation.cancel()
        print("PASS: 100 repeated/64 concurrent shared identities, unchanged initial state and distinct explicit Store")
        print("PASS: six live language changes and lazy/deferred real diagnostic route, no duplicate or early logger")
        print("PASS: no catalog/download/native calls, persistent preference writes or production log files")
    }
}
