#!/usr/bin/env python3
"""Project exact user-authorized October 15 rendering back to public rendering.

Older migration checks keep their frozen public logic oracle. These counted
replacements acknowledge the accepted October 15 visual base without accepting
arbitrary rendering changes, altered actions or different enablement. The circle
integration adds counted press, check, favorite and loading effects; it never
replaces an entire screen or changes a frozen public hash.
"""
from verify_eagle_dock_apply_flow import replace_once


def counted(source, before, after, count):
    assert source.count(before) == count, (before, source.count(before), count)
    return source.replace(before, after)


def inline_aura_animation_visuals(source):
    # Polish pass (16 Oct): preview ring at 60 fps, shape-cast card shadow, contrasting Share label.
    source = replace_once(source, """                // 60 fps while the preview animates: the turning ring stepped visibly at 30.
                TimelineView(.animation(
                    minimumInterval: 1.0 / 60.0,""", """                TimelineView(.animation(
                    minimumInterval: 1.0 / 30.0,""")
    source = replace_once(source, ".eagleSurfaceShadow(cornerRadius: 28, radius: 12, y: 5)",
                          ".shadow(color: EagleVisualTheme.surfaceShadow(for: colorScheme), radius: 12, y: 5)")
    source = counted(source, """
                    // The app tint is white in dark appearance: the label takes the contrasting colour.
                    .foregroundStyle(Color(uiColor: .systemBackground))""", "", 1)
    source = replace_once(source, '''        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !editingIcons || !mgr.dsready {
                auraActionBar
            }
        }
        .eagleScreenBackdrop()''', '        .background(Color(uiColor: .systemGroupedBackground))')
    source = replace_once(source, '''                if applySafetyBlocked || mgr.rcSafetyLocked {
                    diagnosticsCard''', '''                if !mgr.dsready {
                    LaraAccessView(compact: true)
                }

                if applySafetyBlocked || mgr.rcSafetyLocked {
                    diagnosticsCard''')
    source = replace_once(source, '''    /// Apply and Restore stay fixed at the bottom, in reach of the thumb, while the screen scrolls.
    /// Until Eagle is prepared, Prepare takes their place there, so it is always at hand.
    private var auraActionBar: some View {
        EagleApplyBar(ready: mgr.dsready) {
            VStack(spacing: 8) {
                applyButton
                restoreButton
            }
            .disabled(isApplying)
        }
    }

''', '')
    from verify_eagle_dock_apply_flow import declaration
    card = declaration(source, 'private var appearanceCard:')
    restored = replace_once(card, '''                Spacer()
            }
        }
        .padding(14)''', '''                Spacer()
            }

            applyButton
            restoreButton
        }
        .padding(14)''')
    source = replace_once(source, card, restored)
    for before, count in [
        ("                .transition(.eagleWorking)\n", 1),
        ("                                            .transition(.eagleCheck)\n", 2),
    ]:
        source = counted(source, before, "", count)
    return counted(source, ".buttonStyle(EaglePressableStyle(kind: .swatch))", ".buttonStyle(.plain)", 2)


