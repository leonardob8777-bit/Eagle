import SwiftUI

struct PasscodeRepoView: View {
    @ObservedObject private var gallery = PasscodeGalleryManager.shared

    var body: some View {
        List {
            Section {
                Label("Eagle Gallery", systemImage: "lock.square")
                if let error = gallery.loadError {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    Text(LaraL10n.text(
                        en: "Passcode styles are published by Eagle.",
                        es: "Eagle publica los estilos del código."
                    ))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(LaraL10n.text(en: "Passcode catalog", es: "Catálogo del código"))
        .refreshable { await gallery.loadThemes(forceRefresh: true) }
    }
}
