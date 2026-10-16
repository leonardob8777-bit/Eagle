import Foundation

/// Diagnostic text/file coordination. Runtime header data, storage and logging remain injected.
@MainActor
struct EagleAuraStudioDiagnosticsReport {
    let now: () -> Date
    let readLogs: () -> [String]
    let makeHeader: (String, String) -> [String]
    let temporaryDirectory: () -> URL
    let writeReport: (String, URL) throws -> Void
    let log: (String, String) -> Void

    func makeDiagnosticsReport(summary: String) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now())
        let relevantFragments = [
            "eagle.aura",
            "eagle.island",
            "eagle.dock",
            "(rc)",
            "remote call",
            "RemoteCall",
        ]
        let lines = readLogs()
            .flatMap { $0.components(separatedBy: .newlines) }
            .filter { line in
                relevantFragments.contains { fragment in
                    line.localizedCaseInsensitiveContains(fragment)
                }
            }
            .suffix(600)
        let header = makeHeader(timestamp, summary)
        let report = (header + Array(lines)).joined(separator: "\n") + "\n"
        let filename = "Eagle-Aura-Diagnostics-" +
            timestamp.replacingOccurrences(of: ":", with: "-") + ".txt"
        let url = temporaryDirectory()
            .appendingPathComponent(filename)
        do {
            try writeReport(report, url)
            log(
                "diagnostics.ready",
                "path=\(url.lastPathComponent) lines=\(lines.count)"
            )
            return url
        } catch {
            log(
                "diagnostics.failed",
                "error=\(error.localizedDescription)"
            )
            return nil
        }
    }
}

