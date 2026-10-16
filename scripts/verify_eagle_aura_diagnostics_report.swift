import Foundation

@MainActor final class Context {
    var logs: [String] = []
    var events: [String] = []
    var now = Date(timeIntervalSince1970: 0)
    var fail = false
    var mutateHeader = false
    var written: String?
    var destination: URL?
}
@MainActor enum Runtime { static var context: Context! }
@MainActor func fixtureNow() -> Date {
    Runtime.context.events.append("clock"); return Runtime.context.now
}
@MainActor struct Logger {
    var logs: [String] { Runtime.context.events.append("logs"); return Runtime.context.logs }
}
@MainActor var globallogger: Logger { Logger() }
@MainActor enum FileManager {
    static let `default` = SelfProvider()
    @MainActor struct SelfProvider {
        var temporaryDirectory: URL {
            Runtime.context.events.append("directory")
            return URL(fileURLWithPath: "/fixture/Eagle Report/á/")
        }
    }
}
@MainActor enum AuraStudioDiagnostics {
    static func log(_ stage: String, _ detail: String) {
        Runtime.context.events.append("log:\(stage):\(detail)")
    }
}
@MainActor func fixtureHeader(_ timestamp: String, _ summary: String) -> [String] {
    Runtime.context.events.append("header:\(timestamp)|\(summary)")
    if Runtime.context.mutateHeader { Runtime.context.logs = ["eagle.aura later log should not enter report"] }
    return ["Eagle Aura Studio diagnostics", "timestamp=\(timestamp)", "summary=\(summary)", "--- filtered log ---"]
}
@MainActor func fixtureWrite(_ text: String, _ url: URL, atomically: Bool, encoding: String.Encoding) throws {
    precondition(atomically && encoding == .utf8)
    let c = Runtime.context!
    c.events.append("write:\(url.absoluteString)"); c.written = text; c.destination = url
    if c.fail { throw NSError(domain: "EagleReportTest", code: 7, userInfo: [NSLocalizedDescriptionKey: "simulated write failure"]) }
}

@main struct Check {
    @MainActor static func main() throws {
        var cases = 0, events = 0
        let samples: [[String]] = [[], ["unrelated\n\r\n"], ["EAGLE.AURA a\nEagle.Dock b\r\n(rc) c\rRemote Call d"],
                                   ["RemoteCall x\u{2028}eagle.island y", "other", "sesión eagle.aura 🦅"],
                                   ["eagle.aura repeated", "eagle.aura repeated"]]
        let sets = samples + [599, 600, 601, 1201].map { count in (0..<count).map { "eagle.aura line-\($0)" } }
        let dates = [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_792_000_000.123), Date(timeIntervalSince1970: -0.125)]
        let summaries = ["", "Applied and verified", "Error\nDetalle: á 🦅"]
        for logs in sets { for date in dates { for summary in summaries {
            for fail in [false, true] { for mutate in [false, true] {
                let a = Context(), b = Context()
                for c in [a, b] { c.logs = logs; c.now = date; c.fail = fail; c.mutateHeader = mutate }
                Runtime.context = a; let expected = PublicHost().makeDiagnosticsReport(summary: summary)
                Runtime.context = b; let actual = OwnedHost().makeDiagnosticsReport(summary: summary)
                precondition(expected == actual && a.events == b.events && a.written == b.written && a.destination == b.destination)
                precondition(Array(b.events.prefix(2)) == ["clock", "logs"])
                precondition(b.events[2].hasPrefix("header:") && b.events[3] == "directory" && b.events[4].hasPrefix("write:"))
                precondition(b.events.count == 6 && (actual == nil) == fail)
                precondition(b.events.last!.hasPrefix(fail ? "log:diagnostics.failed:" : "log:diagnostics.ready:"))
                precondition(b.written!.hasSuffix("\n") && b.destination!.lastPathComponent.hasPrefix("Eagle-Aura-Diagnostics-"))
                precondition(!b.destination!.lastPathComponent.contains(":"))
                if logs.count >= 599 {
                    let tail = logs.suffix(600).joined(separator: "\n") + "\n"
                    precondition(b.written!.hasSuffix(tail))
                    if logs.count > 600 { precondition(!b.written!.contains("eagle.aura line-0\n")) }
                }
                if mutate { precondition(!b.written!.contains("later log")) }
                cases += 1; events += b.events.count
            }}
        }}}
        // Exercise the real Foundation storage adapter in a unique temporary folder.
        let folder = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent("eagle-report-test-" + UUID().uuidString)
        try Foundation.FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? Foundation.FileManager.default.removeItem(at: folder) }
        var writes = 0
        let report = EagleAuraStudioDiagnosticsReport(
            now: { dates[1] }, readLogs: { ["ignored", "eagle.aura sesión 🦅"] },
            makeHeader: { ["timestamp=\($0)", "summary=\($1)"] },
            temporaryDirectory: { folder },
            writeReport: { try $0.write(to: $1, atomically: true, encoding: .utf8); writes += 1 },
            log: { _, _ in }
        )
        let first = report.makeDiagnosticsReport(summary: "first")!
        let firstContent = try String(contentsOf: first, encoding: .utf8)
        precondition(firstContent.contains("summary=first"))
        let second = report.makeDiagnosticsReport(summary: "second")!
        precondition(first == second && writes == 2)
        let content = try String(contentsOf: second, encoding: .utf8)
        precondition(content.contains("summary=second") && !content.contains("summary=first") && content.hasSuffix("eagle.aura sesión 🦅\n"))
        let missing = EagleAuraStudioDiagnosticsReport(
            now: { dates[1] }, readLogs: { [] }, makeHeader: { [$0, $1] },
            temporaryDirectory: { folder.appendingPathComponent("missing") },
            writeReport: { try $0.write(to: $1, atomically: true, encoding: .utf8) }, log: { _, _ in }
        )
        precondition(missing.makeDiagnosticsReport(summary: "fail") == nil)
        print("PASS: \(cases) report parity cases, \(events) exact events; last-600/newlines/Unicode/errors; real UTF-8 atomic create/replace and missing-directory failure")
    }
}
