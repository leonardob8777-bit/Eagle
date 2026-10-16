import Foundation

final class LogContext {
    var events: [String] = []
    var date: Date
    var initialDelay: TimeInterval = 0
    var initialized = false
    init(_ date: Date) { self.date = date }
    func now() -> Date {
        events.append("clock")
        return date
    }
    func sink() -> LogSink {
        events.append("receiver")
        if !initialized {
            date = date.addingTimeInterval(initialDelay)
            initialized = true
        }
        return LogSink(context: self)
    }
}

struct LogSink {
    let context: LogContext
    func log(_ message: String) { context.events.append("deliver:" + message) }
}

func emit(_ owned: Bool, _ context: LogContext, _ stage: String, _ detail: String?) {
    if owned {
        if let detail {
            EagleAuraStudioDiagnosticLog.log(stage, detail, now: context.now,
                                            makeDelivery: { context.sink().log })
        } else {
            EagleAuraStudioDiagnosticLog.log(stage, now: context.now,
                                            makeDelivery: { context.sink().log })
        }
    } else {
        let reference = PublicDiagnosticLog(context: context)
        if let detail { reference.log(stage, detail) }
        else { reference.log(stage) }
    }
}

func trace(_ owned: Bool, _ stage: String, _ detail: String?, _ date: Date) -> [String] {
    let context = LogContext(date)
    emit(owned, context, stage, detail)
    precondition(context.events.count == 3)
    precondition(Array(context.events.prefix(2)) == ["receiver", "clock"])
    return context.events
}

func runCases() -> Int {
    let dates: [TimeInterval] = [-2208988800, -86400.75, -1, 0, 0.123, 0.999,
                                1, 59.999, 60, 86400, 951782400, 1709251199.999,
                                1791849600.125, 2147483647, 2147483648, 4102444800]
    let stages = ["", "begin", "verified", "failure", "etapa ñ 🦅", "line\nbreak", " ", "a=b[]"]
    let details = ["", " ", "ok", "áé🦅", "line\r\nnext", "stage=other", "[] ()",
                   "\t", String(repeating: "x", count: 4096)]
    var cases = 0
    for timestamp in dates {
        let date = Date(timeIntervalSince1970: timestamp)
        for stage in stages {
            for detail in details {
                let expected = trace(false, stage, detail, date)
                let actual = trace(true, stage, detail, date)
                precondition(actual == expected)
                cases += 1
            }
            precondition(trace(true, stage, nil, date) == trace(false, stage, nil, date))
            cases += 1
        }
    }
    let zero = Date(timeIntervalSince1970: 0)
    precondition(trace(true, "ready", "", zero) == [
        "receiver", "clock", "deliver:[1970-01-01T00:00:00.000Z] (eagle.aura.apply) stage=ready"
    ])
    precondition(trace(true, "ready", "done", zero) == [
        "receiver", "clock", "deliver:[1970-01-01T00:00:00.000Z] (eagle.aura.apply) stage=ready done"
    ])
    // Repeated stages must still reach the existing sink; no new deduplication/cache.
    let owned = LogContext(zero)
    let reference = LogContext(zero)
    for timestamp in [0.0, 1.0, 2.0] {
        owned.date = Date(timeIntervalSince1970: timestamp)
        reference.date = owned.date
        emit(true, owned, "repeated", nil)
        emit(false, reference, "repeated", nil)
    }
    precondition(owned.events == reference.events && owned.events.count == 9)
    precondition(owned.events[2].contains("00:00:00.000Z") && owned.events[5].contains("00:00:01.000Z"))
    precondition(owned.events[8].contains("00:00:02.000Z"))
    // A lazy logger may take time to initialize. Public code resolves it before Date().
    let delayed = LogContext(zero)
    let delayedReference = LogContext(zero)
    delayed.initialDelay = 7
    delayedReference.initialDelay = 7
    emit(true, delayed, "first", nil)
    emit(false, delayedReference, "first", nil)
    precondition(delayed.events == delayedReference.events)
    precondition(delayed.events[2].contains("00:00:07.000Z"))
    return cases + 6
}

@main struct VerifyDiagnosticLog {
    static func main() async {
        let direct = runCases()
        let detached = await Task.detached { runCases() }.value
        precondition(direct == detached)
        print("PASS: \(direct) direct and \(detached) detached diagnostic cases; exact public text, default detail, receiver-before-clock-before-delivery including lazy initialization, repeated calls and timestamp boundaries")
    }
}
