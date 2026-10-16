import Foundation

enum Context { @TaskLocal static var marker = "outside" }

@MainActor final class IslandGalleryArtwork {
    unowned let host: Host
    let kind: Int
    init(_ host: Host, _ kind: Int) { self.host = host; self.kind = kind }
    var liveTheme: String? {
        host.events.append("theme:\(kind)")
        return kind == 1 ? "live" : kind == 2 ? "remote-static" : nil
    }
    var style: String { host.events.append("style:\(kind)"); return kind == 3 ? "remote-fallback" : "built-in" }
}

@MainActor final class IslandGalleryApplyResult {
    unowned let host: Host
    let value: Bool
    let text: String
    init(_ host: Host) { self.host = host; value = host.success; text = host.text }
    var succeeded: Bool { host.events.append("success:\(value)"); return value }
    var message: String { host.events.append("message:\(text)"); return text }
}

@MainActor struct Executor {
    unowned let host: Host
    func applyLive(_ theme: String, shadowIntensity: Double) async -> IslandGalleryApplyResult {
        await host.execute("remote:\(theme):\(shadowIntensity)")
    }
    func apply(_ style: String, shadowIntensity: Double) async -> IslandGalleryApplyResult {
        await host.execute("style:\(style):\(shadowIntensity)")
    }
    func restore() async -> IslandGalleryApplyResult { await host.execute("restore") }
}

@MainActor struct Feedback {
    enum Kind: String { case success, error }
    unowned let host: Host
    func notificationOccurred(_ kind: Kind) {
        precondition(!host.busy)
        host.events.append("feedback:\(kind):\(host.busy)")
    }
}

@MainActor struct Notifications {
    unowned let host: Host
    func result(_ success: Bool, title: String, message: String) {
        precondition(!host.busy && title == "Island Gallery")
        host.events.append("notice:\(success):\(title):\(message):\(host.busy)")
        host.finished += 1
    }
}

@MainActor class Host {
    var events: [String] = []
    var busy = false
    var selected = -1
    var shadow = 0.72
    var success = true
    var text = ""
    var suspend = false
    var cancelExecution = false
    var finished = 0
    var continuation: CheckedContinuation<Void, Never>?
    var applying: Bool {
        get { events.append("busyRead:\(busy)"); return busy }
        set { events.append("busy:\(newValue)"); busy = newValue }
    }
    var shadowIntensity: Double { events.append("intensity:\(shadow)"); return shadow }
    var executor: Executor { events.append("executor"); return Executor(host: self) }
    var feedbackGenerator: Feedback { events.append("generator"); return Feedback(host: self) }
    var notifications: Notifications { events.append("notifications"); return Notifications(host: self) }
    func select(_ item: IslandGalleryArtwork) {
        events.append("select:\(item.kind):\(busy)")
        precondition(!busy)
        selected = item.kind
    }
    func start(_ item: IslandGalleryArtwork?) { fatalError("abstract") }
    func execute(_ request: String) async -> IslandGalleryApplyResult {
        events.append("execute:\(request):\(Task.isCancelled):\(Context.marker)")
        precondition(busy && !Task.isCancelled && Context.marker == "caller")
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if cancelExecution { withUnsafeCurrentTask { $0?.cancel() } }
        events.append("return:\(Task.isCancelled)")
        return IslandGalleryApplyResult(self)
    }
    var snapshot: String { "\(busy)|\(selected)|\(finished)" }
}

@MainActor func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    fatalError("fixture failed to reach checkpoint")
}

