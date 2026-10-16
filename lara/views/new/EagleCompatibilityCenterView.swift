import SwiftUI

struct EagleCompatibilityCenterView: View {
    @AppStorage(EagleReleaseChannel.storageKey)
    private var channelRaw = EagleReleaseChannel.stable.rawValue
    @State private var showingLogs = false

    private var channel: EagleReleaseChannel {
        EagleFeaturePolicy.channel(from: channelRaw)
    }

    private var support: EagleSupportAssessment {
        eagleSupportAssessment()
    }

    private var island: EagleDynamicIslandCompatibility {
        .current
    }

    var body: some View {
        List {
            Section {
                statusRow(
                    title: LaraL10n.text(en: "Prepare engine", es: "Motor de preparación"),
                    value: supportTitle,
                    systemImage: supportIcon,
                    color: supportColor
                )

                statusRow(
                    title: LaraL10n.text(en: "Dynamic Island", es: "Isla Dinámica"),
                    value: islandTitle,
                    systemImage: islandIcon,
                    color: islandColor
                )

                statusRow(
                    title: LaraL10n.text(en: "Device", es: "Dispositivo"),
                    value: island.displayModel,
                    systemImage: "iphone",
                    color: .blue
                )

                Text(support.message(spanish: LaraL10n.language == .spanish))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                // The first header sits on the light top of the backdrop: on a small opaque pill, like
                // Eagle's other labels, so it reads there too.
                Text(LaraL10n.text(en: "This iPhone", es: "Este iPhone"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .padding(.leading, -6)
            }

            Section {
                Picker(
                    LaraL10n.text(en: "Feature channel", es: "Canal de funciones"),
                    selection: Binding(
                        get: { channel },
                        set: {
                            channelRaw = $0.rawValue
                            EagleFeaturePolicy.persist($0)
                        }
                    )
                ) {
                    ForEach(EagleReleaseChannel.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(LaraL10n.text(en: "Feature channel", es: "Canal de funciones"))
                .accessibilityValue(channel.title)
                .accessibilityHint(LaraL10n.text(
                    en: "Stable keeps only verified features. Advanced adds Scenes. Laboratory unlocks advanced system tools.",
                    es: "Estable mantiene solo funciones verificadas. Avanzado añade Escenas. Laboratorio desbloquea herramientas avanzadas del sistema."
                ))

                Text(channel.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(EagleProductFeature.allCases) { feature in
                    let enabled = EagleFeaturePolicy.allows(feature, channel: channel)
                    HStack(spacing: 12) {
                        Image(systemName: enabled ? "checkmark.circle.fill" : "lock.circle")
                            .font(.body)
                            .foregroundStyle(enabled ? Color.green : Color.secondary)
                            .frame(width: 24)
                        Text(feature.title)
                            .foregroundStyle(enabled ? .primary : .secondary)
                        Spacer(minLength: 12)
                        Text(feature.minimumChannel.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Color(uiColor: .tertiarySystemFill),
                                in: Capsule()
                            )
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(feature.title)
                    .accessibilityValue(enabled
                        ? LaraL10n.text(en: "Available", es: "Disponible")
                        : LaraL10n.text(
                            en: "Requires \(feature.minimumChannel.title)",
                            es: "Requiere \(feature.minimumChannel.title)"
                        ))
                }
            } header: {
                Text(LaraL10n.text(en: "Feature policy", es: "Política de funciones"))
            } footer: {
                Text(LaraL10n.text(
                    en: "Changing channel changes real feature availability. It never changes the supported iOS range or bypasses Prepare safety checks.",
                    es: "Cambiar el canal modifica la disponibilidad real de funciones. Nunca cambia el rango de iOS compatible ni evita las comprobaciones de Preparar."
                ))
            }

            Section {
                Button {
                    showingLogs = true
                } label: {
                    Label(
                        LaraL10n.text(en: "Open live logs", es: "Abrir logs en vivo"),
                        systemImage: "terminal"
                    )
                }

                EagleSupportSnapshotCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                EaglePrepareCrashReportCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text(LaraL10n.text(en: "Support", es: "Soporte"))
            } footer: {
                Text(LaraL10n.text(
                    en: "The snapshot contains no logs. A diagnostic report is created only when you request it and never runs during Prepare.",
                    es: "El resumen no contiene logs. El reporte de diagnóstico se crea solo cuando lo solicitas y nunca se ejecuta durante Preparar."
                ))
            }
        }
        .eagleScreenBackdrop()
        .navigationTitle(LaraL10n.text(en: "Compatibility", es: "Compatibilidad"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLogs) {
            LogsView(logger: globallogger)
        }
    }

    @ViewBuilder
    private func statusRow(
        title: String,
        value: String,
        systemImage: String,
        color: Color
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                statusIcon(systemImage, color: color)
                Text(title)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    statusIcon(systemImage, color: color)
                    Text(title)
                }
                Text(value)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder
    private func statusIcon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(
                color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }

    private var supportTitle: String {
        switch support.status {
        case .supported:
            return LaraL10n.text(en: "Supported", es: "Compatible")
        case .testedNeedsMoreTesting:
            return LaraL10n.text(en: "Limited testing", es: "Pruebas limitadas")
        case .possible:
            return LaraL10n.text(en: "Laboratory", es: "Laboratorio")
        case .unsupported:
            return LaraL10n.text(en: "Unsupported", es: "No compatible")
        }
    }

    private var supportIcon: String {
        support.allowsPrepare ? "checkmark.shield.fill" : "xmark.shield.fill"
    }

    private var supportColor: Color {
        switch support.status {
        case .supported: return .green
        case .testedNeedsMoreTesting, .possible: return .orange
        case .unsupported: return .red
        }
    }

    private var islandTitle: String {
        switch island.availability {
        case .supported:
            return LaraL10n.text(en: "Available", es: "Disponible")
        case .unsupported:
            return LaraL10n.text(en: "Not present", es: "No presente")
        case .unknown:
            return LaraL10n.text(en: "Needs verification", es: "Requiere verificación")
        }
    }

    private var islandIcon: String {
        island.availability == .supported
            ? "capsule.fill"
            : "capsule"
    }

    private var islandColor: Color {
        switch island.availability {
        case .supported: return .green
        case .unsupported: return .secondary
        case .unknown: return .orange
        }
    }
}
