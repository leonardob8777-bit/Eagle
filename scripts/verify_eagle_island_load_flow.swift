import Foundation

enum Failure: Error { case transport }

@MainActor class Host {
    var events: [String] = []
    var busy = false
    var failed = false
    var items = ["old"]
    var selected = "old"
    var payload: [String] = []
    var outcome = 0
    var suspend = false
    var cancelAtReturn = false
    var continuation: CheckedContinuation<Void, Never>?
    var completed = false
    var loading: Bool {
        get { events.append("readLoading:\(busy)"); return busy }
        set { events.append("loading:\(newValue)"); busy = newValue }
    }
    var loadFailed: Bool {
        get { failed }
        set { events.append("failed:\(newValue)"); failed = newValue }
    }
    var liveThemes: [String] {
        get { items }
        set { events.append("themes:\(newValue)"); items = newValue }
    }
    func restoreSelection() {
        events.append("restore:\(items):\(failed):\(busy)")
        if !items.contains(selected) { selected = items.first ?? "" }
    }
    func synchronizeSelection() { events.append("sync:\(selected):\(busy)") }
    func run(_ force: Bool) async { fatalError("abstract") }
    func fetch(force: Bool) async throws -> [String] {
        events.append("fetch:\(force):\(Task.isCancelled)")
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if cancelAtReturn { withUnsafeCurrentTask { $0?.cancel() } }
        events.append("return:\(outcome):\(Task.isCancelled)")
        if outcome == 1 { throw Failure.transport }
        if outcome == 2 { throw CancellationError() }
        return payload
    }
    var snapshot: String { "\(busy)|\(failed)|\(items)|\(selected)" }
}

@MainActor func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    fatalError("fixture did not reach its deterministic checkpoint")
}

@MainActor func exercise(_ host: Host, busy: Bool, failed: Bool, payload: [String],
                        outcome: Int, force: Bool, cancellation: Int, suspend: Bool) async -> ([String], String) {
    host.busy = busy
    host.failed = failed
    host.payload = payload
    host.outcome = outcome
    host.suspend = suspend
    host.cancelAtReturn = cancellation == 3
    let task = Task { @MainActor in
        await host.run(force)
        host.completed = true
    }
    if cancellation == 1 { task.cancel() }
    await waitUntil { host.completed || host.continuation != nil }
    if let continuation = host.continuation {
        // A second refresh shares the same state and must be ignored while suspended.
        let prefix = host.events
        await host.run(!force)
        precondition(host.events == prefix + ["readLoading:true"])
        precondition(host.busy && host.items == ["old"] && host.failed == failed)
        if cancellation == 2 { task.cancel() }
        host.continuation = nil
        continuation.resume()
    }
    await task.value
    if busy {
        precondition(host.events == ["readLoading:true"])
        precondition(host.busy && host.items == ["old"] && host.failed == failed)
    } else {
        precondition(!host.busy && host.events.last == "loading:false")
        let cancelled = cancellation == 1 || cancellation == 3 || (cancellation == 2 && suspend)
        if cancelled {
            precondition(host.items == ["old"] && host.failed == failed)
            precondition(!host.events.contains { $0.hasPrefix("restore:") || $0.hasPrefix("sync:") })
        } else if outcome != 0 {
            // A thrown CancellationError alone does not mark the task cancelled.
            precondition(host.failed && host.items == ["old"])
        } else {
            precondition(!host.failed && host.items == payload)
            precondition(host.events.suffix(4).first == "failed:false")
            precondition(host.events.contains { $0.hasPrefix("restore:") })
            precondition(host.events[host.events.count - 2].hasPrefix("sync:"))
        }
    }
    return (host.events, host.snapshot)
}

@MainActor func retrySequence(_ host: Host, force: Bool) async -> ([String], String) {
    host.outcome = 1
    await host.run(force)
    precondition(host.failed && !host.busy && host.items == ["old"])
    host.outcome = 0
    host.payload = ["new", "live"]
    await host.run(!force)
    precondition(!host.failed && !host.busy && host.items == host.payload && host.selected == "new")
    host.payload = []
    await host.run(force)
    precondition(!host.failed && host.items.isEmpty && host.selected.isEmpty)
    return (host.events, host.snapshot)
}

@main struct Main {
    @MainActor static func main() async {
        var count = 0
        var events = 0
        for busy in [false, true] {
            for failed in [false, true] {
                for payload in [[], ["old"], ["new", "live"], ["live", "old", "static"]] {
                    for outcome in 0..<3 {
                        for force in [false, true] {
                            for cancellation in 0..<4 {
                                for suspend in [false, true] {
                                    let a = await exercise(PublicHost(), busy: busy, failed: failed, payload: payload,
                                                           outcome: outcome, force: force, cancellation: cancellation, suspend: suspend)
                                    let b = await exercise(OwnedHost(), busy: busy, failed: failed, payload: payload,
                                                           outcome: outcome, force: force, cancellation: cancellation, suspend: suspend)
                                    precondition(a.0 == b.0 && a.1 == b.1, "public/owned mismatch")
                                    count += 1
                                    events += b.0.count
                                }
                            }
                        }
                    }
                }
            }
        }
        for force in [false, true] {
            let a = await retrySequence(PublicHost(), force: force)
            let b = await retrySequence(OwnedHost(), force: force)
            precondition(a.0 == b.0 && a.1 == b.1)
        }
        print("PASS: \(count) public/owned load scenarios, \(events) ordered events, overlapping refreshes and 2 retry sequences")
    }
}