@MainActor func exercise(_ host: Host, kind: Int, busy: Bool, success: Bool, shadow: Double,
                        suspend: Bool, cancelCaller: Bool, cancelExecution: Bool) async -> ([String], String) {
    host.busy = busy
    host.success = success
    host.text = success ? "Applied ✓" : "No cambió — error"
    host.suspend = suspend
    host.cancelExecution = cancelExecution
    let caller = Task { @MainActor in
        Context.$marker.withValue("caller") {
            host.start(kind == 4 ? nil : IslandGalleryArtwork(host, kind))
            if !busy {
                // Change before the child task runs: intensity must not be snapshotted early.
                host.shadow = shadow
                let prefix = host.events
                host.start(nil)
                host.start(IslandGalleryArtwork(host, 1))
                precondition(host.events == prefix + ["busyRead:true", "busyRead:true"])
            }
        }
    }
    if cancelCaller { caller.cancel() }
    await caller.value
    if busy {
        precondition(host.events == ["busyRead:true"] && host.selected == -1 && host.finished == 0)
    } else {
        await waitUntil { host.continuation != nil || host.finished == 1 }
        if let pending = host.continuation {
            let prefix = host.events
            host.start(IslandGalleryArtwork(host, 0))
            host.start(nil)
            precondition(host.events == prefix + ["busyRead:true", "busyRead:true"])
            host.shadow = 0.123 // Must not change arguments already delivered to executor.
            host.continuation = nil
            pending.resume()
        }
        await waitUntil { host.finished == 1 }
        precondition(!host.busy && host.selected == (kind == 4 ? -1 : kind))
        precondition(host.events.filter { $0.hasPrefix("execute:") }.count == 1)
        let ending = Array(host.events.suffix(8))
        precondition(ending == ["busy:false", "generator", "success:\(success)",
                              "feedback:\(success ? "success" : "error"):false", "notifications",
                              "success:\(success)", "message:\(host.text)",
                              "notice:\(success):Island Gallery:\(host.text):false"])
        if kind == 4 {
            precondition(!host.events.contains { $0.hasPrefix("theme:") || $0.hasPrefix("intensity:") })
        } else {
            precondition(host.events.contains("intensity:\(shadow)"))
            let expected = kind == 1 ? "remote:live" : kind == 2 ? "remote:remote-static" :
                kind == 3 ? "style:remote-fallback" : "style:built-in"
            precondition(host.events.contains("execute:\(expected):\(shadow):false:caller"))
        }
    }
    return (host.events, host.snapshot)
}

@MainActor func sequence(_ host: Host, reversed: Bool) async -> ([String], String) {
    let kinds = reversed ? [4, 2, 4, 0, 3, 1, 4] : [0, 1, 4, 2, 3, 4, 1]
    for (index, kind) in kinds.enumerated() {
        host.success = index % 2 == 0
        host.text = "step-\(index)"
        Context.$marker.withValue("caller") {
            host.start(kind == 4 ? nil : IslandGalleryArtwork(host, kind))
        }
        await waitUntil { host.finished == index + 1 }
        precondition(!host.busy)
    }
    return (host.events, host.snapshot)
}

@main struct Main {
    @MainActor static func main() async {
        var count = 0
        var eventCount = 0
        for kind in 0..<5 {
            for busy in [false, true] {
                for success in [false, true] {
                    for shadow in [0.0, 0.91, Double.nan, Double.infinity] {
                        for suspend in [false, true] {
                            for cancelled in [false, true] {
                                for cancelExecution in [false, true] {
                                    let a = await exercise(PublicHost(), kind: kind, busy: busy, success: success,
                                                           shadow: shadow, suspend: suspend, cancelCaller: cancelled,
                                                           cancelExecution: cancelExecution)
                                    let b = await exercise(OwnedHost(), kind: kind, busy: busy, success: success,
                                                           shadow: shadow, suspend: suspend, cancelCaller: cancelled,
                                                           cancelExecution: cancelExecution)
                                    precondition(a.0 == b.0 && a.1 == b.1, "action parity mismatch")
                                    count += 1
                                    eventCount += b.0.count
                                }
                            }
                        }
                    }
                }
            }
        }
        for reversed in [false, true] {
            let a = await sequence(PublicHost(), reversed: reversed)
            let b = await sequence(OwnedHost(), reversed: reversed)
            precondition(a.0 == b.0 && a.1 == b.1)
        }
        print("PASS: \(count) public/owned action scenarios, \(eventCount) ordered events and 14 sustained mixed actions")
    }
}
