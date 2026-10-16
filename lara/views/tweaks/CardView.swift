//
//  CardView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum replaceoption: String, CaseIterable, Identifiable {
    case photos = "Fotos"
    case files = "Archivos"
    
    var id: String { self.rawValue }
}

struct CardView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var cards: [carditem] = []
    @State private var status: String?
    @State private var working = false
    @State private var showimgpicker = false
    @State private var showdocpicker = false
    @State private var pendingcard: carditem?
    @State private var pickedimgdata: Data?
    @State private var shownumbereditor = false
    @State private var cardnuminput = ""
    @State private var currentcardnum = ""
    @State private var pendingnumcard: carditem?
    @State private var pendingrestorecard: carditem?
    @State private var promptforrespring = false

    private static let cardfiles = [
        "cardBackground@2x.png",
        "cardBackgroundCombined@2x.png",
        "cardBackgroundCombined-watch@2x.png"
    ]

    private struct carditem: Identifiable {
        let id: String
        let imgpath: String
        let dirpath: String
        let bundlename: String
        let bgfilename: String
    }

    private struct cardrow: View {
        let card: carditem
        let onreplace: (carditem, replaceoption) -> Void
        let onrestore: (carditem) -> Void
        let oneditnum: (carditem) -> Void
        let previewimg: (carditem) -> UIImage?

        var body: some View {
            let preview = previewimg(card)
            VStack(alignment: .leading, spacing: 16) {
                CardPreview(image: preview)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Tarjeta de Wallet")
                            .font(.headline)
                        Spacer(minLength: 8)
                        CardBadge(text: "Wallet", systemImage: "wallet.pass")
                    }
                    Text("Lista para personalizar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Menu {
                        Button {
                            onreplace(card, .photos)
                        } label: {
                            Label("Elegir de Fotos", systemImage: "photo.on.rectangle")
                        }

                        Button {
                            onreplace(card, .files)
                        } label: {
                            Label("Elegir de Archivos", systemImage: "folder")
                        }
                    } label: {
                        Label("Cambiar diseño", systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(CardProminentButtonStyle())

                    Menu {
                        Button {
                            oneditnum(card)
                        } label: {
                            Label("Editar terminación", systemImage: "number")
                        }

                        Button(role: .destructive) {
                            onrestore(card)
                        } label: {
                            Label("Restaurar original", systemImage: "arrow.uturn.backward")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(CardSecondaryButtonStyle())
                    .accessibilityLabel("Más opciones")
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }

    // Preview de la tarjeta con un brillo especular sutil que la recorre y
    // "respira", como la luz sobre una tarjeta física. Solo presentación.
    private struct CardPreview: View {
        let image: UIImage?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(uiColor: .tertiarySystemFill)
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.586, contentMode: .fit)
            .overlay { sheen }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
            }
        }

        @ViewBuilder private var sheen: some View {
            if image != nil {
                EagleAmbientTimeline(paused: reduceMotion) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let sweep = 6.5
                    let breath = 5.0
                    let phase = (t.truncatingRemainder(dividingBy: sweep)) / sweep
                    let p = phase * 1.4 - 0.2
                    let lo = min(max(p - 0.16, 0), 1)
                    let mid = min(max(p, 0), 1)
                    let hi = min(max(p + 0.16, 0), 1)
                    let breathPhase = (t.truncatingRemainder(dividingBy: breath)) / breath
                    let breathe = 0.5 + 0.5 * sin(breathPhase * 2 * .pi)
                    let peak = reduceMotion ? 0.0 : (0.07 + 0.06 * breathe)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: lo),
                            .init(color: .white.opacity(peak), location: mid),
                            .init(color: .clear, location: hi)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // Badge fina y neutra para etiquetar la tarjeta.
    private struct CardBadge: View {
        let text: String
        let systemImage: String

        var body: some View {
            Label(text, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
        }
    }

    // Use a paired dynamic fill and foreground so the light button always has
    // dark text, including when the app's accent itself resolves to white.
    private struct CardProminentButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(EagleVisualTheme.actionText)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(EagleVisualTheme.actionFill)
                        .opacity(configuration.isPressed ? 0.85 : 1)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }

    // Acción secundaria: relleno translúcido neutro y misma escala al presionar.
    private struct CardSecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .opacity(configuration.isPressed ? 0.7 : 1)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tu tarjeta, con tu estilo")
                        .font(.title2.bold())
                    Text("Cambia la imagen que ya usa Wallet sin añadir capas, animaciones ni efectos innecesarios.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .eagleHeaderCard()

                if !mgr.sbxready {
                    LaraAccessView(compact: true)
                } else if working {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Buscando tarjetas…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("No encontramos tarjetas")
                            .font(.headline)
                        Text("Comprueba que tengas una tarjeta compatible en Wallet y vuelve a buscar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Buscar de nuevo") {
                            refresh()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .padding(.horizontal, 20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    ForEach(cards) { card in
                        cardrow(
                            card: card,
                            onreplace: { card, option in
                                pendingcard = card
                                switch option {
                                case .photos:
                                    showimgpicker = true
                                case .files:
                                    showdocpicker = true
                                }
                            },
                            onrestore: { card in
                                pendingrestorecard = card
                                restoreimg(card: card)
                            },
                            oneditnum: { card in
                                pendingnumcard = card
                                currentcardnum = readcardnum(for: card) ?? ""
                                cardnuminput = currentcardnum
                                shownumbereditor = true
                            },
                            previewimg: previewimg
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Copia de seguridad automática", systemImage: "checkmark.shield")
                        .font(.footnote.weight(.semibold))
                    Text("Eagle conserva el archivo original antes del primer cambio para que puedas restaurarlo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Link("Idea original de drkm9743", destination: URL(string: "https://github.com/drkm9743")!)
                        .font(.footnote.weight(.medium))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .eagleScreenBackdrop()
        .navigationTitle("Tarjetas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh()
                } label: {
                    if working {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(working || !mgr.sbxready)
                .accessibilityLabel("Buscar tarjetas")
            }
        }
        .alert("Tarjetas", isPresented: Binding(
            get: { status != nil },
            set: { presented in
                if !presented {
                    status = nil
                    promptforrespring = false
                }
            }
        )) {
            if promptforrespring {
                Button("Reiniciar interfaz") {
                    status = nil
                    promptforrespring = false
                    mgr.respring()
                }
                Button("Más tarde", role: .cancel) {
                    status = nil
                    promptforrespring = false
                }
            } else {
                Button("Aceptar") { status = nil }
            }
        } message: {
            Text(status ?? "")
        }
        .alert("Editar terminación", isPresented: $shownumbereditor) {
            TextField("Terminación", text: $cardnuminput)
            Button("Guardar") {
                if let card = pendingnumcard {
                    applycardnum(card: card, newsuffix: cardnuminput)
                }
            }
            if let card = pendingnumcard, haspassjsonbackup(card: card) {
                Button("Restaurar original", role: .destructive) {
                    restorepassjson(card: card)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(currentcardnum.isEmpty
                ? LaraL10n.text(en: "Current ending: none", es: "Terminación actual: ninguna")
                : LaraL10n.text(en: "Current ending: \(currentcardnum)", es: "Terminación actual: \(currentcardnum)"))
        }
        .sheet(isPresented: $showimgpicker) {
            ImagePicker(imageData: $pickedimgdata)
        }
        .sheet(isPresented: $showdocpicker) {
            CardImageDocumentPicker(imgdata: $pickedimgdata)
        }
        .onChange(of: pickedimgdata) { _ in
            guard let card = pendingcard, let data = pickedimgdata else { return }
            pendingcard = nil
            pickedimgdata = nil
            applyreplace(card: card, imgdata: data)
        }
        .onAppear {
            if mgr.sbxready {
                refresh()
            }
        }
        .onChange(of: mgr.sbxready) { ready in
            if ready {
                refresh()
            }
        }
    }

    private func refresh() {
        guard !working else { return }
        working = true
        DispatchQueue.global(qos: .userInitiated).async {
            let items = scancards()
            DispatchQueue.main.async {
                self.cards = items
                self.working = false
            }
        }
    }

    private func scancards() -> [carditem] {
        let candidates = [
            "/var/mobile/Library/Passes/Cards",
            "/private/var/mobile/Library/Passes/Cards",
            "/var/mobile/Library/Passes/Passes/Cards",
            "/private/var/mobile/Library/Passes/Passes/Cards"
        ]

        for root in candidates {
            let bundles = collectcardbundles(in: root)
            if !bundles.isEmpty {
                return bundles
            }
        }

        let passdirs = ["/var/mobile/Library/Passes", "/private/var/mobile/Library/Passes"]
        for container in passdirs {
            let topentries = listdir(container)
            for primary in ["Cards", "Passes", "Wallet"] where topentries.contains(primary) {
                let candidate = joinpath(container, primary)
                let bundles = collectcardbundles(in: candidate)
                if !bundles.isEmpty { return bundles }
                let nested = joinpath(candidate, "Cards")
                let nestedbundles = collectcardbundles(in: nested)
                if !nestedbundles.isEmpty { return nestedbundles }
            }
        }

        return []
    }

    private func collectcardbundles(in cardsroot: String) -> [carditem] {
        let entries = listdir(cardsroot)
        guard !entries.isEmpty else { return [] }

        var bundles: [carditem] = []
        var seendirs: Set<String> = []

        for entry in entries where entry != "." && entry != ".." {
            let candidatedir = joinpath(cardsroot, entry)
            if let bgfile = cardbgfile(in: candidatedir) {
                if !seendirs.contains(candidatedir) {
                    bundles.append(carditem(
                        id: candidatedir,
                        imgpath: joinpath(candidatedir, bgfile),
                        dirpath: candidatedir,
                        bundlename: entry,
                        bgfilename: bgfile
                    ))
                    seendirs.insert(candidatedir)
                }
                continue
            }

            let nestedentries = listdir(candidatedir)
            for nested in nestedentries where nested != "." && nested != ".." {
                let nesteddir = joinpath(candidatedir, nested)
                if let bgfile = cardbgfile(in: nesteddir),
                   !seendirs.contains(nesteddir) {
                    bundles.append(carditem(
                        id: nesteddir,
                        imgpath: joinpath(nesteddir, bgfile),
                        dirpath: nesteddir,
                        bundlename: "\(entry)/\(nested)",
                        bgfilename: bgfile
                    ))
                    seendirs.insert(nesteddir)
                }
            }
        }

        return bundles
    }

    private func cardbgfile(in carddir: String) -> String? {
        let files = listdir(carddir)
        guard !files.isEmpty else { return nil }

        for name in Self.cardfiles where files.contains(name) {
            return name
        }
        return nil
    }

    private func listdir(_ path: String) -> [String] {
        let fm = FileManager.default

        for variant in pathvariants(for: path) {
            do {
                return try fm.contentsOfDirectory(atPath: variant)
            } catch {
                continue
            }
        }

        return []
    }

    private func pathvariants(for path: String) -> [String] {
        var variants: [String] = [path]
        if path.hasPrefix("/private/var/") {
            variants.append(String(path.dropFirst("/private".count)))
        } else if path.hasPrefix("/var/") {
            variants.append("/private" + path)
        }
        var unique: [String] = []
        for variant in variants where !unique.contains(variant) {
            unique.append(variant)
        }
        return unique
    }

    private func joinpath(_ parent: String, _ child: String) -> String {
        if parent.hasSuffix("/") { return parent + child }
        return parent + "/" + child
    }

    private func previewimg(for card: carditem) -> UIImage? {
        let lower = card.bgfilename.lowercased()
        if lower.hasSuffix(".pdf") {
            if let doc = PDFDocument(url: URL(fileURLWithPath: card.imgpath)),
               let page = doc.page(at: 0) {
                return page.thumbnail(of: CGSize(width: 640, height: 400), for: .cropBox)
            }
        } else if let img = UIImage(contentsOfFile: card.imgpath) {
            return img
        }

        if mgr.vfsready, let data = mgr.vfsread(path: card.imgpath, maxSize: 8 * 1024 * 1024) {
            if lower.hasSuffix(".pdf") {
                if let doc = PDFDocument(data: data),
                   let page = doc.page(at: 0) {
                    return page.thumbnail(of: CGSize(width: 640, height: 400), for: .cropBox)
                }
            } else {
                return UIImage(data: data)
            }
        }
        return nil
    }

    private func applyreplace(card: carditem, imgdata: Data) {
        guard let image = UIImage(data: imgdata) else {
            status = LaraL10n.text(en: "That image could not be read.", es: "No se pudo leer esa imagen.")
            return
        }

        let lower = card.bgfilename.lowercased()
        var payload: Data?
        if lower.hasSuffix(".png") {
            payload = image.pngData()
        } else if lower.hasSuffix(".pdf") {
            let pdf = PDFDocument()
            if let page = PDFPage(image: image) {
                pdf.insert(page, at: 0)
                payload = pdf.dataRepresentation()
            }
        } else {
            payload = image.pngData()
        }

        guard let data = payload else {
            status = LaraL10n.text(en: "The image could not be prepared.", es: "No se pudo preparar la imagen.")
            return
        }

        backupifneeded(card: card)
        if writeprefersbx(path: card.imgpath, data: data) {
            clearcache(for: card)
            promptforrespring = true
            status = LaraL10n.text(en: "The card was updated. Restart the interface now?", es: "La tarjeta se actualizó. ¿Quieres reiniciar la interfaz ahora?")
        } else {
            status = LaraL10n.text(en: "The card could not be updated.", es: "No se pudo actualizar la tarjeta.")
        }
    }

    private func backupifneeded(card: carditem) {
        let backuppath = card.imgpath + ".backup"
        let fm = FileManager.default
        if fm.fileExists(atPath: backuppath) { return }
        if let data = readprefersbx(path: card.imgpath, maxsize: 16 * 1024 * 1024) {
            _ = writeprefersbx(path: backuppath, data: data)
        }
    }

    private func restoreimg(card: carditem) {
        let backuppath = card.imgpath + ".backup"
        guard FileManager.default.fileExists(atPath: backuppath) else {
            status = LaraL10n.text(en: "There is no original backup for this card yet.", es: "Todavía no existe una copia original para esta tarjeta.")
            return
        }
        guard let data = readprefersbx(path: backuppath, maxsize: 16 * 1024 * 1024) else {
            status = LaraL10n.text(en: "The original backup could not be read.", es: "No se pudo leer la copia original.")
            return
        }
        if writeprefersbx(path: card.imgpath, data: data) {
            clearcache(for: card)
            promptforrespring = true
            status = LaraL10n.text(en: "The original design was restored. Restart the interface now?", es: "Se restauró el diseño original. ¿Quieres reiniciar la interfaz ahora?")
        } else {
            status = LaraL10n.text(en: "The original design could not be restored.", es: "No se pudo restaurar el diseño original.")
        }
    }

    private func passjsonpath(for card: carditem) -> String {
        card.dirpath + "/pass.json"
    }

    private func passjsonbackuppath(for card: carditem) -> String {
        card.dirpath + "/pass.json.backup"
    }

    private func haspassjsonbackup(card: carditem) -> Bool {
        FileManager.default.fileExists(atPath: passjsonbackuppath(for: card))
    }

    private func readpassjson(for card: carditem) -> Data? {
        if let data = readprefersbx(path: passjsonpath(for: card), maxsize: 512 * 1024) {
            return data
        }
        return nil
    }

    private func readcardnum(for card: carditem) -> String? {
        guard let data = readpassjson(for: card),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let suffix = json["primaryAccountSuffix"] as? String else {
            return nil
        }
        return suffix
    }

    private func backuppassjsonifneeded(card: carditem) {
        let src = passjsonpath(for: card)
        let backup = passjsonbackuppath(for: card)
        guard !FileManager.default.fileExists(atPath: backup) else { return }
        guard let data = readprefersbx(path: src, maxsize: 512 * 1024) else { return }
        _ = writeprefersbx(path: backup, data: data)
    }

    private func applycardnum(card: carditem, newsuffix: String) {
        guard var json = (readpassjson(for: card)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else {
            status = LaraL10n.text(en: "The card information could not be read.", es: "No se pudo leer la información de la tarjeta.")
            return
        }
        backuppassjsonifneeded(card: card)
        let trimmed = newsuffix.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            json.removeValue(forKey: "primaryAccountSuffix")
        } else {
            json["primaryAccountSuffix"] = trimmed
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            status = LaraL10n.text(en: "The card information could not be prepared.", es: "No se pudo preparar la información de la tarjeta.")
            return
        }
        if writeprefersbx(path: passjsonpath(for: card), data: data) {
            clearcache(for: card)
            currentcardnum = trimmed
            status = LaraL10n.text(en: "The card ending was updated.", es: "La terminación se actualizó.")
        } else {
            status = LaraL10n.text(en: "The card ending could not be updated.", es: "No se pudo actualizar la terminación.")
        }
    }

    private func restorepassjson(card: carditem) {
        let backup = passjsonbackuppath(for: card)
        guard FileManager.default.fileExists(atPath: backup) else {
            status = LaraL10n.text(en: "There is no original information backup for this card.", es: "No existe una copia original de la información de esta tarjeta.")
            return
        }
        guard let data = readprefersbx(path: backup, maxsize: 512 * 1024) else {
            status = LaraL10n.text(en: "The original backup could not be read.", es: "No se pudo leer la copia original.")
            return
        }
        if writeprefersbx(path: passjsonpath(for: card), data: data) {
            clearcache(for: card)
            currentcardnum = readcardnum(for: card) ?? ""
            status = LaraL10n.text(en: "The original card ending was restored.", es: "Se restauró la terminación original.")
        } else {
            status = LaraL10n.text(en: "The original card ending could not be restored.", es: "No se pudo restaurar la terminación original.")
        }
    }

    private func clearcache(for card: carditem) {
        let fm = FileManager.default
        let dir = card.dirpath
        let cachepath: String
        if dir.lowercased().hasSuffix(".pkpass") {
            cachepath = dir.replacingOccurrences(of: "pkpass", with: "cache")
        } else {
            cachepath = dir + ".cache"
        }
        if fm.fileExists(atPath: cachepath) {
            try? fm.removeItem(atPath: cachepath)
        }
    }

    private func readprefersbx(path: String, maxsize: Int) -> Data? {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
            return data.count > maxsize ? data.prefix(maxsize) : data
        }
        if mgr.vfsready {
            return mgr.vfsread(path: path, maxSize: maxsize)
        }
        return nil
    }

    private func writeprefersbx(path: String, data: Data) -> Bool {
        do {
            print("(card) writing to \(path)")
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            guard mgr.vfsready else { return false }
            return mgr.vfsoverwritewithdata(target: path, data: data)
        }
    }
}

struct CardImageDocumentPicker: UIViewControllerRepresentable {
    @Binding var imgdata: Data?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.png, .jpeg, .image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: CardImageDocumentPicker
        init(_ parent: CardImageDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            if let data = try? Data(contentsOf: url) {
                parent.imgdata = data
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
