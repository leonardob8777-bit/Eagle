import Foundation
import Combine
import Darwin

@MainActor private protocol LoggerProbe: AnyObject {
    var logs: [String] { get }
    func log(_ message: String)
    func divider()
    func enclosedlog(_ message: String)
    func flushdivider()
    func clear()
    func capture()
    func stopcapture()
    func flushToDisk()
}
extension EagleDiagnosticLogger: LoggerProbe {}
extension PublicDiagnosticLogger: LoggerProbe {}

@main private enum DiagnosticLoggerChecks {
    static let preferenceKey = "test.eagle.diagnostics.dividers"

    static func drain() async {
        // The public divider methods intentionally enqueue nested main-queue
        // work. Two queue barriers observe it without changing scheduling.
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    static func directory(_ parent: URL, _ name: String) throws -> URL {
        let result = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: false)
        return result
    }

    static func text(_ root: URL, _ name: String = "lara.log") throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "lara started: [^\\n]+", with: "lara started: <date>", options: .regularExpression)
    }

    static func setDividersDisabled(_ disabled: Bool) {
        UserDefaults.standard.setVolatileDomain(
            [preferenceKey: disabled], forName: UserDefaults.argumentDomain
        )
    }

    static func presentation(_ root: URL) async throws {
        for disabled in [false, true] {
            setDividersDisabled(disabled)
            let ownedDirectory = try directory(root, "owned-\(disabled)")
            let publicDirectory = try directory(root, "public-\(disabled)")
            let owned = EagleDiagnosticLogger(disableLogDividersKey: preferenceKey, logDirectory: ownedDirectory)
            let reference = PublicDiagnosticLogger(disableLogDividersKey: preferenceKey, logDirectory: publicDirectory)
            let legacy: Logger = owned
            precondition(legacy === owned, "Compatibility alias introduced another logger")
            var ownEvents: [[String]] = []
            var publicEvents: [[String]] = []
            let subscriptions = [
                owned.$logs.sink { ownEvents.append($0.map(normalize)) },
                reference.$logs.sink { publicEvents.append($0.map(normalize)) },
            ]
            let pair: [any LoggerProbe] = [owned, reference]
            let actions: [(any LoggerProbe) -> Void] = [
                { $0.clear() }, { $0.log("first") }, { $0.log("first") },
                { $0.log("first") }, { $0.log("second") }, { $0.divider() },
                { $0.log("after divider") }, { $0.enclosedlog("enclosed") },
                { $0.log("after enclosed") }, { $0.enclosedlog("another") },
                { $0.flushdivider() }, { $0.log("after flush") },
                { $0.log("") }, { $0.log("UITouch ignored in disk") },
                { $0.log("12345") }, { $0.log("Águila 🦅\nsecond line") },
                { $0.log(String(repeating: "🦅", count: 2200)) },
                { $0.log(String(repeating: "a", count: 9000)) },
                { $0.clear() }, { $0.log("repeat after clear") },
                { $0.log("repeat after clear") },
            ]
            for action in actions {
                for logger in pair { action(logger) }
                await drain()
                precondition(owned.logs == reference.logs, "Visible log parity")
                precondition(ownEvents == publicEvents, "Published event parity")
                let current = try text(ownedDirectory)
                let publicText = try text(publicDirectory)
                precondition(current == publicText, "File-log parity")
            }
            precondition(owned.logs == ["repeat after clear (2x)"])
            let repeated = try text(ownedDirectory)
            precondition(repeated == "repeat after clear\nrepeat after clear\n")

            for logger in pair { logger.clear() }
            await drain()
            setDividersDisabled(true)
            for index in 0..<410 {
                for logger in pair { logger.log("entry \(index)") }
            }
            await drain()
            precondition(owned.logs.count == 400 && owned.logs.first == "entry 10")
            precondition(owned.logs == reference.logs && ownEvents == publicEvents)
            // Preference is read at delivery, not captured when the logger was made.
            setDividersDisabled(false)
            for logger in pair { logger.log("grouped at runtime") }
            await drain()
            precondition(owned.logs.last == "entry 409\ngrouped at runtime")
            precondition(owned.logs == reference.logs && ownEvents == publicEvents)
            for logger in pair { logger.clear(); logger.log("UITouch filtered"); logger.log("kept") }
            await drain()
            let filtered = try text(ownedDirectory)
            precondition(filtered == "kept\n")
            for logger in pair { logger.flushToDisk(); logger.stopcapture() }
            withExtendedLifetime(subscriptions) {}
        }
        print("PASS: display/repeat/divider/clear/filter/Unicode/400-entry limits, live preferences, disk and published-event parity")
    }

    static func rotation(_ root: URL) throws {
        for mode in ["missing", "empty", "populated", "no-previous", "preservation-failure"] {
            let fixture = try directory(root, mode)
            let previous = fixture.appendingPathComponent("lara.previous.log")
            let current = fixture.appendingPathComponent("lara.log")
            let older = fixture.appendingPathComponent("lara.previous.2.log")
            let currentData = Data(repeating: 65, count: 600 * 1024)
            let previousData = Data(repeating: 66, count: 600 * 1024)
            if mode != "missing" { try (mode == "empty" ? Data() : currentData).write(to: current) }
            if mode == "preservation-failure" {
                try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: false)
            } else if mode == "populated" { try previousData.write(to: previous) }
            let logger = EagleDiagnosticLogger(disableLogDividersKey: preferenceKey, logDirectory: fixture)
            logger.flushToDisk()
            precondition(logger.logs.count == 1 && logger.logs[0].hasPrefix("lara started: "))
            let newCurrent = try Data(contentsOf: current)
            let separator = Data((logger.logs[0] + "\n").utf8)
            if mode == "preservation-failure" {
                precondition(newCurrent == currentData + separator, "Failed preservation must append, not erase")
            } else {
                precondition(newCurrent == separator)
                if mode == "populated" || mode == "no-previous" {
                    let preserved = try Data(contentsOf: previous)
                    precondition(preserved == Data(currentData.suffix(512 * 1024)))
                }
                if mode == "populated" {
                    let preservedOlder = try Data(contentsOf: older)
                    precondition(preservedOlder == Data(previousData.suffix(512 * 1024)))
                }
            }
            logger.stopcapture()
        }
        print("PASS: missing/empty/populated/previous-missing rotation, 512 KiB tails and preservation-failure append")
    }

    static func waitFor(_ value: String, logger: any LoggerProbe) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !logger.logs.contains(value) {
            precondition(Date() < deadline, "Timed out waiting for captured fixture line: \(value)")
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static func writePipe(_ text: String, descriptor: Int32) {
        let data = Data(text.utf8)
        data.withUnsafeBytes { bytes in
            precondition(Darwin.write(descriptor, bytes.baseAddress!, data.count) == data.count)
        }
    }

    static func capture(_ root: URL, publicReference: Bool) async throws {
        let logger: any LoggerProbe = publicReference
            ? PublicDiagnosticLogger(disableLogDividersKey: preferenceKey, logDirectory: root)
            : EagleDiagnosticLogger(disableLogDividersKey: preferenceKey, logDirectory: root)
        logger.clear()
        await drain()
        logger.capture()
        logger.capture() // Idempotent; never replace the original descriptors.
        writePipe("captured stdout\npartial", descriptor: STDOUT_FILENO)
        try await waitFor("captured stdout", logger: logger)
        writePipe(" finish\nUITouch ignored\n12345\ncaptured stderr\n", descriptor: STDERR_FILENO)
        try await waitFor("captured stderr", logger: logger)
        logger.flushToDisk()
        logger.stopcapture()
        precondition(logger.logs == ["captured stdout", "partial finish", "captured stderr"])
        let first = try text(root)
        precondition(first == "captured stdout\npartial finish\ncaptured stderr\n")
        logger.log("while stopped")
        await drain()
        let stopped = try text(root)
        precondition(stopped == first)
        logger.capture() // Reopen the same file, without rotation or resetting logs.
        writePipe("after reopen\n", descriptor: STDOUT_FILENO)
        try await waitFor("after reopen", logger: logger)
        logger.stopcapture()
        logger.stopcapture()
        let reopened = try text(root)
        precondition(reopened == first + "after reopen\n")
        precondition(fcntl(STDOUT_FILENO, F_GETFD) != -1 && fcntl(STDERR_FILENO, F_GETFD) != -1)
        print("PASS: \(publicReference ? "public" : "owned") fixture-only stdout/stderr, partial lines, filtering, stop/reopen and descriptor restoration")
    }

    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        switch mode {
        case "presentation": try await presentation(root)
        case "rotation": try rotation(root)
        case "owned-capture": try await capture(root, publicReference: false)
        case "public-capture": try await capture(root, publicReference: true)
        default: preconditionFailure("Unknown fixture mode")
        }
    }
}
