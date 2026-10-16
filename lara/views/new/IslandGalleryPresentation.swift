import SwiftUI
import UIKit

/// One identity per artwork, including every Live style that shares native mode 36.
struct IslandGalleryArtwork: Identifiable {
    let style: IslandGalleryStyle
    var liveTheme: IslandLiveTheme? = nil
    var id: String { liveTheme?.id ?? (style == .singularityLive ? "singularity-live" : "island-\(style.rawValue)") }
    var isRemote: Bool { style == .singularityLive }
    var isLive: Bool { isRemote && (liveTheme?.isAnimated ?? true) }
    var title: String { liveTheme.map { LaraL10n.text(en: $0.title, es: $0.titleES) } ?? style.title }
    var subtitle: String {
        if isLive { return LaraL10n.text(en: "Art in motion. Made for your Island.", es: "Arte en movimiento. Hecho para tu isla.") }
        if isRemote { return LaraL10n.text(en: "Still art for your Island.", es: "Arte fijo para tu isla.") }
        return style.subtitle
    }
    var accent: Color {
        guard let rgb = liveTheme?.rgb else { return style.accent }
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
    var actionTextColor: Color {
        let rgb = liveTheme?.rgb ?? style.rgb
        let brightness = (0.2126 * Double(rgb.red) + 0.7152 * Double(rgb.green) + 0.0722 * Double(rgb.blue)) / 255
        return brightness > 0.65 ? .black : .white
    }
    var posterURL: URL? { isRemote ? (liveTheme?.posterURL ?? IslandLiveMedia.posterURL) : nil }
    var motionURL: URL? { isRemote ? (liveTheme?.previewURL ?? IslandLiveMedia.previewURL) : nil }
}

typealias IslandGalleryFilter = EagleIslandGalleryFilter

extension EagleIslandGalleryFilter {
    var title: String {
        title(localizedText: { LaraL10n.text(en: $0, es: $1) })
    }
    func includes(_ artwork: IslandGalleryArtwork, favorites: Set<String>) -> Bool {
        includes(isLive: artwork.isLive, artworkID: artwork.id, favorites: favorites)
    }
}

struct IslandGalleryView: View {
    @ObservedObject private var manager = laramgr.shared
    @AppStorage("eagle.islandGallery.selectedStyle") private var selectedRaw = IslandGalleryStyle.starlight.rawValue
    @AppStorage("eagle.islandGallery.selectedArtworkID") private var selectedID = ""
    @AppStorage("eagle.islandGallery.favoriteIDs") private var favoritesJSON = "[]"
    @AppStorage("eagle.islandGallery.shadowIntensity") private var shadowIntensity = 0.72
    @AppStorage("eagle.islandGallery.positionX") private var positionX = 0.0
    @AppStorage("eagle.islandGallery.positionY") private var positionY = 0.0
    @AppStorage("eagle.auraStudio.activeFlags") private var activeFlagsRaw = 0
    @AppStorage("eagle.auraStudio.activeIslandMode") private var activeIslandModeRaw = 0
    @AppStorage("eagle.islandGallery.activeLiveID") private var activeLiveID = "singularity-live"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var liveThemes: [IslandLiveTheme] = []
    @State private var loading = false
    @State private var loadFailed = false
    @State private var filter: IslandGalleryFilter = .all
    @State private var search = ""
    @State private var motionPaused = false
    @State private var applying = false
    @State private var showAccess = false
    @State private var rememberedSelections: [IslandGalleryFilter: String] = [:]

    private var artworks: [IslandGalleryArtwork] {
        EagleIslandGalleryCollection.assemble(
            styles: { IslandGalleryStyle.allCases },
            isAvailable: { $0.isAvailableInGallery },
            remoteStyle: IslandGalleryStyle.singularityLive,
            themes: { liveThemes },
            makeArtwork: { IslandGalleryArtwork(style: $0, liveTheme: $1) }
        )
    }
    private var favorites: Set<String> {
        EagleIslandGalleryFavorites.decode(favoritesJSON)
    }
    private var visibleArtworks: [IslandGalleryArtwork] {
        EagleIslandGalleryCollection.visible(
            search: { search },
            artworks: { artworks },
            filter: { filter },
            favorites: { favorites },
            isLive: { $0.isLive },
            title: { $0.title },
            subtitle: { $0.subtitle }
        )
    }
    private var selected: IslandGalleryArtwork? {
        selectionController.selected
    }
    private var activeArtwork: IslandGalleryArtwork? {
        artworks.first(where: isActive)
    }
    private var hasRetiredIslandStyle: Bool {
        (activeFlagsRaw & 1) != 0 &&
            IslandGalleryStyle(rawValue: activeIslandModeRaw)?.isAvailableInGallery == false
    }
    private func isActive(_ item: IslandGalleryArtwork) -> Bool {
        (activeFlagsRaw & 1) != 0 && activeIslandModeRaw == item.style.rawValue &&
            (!item.isRemote || activeLiveID == item.id)
    }
    private var selectionIndex: Int {
        selectionController.selectionIndex
    }

