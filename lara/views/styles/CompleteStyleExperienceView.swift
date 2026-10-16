import SwiftUI

struct CompleteStyleLivePreviewView: View {
    let title: String
    let wallpaperPack: CompleteStylePack?
    let passcodePack: CompleteStylePack?
    let cardPack: CompleteStylePack?
    let onApply: (() -> Void)?

    @ObservedObject private var manager = CompleteStyleManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPage = 0

    init(
        title: String,
        wallpaperPack: CompleteStylePack?,
        passcodePack: CompleteStylePack?,
        cardPack: CompleteStylePack?,
        onApply: (() -> Void)? = nil
    ) {
        self.title = title
        self.wallpaperPack = wallpaperPack
        self.passcodePack = passcodePack
        self.cardPack = cardPack
        self.onApply = onApply
    }

    private var components: [CompleteStyleComponent] {
        var result: [CompleteStyleComponent] = []
        if wallpaperPack != nil { result.append(.wallpaper) }
        if passcodePack != nil { result.append(.passcode) }
        if cardPack != nil { result.append(.card) }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.bold())
                    Text(LaraL10n.text(
                        en: "Real assets and compatibility before changing your iPhone",
                        es: "Recursos reales y compatibilidad antes de cambiar tu iPhone"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .eagleHeaderCard()
                .padding(.horizontal, 20)
                .padding(.top, 8)

                preflightBar
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                TabView(selection: $selectedPage) {
                    ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                        ScrollView(.vertical, showsIndicators: false) {
                            previewPage(component)
                                .frame(maxWidth: .infinity)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(components.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedPage ? Color.primary : Color.secondary.opacity(0.25))
                            .frame(width: index == selectedPage ? 20 : 7, height: 7)
                            .animation(.easeOut(duration: 0.2), value: selectedPage)
                    }
                }
                .frame(height: 22)

                VStack(spacing: 10) {
                    if let onApply {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onApply()
                            }
                        } label: {
                            Label(
                                mgr.sbxready
                                    ? LaraL10n.text(en: "Apply this selection", es: "Aplicar esta selección")
                                    : LaraL10n.text(en: "Prepare Eagle to apply", es: "Prepara Eagle para aplicar"),
                                systemImage: mgr.sbxready ? "sparkles" : "lock.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(EagleApplyButtonStyle(busy: manager.isWorking))
                        .disabled(!mgr.sbxready || manager.isWorking || components.isEmpty)
                    }

                    Label(
                        LaraL10n.text(
                            en: "Guardian protects the current state before applying.",
                            es: "Guardian protege el estado actual antes de aplicar."
                        ),
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .eagleScreenBackdrop()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LaraL10n.text(en: "Close", es: "Cerrar")) { dismiss() }
                }
            }
            .onAppear {
                manager.refreshCompatibility()
            }
        }
    }

    private var preflightBar: some View {
        HStack(spacing: 8) {
            ForEach(components) { component in
                HStack(spacing: 5) {
                    Image(systemName: preflightSymbol(for: component))
                    Text(preflightTitle(for: component))
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(preflightColor(for: component))
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(
                    preflightColor(for: component).opacity(0.10),
                    in: Capsule()
                )
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(LaraL10n.text(en: "Guardian ready", es: "Guardian listo"))
        }
    }

    private func preflightIsReady(_ component: CompleteStyleComponent) -> Bool {
        guard mgr.sbxready else { return false }
        switch component {
        case .wallpaper: return true
        case .passcode: return manager.passcodeAvailable
        case .card: return manager.cardAvailable
        }
    }

    private func preflightTitle(for component: CompleteStyleComponent) -> String {
        guard mgr.sbxready else { return LaraL10n.text(en: "Access", es: "Acceso") }
        return preflightIsReady(component)
            ? LaraL10n.text(en: "Ready", es: "Listo")
            : LaraL10n.text(en: "Will skip", es: "Se omitirá")
    }

    private func preflightSymbol(for component: CompleteStyleComponent) -> String {
        guard mgr.sbxready else { return "lock.fill" }
        return preflightIsReady(component) ? "checkmark.circle.fill" : "minus.circle.fill"
    }

    private func preflightColor(for component: CompleteStyleComponent) -> Color {
        guard mgr.sbxready else { return .orange }
        return preflightIsReady(component) ? .green : .secondary
    }

    @ViewBuilder
    private func previewPage(_ component: CompleteStyleComponent) -> some View {
        switch component {
        case .wallpaper:
            if let wallpaperPack {
                CompleteWallpaperLivePage(pack: wallpaperPack)
            }
        case .passcode:
            if let passcodePack {
                CompletePasscodeLivePage(pack: passcodePack)
            }
        case .card:
            if let cardPack {
                CompleteCardLivePage(pack: cardPack)
            }
        }
    }
}

private struct CompleteWallpaperLivePage: View {
    let pack: CompleteStylePack

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(.black)

                LaraRemoteMediaPreview(
                    url: pack.wallpaperPreviewURL,
                    animated: true,
                    contentMode: .fill,
                    showsRetry: true,
                    background: .black
                )
                    .clipShape(RoundedRectangle(cornerRadius: 37, style: .continuous))
                    .padding(5)
            }
            .frame(width: 242, height: 486)
            .shadow(color: pack.primary.color.opacity(0.28), radius: 24, y: 14)

            VStack(spacing: 3) {
                Label(LaraL10n.text(en: "Real animated wallpaper", es: "Fondo animado real"), systemImage: "livephoto")
                    .font(.headline)
                Text("\(pack.wallpaperName) · \(pack.wallpaperAuthor)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct CompletePasscodeLivePage: View {
    let pack: CompleteStylePack

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.black)
                AsyncImage(url: pack.passcodePreviewURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                    } else if case .failure = phase {
                        unavailable
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: 390)
            .aspectRatio(0.78, contentMode: .fit)
            .shadow(color: pack.secondary.color.opacity(0.2), radius: 22, y: 12)

            VStack(spacing: 3) {
                Label(LaraL10n.text(en: "Exact digits from the package", es: "Números exactos del paquete"), systemImage: "circle.grid.3x3.fill")
                    .font(.headline)
                Text("\(pack.passcodeName) · \(pack.passcodeAuthor)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
            Text(LaraL10n.text(en: "Preview unavailable", es: "Vista previa no disponible"))
                .font(.subheadline)
        }
        .foregroundStyle(.white.opacity(0.72))
    }
}

private struct CompleteCardLivePage: View {
    let pack: CompleteStylePack

    var body: some View {
        VStack(spacing: 28) {
            Group {
                if let image = CompleteCardStyleEngine.previewImage(pack: pack) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(pack.secondary.color)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topLeading) {
                Image(systemName: pack.symbol)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(25)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "wave.3.right")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(25)
            }
            .frame(maxWidth: 430)
            .shadow(color: pack.primary.color.opacity(0.28), radius: 25, y: 14)

            VStack(spacing: 3) {
                Label(LaraL10n.text(en: "Final Wallet render", es: "Render final de Wallet"), systemImage: "creditcard.fill")
                    .font(.headline)
                Text(LaraL10n.text(en: "Generated locally by Eagle", es: "Generado localmente por Eagle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

struct CompleteStyleMixerView: View {
    @ObservedObject private var manager = CompleteStyleManager.shared
    @ObservedObject private var mgr = laramgr.shared
    @State private var wallpaperID = CompleteStylePack.all[1].id
    @State private var passcodeID = CompleteStylePack.all[3].id
    @State private var cardID = CompleteStylePack.all[0].id
    @State private var showLivePreview = false

    private var wallpaperPack: CompleteStylePack { pack(for: wallpaperID) }
    private var passcodePack: CompleteStylePack { pack(for: passcodeID) }
    private var cardPack: CompleteStylePack { pack(for: cardID) }

    private var selection: CompleteStyleSelection {
        CompleteStyleSelection(
            title: "Mi combinación",
            wallpaperPack: wallpaperPack,
            passcodePack: passcodePack,
            cardPack: cardPack
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(LaraL10n.text(en: "Three parts. One identity.", es: "Tres piezas. Una identidad."))
                        .font(.title2.bold())
                    Text(LaraL10n.text(
                        en: "Mix only what matters. Eagle keeps the application coordinated and reversible.",
                        es: "Mezcla solamente lo que importa. Eagle mantiene la aplicación coordinada y reversible."
                    ))
                        .foregroundStyle(.secondary)
                }
                .eagleHeaderCard()

                mixedPreview

                VStack(spacing: 0) {
                    pickerRow(
                        component: .wallpaper,
                        selected: wallpaperPack,
                        selection: $wallpaperID
                    )
                    Divider().padding(.leading, 60)
                    pickerRow(
                        component: .passcode,
                        selected: passcodePack,
                        selection: $passcodeID
                    )
                    Divider().padding(.leading, 60)
                    pickerRow(
                        component: .card,
                        selected: cardPack,
                        selection: $cardID
                    )
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Button {
                    showLivePreview = true
                } label: {
                    Label(LaraL10n.text(en: "Real preview", es: "Vista previa real"), systemImage: "eye.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EagleSecondaryButtonStyle())

                Label(
                    "Solo se guarda una acción para Deshacer. Los originales permanecen disponibles por separado.",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .eagleBackdropText()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        // Apply (with its progress) stays fixed at the bottom; Prepare takes its place until ready.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EagleApplyBar(ready: mgr.sbxready, onPrepared: { manager.refreshCompatibility() }) {
                if manager.isWorking {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(manager.stage).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(manager.progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: manager.progress)
                            .tint(cardPack.secondary.color)
                    }
                }

                Button {
                    manager.apply(selection: selection)
                } label: {
                    Label(LaraL10n.text(en: "Apply combination", es: "Aplicar combinación"), systemImage: "wand.and.sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EagleApplyButtonStyle(fill: cardPack.secondary.color, text: .white,
                                                   busy: manager.isWorking))
                .disabled(manager.isWorking || !mgr.sbxready)
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle("Crear combinación")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { manager.refreshCompatibility() }
        .fullScreenCover(isPresented: $showLivePreview) {
            CompleteStyleLivePreviewView(
                title: LaraL10n.text(en: "My Mix", es: "Mi combinación"),
                wallpaperPack: wallpaperPack,
                passcodePack: passcodePack,
                cardPack: cardPack
            ) {
                manager.apply(selection: selection)
            }
        }
    }

    private var mixedPreview: some View {
        ZStack {
            LinearGradient(
                colors: [wallpaperPack.primary.color, cardPack.secondary.color, passcodePack.tertiary.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .bottom, spacing: -24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 27, style: .continuous).fill(.black)
                    LaraRemoteMediaPreview(
                        url: wallpaperPack.wallpaperPreviewURL,
                        animated: false,
                        contentMode: .fill,
                        showsRetry: false,
                        background: wallpaperPack.secondary.color
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(4)
                }
                .frame(width: 118, height: 235)

                VStack(spacing: 12) {
                    if let image = CompleteCardStyleEngine.previewImage(pack: cardPack) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .frame(width: 166)
                            .rotationEffect(.degrees(4))
                    }

                    AsyncImage(url: passcodePack.passcodePreviewURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(width: 112, height: 92)
                    .padding(6)
                    .background(.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .offset(y: -15)
            }
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func pickerRow(
        component: CompleteStyleComponent,
        selected: CompleteStylePack,
        selection: Binding<String>
    ) -> some View {
        Menu {
            ForEach(CompleteStylePack.all) { pack in
                Button {
                    selection.wrappedValue = pack.id
                } label: {
                    if pack.id == selected.id {
                        Label(pack.localizedName, systemImage: "checkmark")
                    } else {
                        Text(pack.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: component.systemImage)
                    .foregroundStyle(selected.tertiary.color)
                    .frame(width: 38, height: 38)
                    .background(selected.tertiary.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(componentValue(component, pack: selected))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(selected.localizedName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .contentShape(Rectangle())
        }
    }

    private func componentValue(_ component: CompleteStyleComponent, pack: CompleteStylePack) -> String {
        switch component {
        case .wallpaper: return pack.wallpaperName
        case .passcode: return pack.passcodeName
        case .card: return LaraL10n.text(en: "Eagle design", es: "Diseño Eagle")
        }
    }

    private func pack(for identifier: String) -> CompleteStylePack {
        CompleteStylePack.all.first { $0.id == identifier } ?? CompleteStylePack.all[0]
    }
}
