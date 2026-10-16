import Foundation
import Combine

@MainActor protocol HistoryHost: AnyObject {
    var log: String { get set }
    var dsprogress: Double { get }
    func logmsg(_ message: String)
    func flush(lines: [String], progress: Double?)
}

@MainActor final class HistoryRecordingSink {
    private(set) static var initializationCount = 0
    var delivery: ((String) -> Void)?
    init() { Self.initializationCount += 1 }
    func log(_ message: String) { delivery?(message) }
}
let globallogger = HistoryRecordingSink()

@MainActor private final class HistoryTrace {
    struct Event: Equatable {
        let kind: String
        let text: String
        let progress: Double
    }
    var events: [Event] = []
    func add(_ kind: String, _ host: any HistoryHost) {
        events.append(Event(kind: kind, text: host.log, progress: host.dsprogress))
    }
}

@main private enum LogHistoryChecks {
    static func waitForCount(_ count: Int, observed: () -> Int) async {
        let deadline = Date().addingTimeInterval(4)
        while observed() < count {
            precondition(Date() < deadline, "Timed out waiting for diagnostic delivery")
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        precondition(observed() == count, "Duplicate diagnostic delivery")
    }

    static func ownedConnection() async {
        precondition(HistoryRecordingSink.initializationCount == 0)
        let shared = EagleAppDiagnostics.shared
        let privateChannel = EagleAppDiagnostics.makeDelivery()
        precondition(shared === EagleAppDiagnostics.shared && shared !== privateChannel)
        precondition(shared.history !== privateChannel.history)
        precondition(HistoryRecordingSink.initializationCount == 0, "Creating diagnostics eagerly opened the logger")

        var messages: [String] = []
        globallogger.delivery = { message in
            MainActor.assertIsolated()
            messages.append(message)
            precondition(shared.history.text == messages.joined(separator: "\n") + "\n",
                         "History must update once, before the logger")
        }
        // No manager host exists yet: the owned route retains this early message.
        EagleAppDiagnostics.log("before manager")
        precondition(messages.isEmpty && shared.history.text.isEmpty)
        await waitForCount(1, observed: { messages.count })
        let manager = OwnedHistoryHost.shared
        precondition(manager.log == "before manager\n")
        var beforeChange: [String] = []
        let observation = manager.objectWillChange.sink { _ in beforeChange.append(manager.log) }

        EagleAppDiagnostics.log("gallery")
        CurrentArchiveDiagnostics.log("zip")
        manager.logmsg("manager")
        precondition(messages.count == 1)
        await waitForCount(4, observed: { messages.count })
        precondition(Set(messages.dropFirst()) == Set(["gallery", "zip", "manager"]))
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    if index.isMultiple(of: 2) { EagleAppDiagnostics.log("background-\(index)") }
                    else { CurrentArchiveDiagnostics.log("background-\(index)") }
                }
            }
        }
        await waitForCount(68, observed: { messages.count })
        precondition(Set(messages.suffix(64)) == Set((0..<64).map { "background-\($0)" }))
        precondition(manager.log == shared.history.text && privateChannel.history.text.isEmpty)
        var expectedBefore: [String] = []
        var accumulated = messages[0] + "\n"
        for message in messages.dropFirst() {
            expectedBefore.append(accumulated)
            accumulated += message + "\n"
        }
        precondition(beforeChange == expectedBefore, "Shared manager notifications changed order or count")
        observation.cancel()

        let firstPrivate = OwnedHistoryHost()
        let secondPrivate = OwnedHistoryHost()
        var privateMessages: [String] = []
        globallogger.delivery = { privateMessages.append($0) }
        firstPrivate.logmsg("private one")
        secondPrivate.logmsg("private two")
        privateChannel.enqueue("direct channel")
        await waitForCount(3, observed: { privateMessages.count })
        precondition(firstPrivate.log == "private one\n" && secondPrivate.log == "private two\n")
        precondition(privateChannel.history.text == "direct channel\n")
        precondition(manager.log == accumulated)
        manager.log = ""
        precondition(shared.history.text.isEmpty && firstPrivate.log == "private one\n")
        globallogger.delivery = nil
        print("PASS: lazy logger, pre-manager delivery, 68 shared/3 isolated messages, background calls and observer order")
    }

    static func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    static func trace<Host: HistoryHost & ObservableObject>(
        _ host: Host, seed: String
    ) async -> [HistoryTrace.Event] {
        let trace = HistoryTrace()
        let observation = host.objectWillChange.sink { _ in trace.add("willChange", host) }
        globallogger.delivery = { trace.add("file:\($0)", host) }
        defer { globallogger.delivery = nil; observation.cancel() }
        host.log = seed
        trace.add("seed", host)
        host.logmsg("")
        // Preserve the original queued delivery, not an immediate append.
        precondition(host.log == seed)
        trace.add("before queue", host)
        await drain()
        trace.add("after queue", host)
        host.logmsg("same")
        host.logmsg("same")
        host.logmsg("Águila 🦅\nsecond line")
        await drain()
        trace.add("queued sequence", host)
        host.flush(lines: ["batch first", "batch second"], progress: 0.5)
        trace.add("batch", host)
        host.flush(lines: [], progress: 0.75)
        trace.add("progress only", host)
        host.flush(lines: [], progress: nil)
        trace.add("empty flush", host)
        host.flush(lines: ["", ""], progress: nil)
        trace.add("blank lines", host)
        let iconWriter = IconHistoryWriter(host)
        iconWriter.icon_logmsg("direct icon")
        iconWriter.unzip_logmsg("direct zip")
        await drain()
        trace.add("direct consumers", host)
        host.log = host.log
        trace.add("same-value assignment", host)
        // Prepare's existing clear is a direct assignment, with no file write.
        host.log = ""
        trace.add("clear", host)
        host.logmsg("after clear")
        await drain()
        trace.add("reuse", host)
        return trace.events
    }

    static func lifetime<Host: HistoryHost>(_ make: () -> Host) async {
        var host: Host? = make()
        weak let weakHost = host
        host?.logmsg("retained until queued delivery")
        host = nil
        precondition(weakHost != nil)
        await drain()
        precondition(weakHost == nil, "Observation bridge retained its manager")
    }

    static func main() async {
        await ownedConnection()
        let history = EagleLogHistory()
        precondition(history.text.isEmpty)
        var published: [String] = []
        let publisher = history.$text.sink { published.append($0) }
        history.append("one")
        history.append("")
        precondition(history.text == "one\n\n" && published == ["", "one\n", "one\n\n"])
        publisher.cancel()

        let seeds = [
            "", "prefix\n", String(repeating: "x", count: 256 * 1024 - 2),
            String(repeating: "x", count: 256 * 1024 - 1),
            String(repeating: "x", count: 256 * 1024),
            String(repeating: "x", count: 256 * 1024 + 1),
            String(repeating: "é", count: 128 * 1024),
            String(repeating: "🦅", count: 70_000),
            String(repeating: "e\u{301}", count: 90_000),
        ]
        var eventCount = 0
        for seed in seeds {
            let expected = await trace(PublicHistoryHost(), seed: seed)
            let actual = await trace(OwnedHistoryHost(), seed: seed)
            precondition(actual == expected, "History/notification/file-delivery trace diverged")
            eventCount += actual.count
        }

        // Independent expectations for the public mixed-unit truncation policy.
        history.text = String(repeating: "x", count: 256 * 1024 - 1)
        history.append("")
        precondition(history.text.utf8.count == 256 * 1024)
        history.append("")
        precondition(history.text.count == 128 * 1024 && history.text.hasSuffix("\n\n"))
        history.text = String(repeating: "🦅", count: 70_000)
        history.append("")
        precondition(history.text.count == 70_001 && history.text.utf8.count > 256 * 1024)

        let first = OwnedHistoryHost()
        let second = OwnedHistoryHost()
        first.logmsg("first")
        second.logmsg("second")
        await drain()
        precondition(first.log == "first\n" && second.log == "second\n")
        first.log = ""
        precondition(second.log == "second\n")
        // Direct writes keep their historical unbounded behavior until the next
        // bounded message; routing them through append() would be a regression.
        first.log = String(repeating: "x", count: 300 * 1024)
        let icons = IconHistoryWriter(first)
        icons.icon_logmsg("kept directly")
        await drain()
        precondition(first.log.utf8.count > 300 * 1024)
        first.logmsg("bounded next")
        await drain()
        precondition(first.log.count == 128 * 1024)
        await lifetime { PublicHistoryHost() }
        await lifetime { OwnedHistoryHost() }
        print("PASS: \(seeds.count) public-reference scenarios / \(eventCount) ordered events, queue timing, batch/progress and icon/ZIP writes")
        print("PASS: limits/Unicode, direct writes, published values, instance isolation and queued-delivery lifetime")
    }
}