def inline_dock_apply_visuals(source):
    # Island-style layout (16 Oct): no header card, refresh in the bar, title row, counter, halo label.
    source = replace_once(source, '                Label(LaraL10n.text(en: "Shadow", es: "Sombra"), systemImage: "circle.lefthalf.filled")\n                    .font(.subheadline.weight(.semibold))\n                Spacer()\n                Text(glowIntensity <= 0.005\n                    ? LaraL10n.text(en: "Off", es: "Sin sombra")\n                    : "\\(Int((glowIntensity * 100).rounded()))%")', '                Label(LaraL10n.text(en: "Dock light", es: "Luz del Dock"), systemImage: "sun.max.fill")\n                    .font(.subheadline.weight(.semibold))\n                Spacer()\n                Text("\\(Int((glowIntensity * 100).rounded()))%")')
    source = replace_once(source, '                    .frame(minWidth: 54)\n                remoteArrowButton(symbol: "chevron.right", step: 1)', '                    .frame(minWidth: 46)\n                remoteArrowButton(symbol: "chevron.right", step: 1)')
    source = replace_once(source, '            Image(systemName: symbol)\n                .font(.system(size: 13, weight: .bold))\n                .foregroundStyle(.primary)\n                .frame(width: 44, height: 44)\n                .background(Color.primary.opacity(0.06), in: Circle())', '            Image(systemName: symbol)\n                .font(.subheadline.weight(.bold))\n                .foregroundStyle(.primary)\n                .frame(width: 44, height: 44)\n                .background(Color.primary.opacity(0.08), in: Circle())')
    source = replace_once(source, '        return String(format: "%02d", current + 1) + " / " + String(format: "%02d", themes.count)', '        return "\\(current + 1) / \\(themes.count)"')
    source = replace_once(source, '            HStack(spacing: 8) {\n                Text(theme.localizedTitle)\n                    .font(.title3.bold())\n                    .lineLimit(2)\n                if active {\n                    Image(systemName: "checkmark.circle.fill")\n                        .font(.caption)\n                        .foregroundStyle(theme.color)\n                }\n                Spacer(minLength: 6)\n                Button {\n                    toggleFavorite(theme)\n                } label: {\n                    Image(systemName: favoriteIDs.contains(theme.id) ? "heart.fill" : "heart")\n                        .font(.system(size: 16))\n                        .foregroundStyle(favoriteIDs.contains(theme.id) ? Color.pink : .primary)\n                        .eagleSymbolPop(favoriteIDs.contains(theme.id))\n                        .frame(width: 44, height: 44)\n                        .background(Color.primary.opacity(0.05), in: Circle())\n                }\n                .buttonStyle(EaglePressableStyle(kind: .swatch))\n                .disabled(isApplying || remoteGallery.downloadingID != nil)\n                .accessibilityLabel(favoriteIDs.contains(theme.id)\n                    ? LaraL10n.text(en: "Remove from favorites", es: "Quitar de favoritos")\n                    : LaraL10n.text(en: "Add to favorites", es: "Añadir a favoritos"))\n                .accessibilityValue(theme.localizedTitle)\n            }\n', '            HStack(spacing: 8) {\n                Text(theme.localizedTitle)\n                    .font(.title3.bold())\n                    .multilineTextAlignment(.center)\n                    .lineLimit(2)\n                Label(\n                    theme.frameCount > 1 ? "Live" : "Static",\n                    systemImage: theme.frameCount > 1 ? "play.fill" : "photo.fill"\n                )\n                .font(.caption2.weight(.bold))\n                .foregroundStyle(.secondary)\n                if active {\n                    Image(systemName: "checkmark.circle.fill")\n                        .font(.caption)\n                        .foregroundStyle(theme.color)\n                }\n                Button {\n                    toggleFavorite(theme)\n                } label: {\n                    Image(systemName: favoriteIDs.contains(theme.id) ? "heart.fill" : "heart")\n                        .font(.system(size: 18, weight: .medium))\n                        .foregroundStyle(.primary)\n                        .eagleSymbolPop(favoriteIDs.contains(theme.id))\n                        .frame(width: 44, height: 44)\n                        .contentShape(Circle())\n                }\n                .buttonStyle(EaglePressableStyle(kind: .swatch))\n                .disabled(isApplying || remoteGallery.downloadingID != nil)\n                .scaleEffect(favoriteIDs.contains(theme.id) ? 1.06 : 1)\n                .animation(\n                    reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.72),\n                    value: favoriteIDs.contains(theme.id)\n                )\n                .accessibilityLabel(favoriteIDs.contains(theme.id)\n                    ? LaraL10n.text(en: "Remove from favorites", es: "Quitar de favoritos")\n                    : LaraL10n.text(en: "Add to favorites", es: "Añadir a favoritos"))\n                .accessibilityValue(theme.localizedTitle)\n            }\n')
    source = replace_once(source, '        .navigationTitle(LaraL10n.text(en: "Dock Gallery", es: "Galería Dock"))\n        // Refresh in the navigation bar, as in Island Gallery.\n        .toolbar {\n            ToolbarItem(placement: .navigationBarTrailing) {\n                Button { Task { await remoteGallery.load(force: true) } } label: {\n                    Image(systemName: "arrow.clockwise")\n                }\n                .disabled(remoteGallery.loading || isApplying)\n                .accessibilityLabel(LaraL10n.text(en: "Refresh collection", es: "Actualizar colección"))\n            }\n        }\n        .navigationBarTitleDisplayMode(.inline)', '        .navigationTitle(LaraL10n.text(en: "Dock Gallery", es: "Galería Dock"))\n        .navigationBarTitleDisplayMode(.inline)')
    source = replace_once(source, '            VStack(alignment: .leading, spacing: 14) {\n                mediaFilterControl\n', '            VStack(alignment: .leading, spacing: 14) {\n                collectionHeader\n                mediaFilterControl\n')
    # Polish pass (16 Oct): heart press feedback and the collection header on an opaque card.
    source = replace_once(source, ".buttonStyle(EaglePressableStyle(kind: .swatch))", ".buttonStyle(.plain)")
    source = replace_once(source, """        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // On its own opaque surface, like the filters below it, so it reads over the light top of the
        // backdrop as well as over the dark.
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }""", """        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }""")
    source = replace_once(source, '''        // The selected theme's Apply stays fixed at the bottom, in reach of the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let theme = selectedRemoteTheme {
                EagleApplyBar {
                    remoteActionButton(theme)
                }
            }
        }
        .eagleScreenBackdrop()''', '        .background(Color(uiColor: .systemBackground).ignoresSafeArea())')
    source = replace_once(source, '''        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAccessSetup)''', '''        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showAccessSetup)''')
    source = replace_once(source, '                .eagleScreenBackdrop()', '                .background(Color(uiColor: .systemGroupedBackground))')
    source = replace_once(source, '''                        disabled: isApplying || remoteGallery.downloadingID != nil
                    )
                } else''', '''                        disabled: isApplying || remoteGallery.downloadingID != nil
                    )
                    remoteActionButton(theme)
                } else''')
    source = counted(source, ".buttonStyle(EaglePressableStyle())", ".buttonStyle(.plain)", 3)
    source = replace_once(source, "                        .eagleSymbolPop(favoriteIDs.contains(theme.id))\n", "")
    source = replace_once(source, """                // Turns while the collection refreshes (from the clock, so it really stops at the end).
                EagleAmbientTimeline(paused: !remoteGallery.loading) { context in
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .rotationEffect(.degrees(remoteGallery.loading
                            ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
                            : 0))
                }
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.08), in: Circle())""", """                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.08), in: Circle())""")
    source = replace_once(source, """.buttonStyle(EagleApplyButtonStyle(fill: active ? .red : EagleVisualTheme.actionFill,
                                               text: active ? .white : EagleVisualTheme.actionText,
                                               busy: isApplying))""", """.buttonStyle(.borderedProminent)
            .tint(active ? .red : EagleVisualTheme.actionFill)
            .foregroundStyle(active ? Color.white : EagleVisualTheme.actionText)""")
    return replace_once(source, ".buttonStyle(EagleApplyButtonStyle(busy: downloading || isApplying))", """.buttonStyle(.borderedProminent)
            .tint(EagleVisualTheme.actionFill)
            .foregroundStyle(EagleVisualTheme.actionText)""")


