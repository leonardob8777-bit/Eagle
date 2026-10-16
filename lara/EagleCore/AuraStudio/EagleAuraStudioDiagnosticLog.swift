import Foundation

/// Formats one existing Aura diagnostic event; the caller owns the clock and delivery.
enum EagleAuraStudioDiagnosticLog {
    static func log(
        _ stage: String,
        _ detail: String = "",
        now: () -> Date,
        makeDelivery: () -> (String) -> Void
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let suffix = detail.isEmpty ? "" : " \(detail)"
        makeDelivery()("[\(formatter.string(from: now()))] (eagle.aura.apply) stage=\(stage)\(suffix)")
    }
}