    private var selectionController: EagleIslandGallerySelection<IslandGalleryArtwork> {
        EagleIslandGallerySelection(
            readVisibleArtworks: { self.visibleArtworks },
            readApplying: { self.applying },
            readSelectedID: { self.selectedID },
            writeSelectedID: { self.selectedID = $0 },
            writeSelectedRaw: { self.selectedRaw = $0 },
            readFilter: { self.filter },
            writeFilter: { self.filter = $0 },
            readMemory: { self.rememberedSelections },
            writeMemory: { self.rememberedSelections = $0 },
            rawStyle: { $0.style.rawValue },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    filterPicker
                    if let item = selected {
                        featuredPresentation(item)
                            .id("island-featured")
                    }
                    collectionSection(proxy: proxy)
                    if loadFailed { catalogRetry }
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(LaraL10n.text(en: "Loading collection…", es: "Cargando colección…"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let active = activeArtwork {
                        activeStyleSummary(active)
                    } else if hasRetiredIslandStyle {
                        retiredStyleRestoration
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            actionBar
            }
            .eagleScreenBackdrop()
            .navigationTitle("Island Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await loadCatalog(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading || applying)
                    .accessibilityLabel(LaraL10n.text(en: "Refresh collection", es: "Actualizar colección"))
                }
            }
            .sheet(isPresented: $showAccess) { accessSheet }
            .task { await loadCatalog() }
            .onAppear { restoreSelection() }
            .onChange(of: search) { _ in synchronizeSelection() }
            .onChange(of: favoritesJSON) { _ in synchronizeSelection() }
        }
    }

    private var filterPicker: some View {
        GalleryFilterBar(
            items: [IslandGalleryFilter.all, .still, .live, .favorites].map {
                GalleryFilterItem(id: $0.rawValue, title: $0.title, icon: $0.icon)
            },
            selectedID: filter.rawValue,
            disabled: applying,
            accessibilityPrefix: "island"
        ) { id in
            guard let option = IslandGalleryFilter(rawValue: id) else { return }
            selectFilter(option)
        }
    }

    private func featuredPresentation(_ item: IslandGalleryArtwork) -> some View {
        VStack(spacing: 16) {
            IslandGalleryStage(
                artwork: item,
                playing: !applying && !motionPaused && !reduceMotion,
                active: isActive(item),
                shadowIntensity: shadowIntensity,
                position: GalleryPosition(x: positionX, y: positionY)
            )
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { gesture in
                    guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                    animatedStep(gesture.translation.width < 0 ? 1 : -1)
                })
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                Spacer(minLength: 6)
                if item.isLive {
                    Button { motionPaused.toggle() } label: {
                        Image(systemName: motionPaused || reduceMotion ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(EaglePressableStyle(kind: .swatch))
                    .disabled(reduceMotion)
                    .accessibilityLabel(motionPaused
                        ? LaraL10n.text(en: "Play preview", es: "Reproducir vista previa")
                        : LaraL10n.text(en: "Pause preview", es: "Pausar vista previa"))
                }
                favoriteButton(item)
            }
            HStack(spacing: 28) {
                navigationButton("chevron.left", direction: -1)
                Text(String(format: "%02d", selectionIndex + 1) + " / " + String(format: "%02d", visibleArtworks.count))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 54)
                navigationButton("chevron.right", direction: 1)
            }
            .frame(maxWidth: .infinity)
            shadowControl
            GalleryPositionControl(
                x: $positionX,
                y: $positionY,
                disabled: applying
            )
        }
    }

    private var shadowControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(LaraL10n.text(en: "Shadow", es: "Sombra"), systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(shadowIntensity <= 0.005
                    ? LaraL10n.text(en: "Off", es: "Sin sombra")
                    : "\(Int((shadowIntensity * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $shadowIntensity, in: 0...1, step: 0.01)
                .tint(.primary)
                .disabled(applying)
                .accessibilityLabel(LaraL10n.text(
                    en: "Island shadow intensity",
                    es: "Intensidad de sombra de Island"
                ))
                .accessibilityValue(shadowIntensity <= 0.005
                    ? LaraL10n.text(en: "No shadow", es: "Sin sombra")
                    : "\(Int((shadowIntensity * 100).rounded()))%")
        }
        .padding(.horizontal, 2)
    }