def inline_island_apply_visuals(source):
    # Polish pass (16 Oct): opaque summary cards and press feedback on the small buttons.
    for radius, count in ((24, 1), (20, 2)):
        source = counted(source, f""".background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: {radius}, style: .continuous))
        .overlay {{ RoundedRectangle(cornerRadius: {radius}, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }}""",
                         f".background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: {radius}))", count)
    source = counted(source, ".buttonStyle(EaglePressableStyle(kind: .swatch))", ".buttonStyle(.plain)", 3)
    source = counted(source, ".buttonStyle(EaglePressableStyle(kind: .card))", ".buttonStyle(.plain)", 1)
    source = replace_once(source, '            .eagleScreenBackdrop()', '            .background(Color(uiColor: .systemBackground))')
    source = replace_once(source, '''            .navigationTitle("Island Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {''', '''            .navigationTitle("Island Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {''')
    source = replace_once(source, '            .eagleActionBar()', '''            .padding(.horizontal, 20)
            .padding(.top, 13)
            .padding(.bottom, 12)
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5) }''')
    source = counted(source, ".buttonStyle(EaglePressableStyle())", ".buttonStyle(.plain)", 2)
    source = replace_once(source, "                        .eagleSymbolPop(favorites.contains(item.id))\n", "")
    source = replace_once(source, "                .eagleSymbolPop(favorites.contains(item.id))\n", "")
    source = replace_once(source, "                .animation(.easeInOut(duration: 0.22), value: isSelected)\n", "")
    return replace_once(source, ".buttonStyle(EagleApplyButtonStyle(busy: applying))", """.buttonStyle(.borderedProminent)
                .tint(EagleVisualTheme.actionFill)""")
