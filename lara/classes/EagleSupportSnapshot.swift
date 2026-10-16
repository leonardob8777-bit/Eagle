import Darwin
import Foundation
import SwiftUI
import UIKit

enum EagleDeviceIdentity {
    static func displayName(for identifier: String) -> String {
        guard let marketingName = marketingNames[identifier] else {
            return identifier
        }
        return "\(marketingName) (\(identifier))"
    }

    private static let marketingNames: [String: String] = [
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
    ]
}

extension EagleDynamicIslandCompatibility {
    var displayModel: String {
        EagleDeviceIdentity.displayName(for: modelIdentifier)
    }
}

enum EagleSupportSnapshot {
    static func makeText(
        defaults: UserDefaults = .standard,
        date: Date = Date()
    ) -> String {
        let bundle = Bundle.main
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = [
            operatingSystem.majorVersion,
            operatingSystem.minorVersion,
            operatingSystem.patchVersion,
        ].map(String.init).joined(separator: ".")
        let systemBuild = sysctlString("kern.osversion") ?? "unknown"
        let island = EagleDynamicIslandCompatibility.current
        let support = eagleSupportAssessment()
        let channel = EagleFeaturePolicy.persistedChannel(defaults: defaults)
        let language = LaraLanguage(
            rawValue: defaults.string(forKey: LaraLanguage.storageKey) ?? ""
        ) ?? .english
        let prepareSupport = island.isSimulator
            ? "unavailable [simulator]"
            : "\(support.status.rawValue) [\(support.reason.rawValue)]"

        return [
            "Eagle Support Snapshot",
            "App: Eagle \(version) (\(build))",
            "Device: \(island.displayModel)",
            "iOS: \(systemVersion) (\(systemBuild))",
            "Prepare support: \(prepareSupport)",
            "Dynamic Island hardware: \(island.availability.rawValue)",
            "Feature channel: \(channel.rawValue)",
            "Interface language: \(language.rawValue)",
            "Generated: \(timestampFormatter.string(from: date))",
        ].joined(separator: "\n")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0,
              size > 1, size <= 4_096 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct EagleSupportSnapshotCard: View {
    @State private var copied = false

    private var snapshot: String {
        EagleSupportSnapshot.makeText()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.blue.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(LaraL10n.text(
                        en: "Support Snapshot",
                        es: "Resumen de soporte"
                    ))
                        .font(.headline)
                    Text(LaraL10n.text(
                        en: "Share app, device, iOS, and compatibility details without attaching logs.",
                        es: "Comparte la app, el dispositivo, iOS y la compatibilidad sin adjuntar logs."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ShareLink(item: snapshot) {
                        Label(
                            LaraL10n.text(en: "Share", es: "Compartir"),
                            systemImage: "square.and.arrow.up"
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.borderedProminent)
                    // The contrasting colour on the black/white fill, grey while disabled.
                    .eagleProminentLabel()

                    copyButton
                }

                VStack(spacing: 10) {
                    ShareLink(item: snapshot) {
                        Label(
                            LaraL10n.text(en: "Share", es: "Compartir"),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    // The contrasting colour on the black/white fill, grey while disabled.
                    .eagleProminentLabel()

                    Button(action: copySnapshot) {
                        copyLabel
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var copyButton: some View {
        Button(action: copySnapshot) {
            copyLabel
        }
        .buttonStyle(.bordered)
    }

    private var copyLabel: some View {
        Label(
            copied
                ? LaraL10n.text(en: "Copied", es: "Copiado")
                : LaraL10n.text(en: "Copy", es: "Copiar"),
            systemImage: copied ? "checkmark" : "doc.on.doc"
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private func copySnapshot() {
        UIPasteboard.general.string = snapshot
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copied = false
        }
    }
}