    private func navigationButton(_ symbol: String, direction: Int) -> some View {
        Button { animatedStep(direction) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(EaglePressableStyle())
        .disabled(applying || visibleArtworks.count < 2)
        .accessibilityLabel(direction < 0
            ? LaraL10n.text(en: "Previous style", es: "Estilo anterior")
            : LaraL10n.text(en: "Next style", es: "Estilo siguiente"))
        .accessibilityIdentifier(direction < 0 ? "island-previous" : "island-next")
    }

    private func collectionSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(filter == .favorites
                    ? LaraL10n.text(en: "Your collection", es: "Tu colección")
                    : LaraL10n.text(en: "Collection", es: "Colección"))
                    .font(.headline).tracking(-0.4)
                Spacer(minLength: 8)
                Text("\(visibleArtworks.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            searchField
            if visibleArtworks.isEmpty { emptyCollection }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 260 : 145), spacing: 12)],
                      spacing: 12) {
                ForEach(visibleArtworks) { item in
                    collectionTile(item) {
                        selectForPreview(item)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            proxy.scrollTo("island-featured", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(LaraL10n.text(en: "Find a style…", es: "Busca un estilo…"), text: $search)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("island-search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 28, height: 36)
                }
                .accessibilityLabel(LaraL10n.text(en: "Clear search", es: "Borrar búsqueda"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        .disabled(applying)
    }

    private func collectionTile(_ item: IslandGalleryArtwork, action: @escaping () -> Void) -> some View {
        let isSelected = item.id == selected?.id
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                ZStack {
                    Color(red: 0.045, green: 0.047, blue: 0.06)
                    RadialGradient(colors: [item.accent.opacity(0.3), .clear], center: .center,
                                   startRadius: 0, endRadius: 100)
                    IslandGalleryArtworkImage(artwork: item, animated: false, compact: true)
                        .aspectRatio(2.4, contentMode: .fit)
                        .padding(.horizontal, 10)
                        .shadow(color: item.accent.opacity(0.4), radius: 9)
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: item.isLive ? "play.fill" : "sparkle")
                            Text(item.isLive ? "LIVE" : "STATIC")
                            Spacer()
                            if isActive(item) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.mint) }
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(12)
                }
                .frame(height: 107)
                .clipShape(RoundedRectangle(cornerRadius: 19))
                .contentShape(Rectangle())
            }
            .buttonStyle(EaglePressableStyle())
            .accessibilityLabel(LaraL10n.text(en: "Preview \(item.title)", es: "Ver \(item.title)"))
            .disabled(applying)
            HStack(spacing: 2) {
                Button(action: action) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(EaglePressableStyle(kind: .card))
                .disabled(applying)
                Button { toggleFavorite(item) } label: {
                    Image(systemName: favorites.contains(item.id) ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .foregroundStyle(favorites.contains(item.id) ? .pink : .secondary)
                        .eagleSymbolPop(favorites.contains(item.id))
                        .frame(width: 34, height: 44)
                }
                .buttonStyle(EaglePressableStyle(kind: .swatch))
                .disabled(applying)
                .accessibilityLabel(favoriteLabel(item))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(isSelected ? item.accent.opacity(0.9) : Color.primary.opacity(0.065), lineWidth: isSelected ? 1.5 : 1)
                .animation(.easeInOut(duration: 0.22), value: isSelected)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("island-tile-\(item.id)")
    }

    private var emptyCollection: some View {
        VStack(spacing: 14) {
            Image(systemName: filter == .favorites ? "heart" : "sparkle.magnifyingglass")
                .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text(filter == .favorites && search.isEmpty
                ? LaraL10n.text(en: "No favorites yet", es: "Sin favoritos")
                : LaraL10n.text(en: "No matching styles.", es: "No encontramos ese estilo."))
                .font(.headline)
            Button(LaraL10n.text(en: "Explore all", es: "Explorar todo")) {
                search = ""
                selectFilter(.all)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
    }

    private var catalogRetry: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
            Text(LaraL10n.text(en: "The Live collection couldn't be refreshed.", es: "No pudimos actualizar la colección Live."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(LaraL10n.text(en: "Retry", es: "Reintentar")) { Task { await loadCatalog(force: true) } }
                .font(.caption.weight(.semibold)).disabled(loading || applying)
        }
        .padding(14)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func activeStyleSummary(_ item: IslandGalleryArtwork) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.mint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(LaraL10n.text(en: "ON YOUR ISLAND", es: "EN TU ISLAND"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary)
                Text(item.title).font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button(role: .destructive) { restore() } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
            }
            .disabled(applying)
            .accessibilityLabel(LaraL10n.text(en: "Restore original Island", es: "Restaurar Island original"))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
    }

    private var retiredStyleRestoration: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.secondary)
            Text(LaraL10n.text(
                en: "A previous Island style is active",
                es: "Hay un estilo anterior activo en Island"
            ))
            .font(.subheadline.weight(.semibold))
            Spacer()
            Button(role: .destructive) { restore() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 44, height: 44)
            }
            .disabled(applying)
            .accessibilityLabel(LaraL10n.text(
                en: "Restore original Island",
                es: "Restaurar Island original"
            ))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
    }

    @ViewBuilder private var actionBar: some View {
        if let item = selected {
            HStack(spacing: 10) {
                Button {
                    if !manager.dsready { showAccess = true }
                    else { apply(item) }
                } label: {
                    HStack(spacing: 8) {
                        if applying { ProgressView().tint(EagleVisualTheme.actionText) }
                        else {
                            Image(systemName: !manager.dsready
                                ? "lock.shield.fill"
                                : (isActive(item) ? "arrow.clockwise" : "arrow.down.circle.fill"))
                        }
                        Text(!manager.dsready
                            ? LaraL10n.text(en: "Prepare to apply", es: "Preparar para aplicar")
                            : (isActive(item)
                                ? LaraL10n.text(en: "Reapply \(item.title)", es: "Reaplicar \(item.title)")
                                : LaraL10n.text(en: "Apply \(item.title)", es: "Aplicar \(item.title)")))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(EagleVisualTheme.actionText)
                }
                .buttonStyle(EagleApplyButtonStyle(busy: applying))
                .accessibilityIdentifier("island-apply")

                if isActive(item) && manager.dsready {
                    Button(role: .destructive) { restore() } label: {
                        Image(systemName: "trash.fill")
                            .font(.headline)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityLabel(LaraL10n.text(en: "Remove Island theme", es: "Quitar tema de Island"))
                    .accessibilityIdentifier("island-remove")
                }
            }
            .disabled(applying)
            .eagleActionBar()
        }
    }

    private var accessSheet: some View {
        NavigationStack {
            ScrollView {
                LaraAccessView(compact: true) { showAccess = false }.padding(20)
            }
            .navigationTitle(LaraL10n.text(en: "Prepare Eagle", es: "Preparar Eagle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LaraL10n.text(en: "Done", es: "Listo")) { showAccess = false }
                }
            }
        }
    }

    private func favoriteButton(_ item: IslandGalleryArtwork) -> some View {
        Button { toggleFavorite(item) } label: {
            Image(systemName: favorites.contains(item.id) ? "heart.fill" : "heart")
                .font(.system(size: 16))
                .foregroundStyle(favorites.contains(item.id) ? Color.pink : .primary)
                .eagleSymbolPop(favorites.contains(item.id))
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.05), in: Circle())
        }
        .buttonStyle(EaglePressableStyle(kind: .swatch))
        .disabled(applying)
        .accessibilityLabel(favoriteLabel(item))
        .accessibilityIdentifier("island-favorite")
    }

    private func favoriteLabel(_ item: IslandGalleryArtwork) -> String {
        favorites.contains(item.id)
            ? LaraL10n.text(en: "Remove \(item.title) from favorites", es: "Quitar \(item.title) de favoritos")
            : LaraL10n.text(en: "Save \(item.title) to favorites", es: "Guardar \(item.title) en favoritos")
    }

    private func toggleFavorite(_ item: IslandGalleryArtwork) {
        EagleIslandGalleryFavorites.toggle(
            applying: { applying },
            favorites: { favorites },
            artworkID: { item.id },
            save: { favoritesJSON = $0 },
            feedback: { UISelectionFeedbackGenerator().selectionChanged() }
        )
    }

    private func select(_ item: IslandGalleryArtwork) {
        selectionController.select(item)
    }

    private func selectForPreview(_ item: IslandGalleryArtwork) {
        select(item)
    }

    private func selectFilter(_ value: IslandGalleryFilter) {
        selectionController.selectFilter(value)
    }

    private func synchronizeSelection() {
        selectionController.synchronizeSelection()
    }

    private func restoreSelection() {
        EagleIslandGalleryRecovery.restore(
            readSelectedRaw: { selectedRaw },
            writeSelectedRaw: { selectedRaw = $0 },
            readSelectedID: { selectedID },
            writeSelectedID: { selectedID = $0 },
            styleForRaw: { IslandGalleryStyle(rawValue: $0) },
            isAvailable: { $0.isAvailableInGallery },
            defaultStyle: { IslandGalleryStyle.starlight },
            remoteStyle: { IslandGalleryStyle.singularityLive },
            artworkID: { IslandGalleryArtwork(style: $0).id },
            readActiveFlags: { activeFlagsRaw },
            readActiveMode: { activeIslandModeRaw },
            readActiveLiveID: { activeLiveID },
            activeArtworkID: { activeArtwork?.id }
        )
    }

    private func step(_ delta: Int) {
        selectionController.step(delta)
    }

    private func animatedStep(_ delta: Int) {
        step(delta)
    }

    private func loadCatalog(force: Bool = false) async {
        await EagleIslandGalleryLoadFlow.load(
            force: force,
            readLoading: { loading },
            writeLoading: { loading = $0 },
            fetch: { try await IslandLiveMedia.loadCatalog(force: $0) },
            writeThemes: { liveThemes = $0 },
            writeFailed: { loadFailed = $0 },
            restoreSelection: { restoreSelection() },
            synchronizeSelection: { synchronizeSelection() }
        )
    }

    private func apply(_ item: IslandGalleryArtwork) {
        EagleIslandGalleryActionFlow.apply(
            item,
            isApplying: { applying },
            select: { select($0) },
            setApplying: { applying = $0 },
            liveTheme: { $0.liveTheme },
            applyLive: { await IslandGalleryExecutor.shared.applyLive($0, shadowIntensity: shadowIntensity) },
            applyStyle: { await IslandGalleryExecutor.shared.apply($0.style, shadowIntensity: shadowIntensity) },
            feedback: { UINotificationFeedbackGenerator().notificationOccurred($0.succeeded ? .success : .error) },
            notify: { EagleNotifications.shared.result($0.succeeded, title: "Island Gallery", message: $0.message) }
        )
    }

    private func restore() {
        EagleIslandGalleryActionFlow.restore(
            isApplying: { applying },
            setApplying: { applying = $0 },
            execute: { await IslandGalleryExecutor.shared.restore() },
            feedback: { UINotificationFeedbackGenerator().notificationOccurred($0.succeeded ? .success : .error) },
            notify: { EagleNotifications.shared.result($0.succeeded, title: "Island Gallery", message: $0.message) }
        )
    }
}

/// Exactly one featured animation. Collection tiles request only PNG posters.
private struct IslandGalleryArtworkImage: View {
    let artwork: IslandGalleryArtwork
    let animated: Bool
    var compact = false
    var presentationMotion = false
    var body: some View {
        Group {
            if artwork.isRemote {
                LaraRemoteMediaPreview(url: animated ? artwork.motionURL : artwork.posterURL,
                                       animated: animated, contentMode: compact ? .fill : .fit,
                                       showsRetry: !compact, compactPlaceholder: compact, background: .clear,
                                       presentationMotion: presentationMotion && !animated)
            } else {
                if compact {
                    Image(artwork.style.assetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .eagleGalleryPresentationMotion(active: presentationMotion)
                } else {
                    Image(artwork.style.assetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .eagleGalleryPresentationMotion(active: presentationMotion)
                }
            }
        }
        .accessibilityHidden(compact)
    }
}

private struct IslandGalleryStage: View {
    let artwork: IslandGalleryArtwork
    let playing: Bool
    let active: Bool
    let shadowIntensity: Double
    let position: GalleryPosition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let islandWidth = min(max(proxy.size.width - 145, 126), 210)
            HStack(spacing: 10) {
                Text("9:41")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                    .frame(width: 38, alignment: .leading)

                ZStack {
                    IslandGalleryArtworkImage(
                        artwork: artwork,
                        animated: playing && artwork.isLive,
                        compact: true
                    )
                    .id(artwork.id)
                    .transition(.opacity)
                }
                .frame(width: islandWidth, height: 68)
                // Server previews are 1200×500 with the actual Island inset
                // inside a transparent canvas. Enlarge only the art, never
                // the surrounding controls or gallery layout.
                .scaleEffect(1.40)
                .frame(width: islandWidth, height: 68)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: artwork.id)
                .shadow(
                    color: artwork.accent.opacity(0.9 * shadowIntensity),
                    radius: 17 * shadowIntensity
                )
                .offset(x: position.x, y: position.y)

                HStack(spacing: 5) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }
                .font(.system(size: 12, weight: .semibold))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 112)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(artwork.title)
        .accessibilityIdentifier("island-featured-stage")
    }
}
