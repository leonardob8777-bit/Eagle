import Foundation

enum LifecyclePhase: CaseIterable {
    case active, background, inactive, future
}

struct LifecycleSnapshot: Equatable {
    var started = false
    var pending = false
    var access = false
    var applying = false
    var download: String? = nil
    var begins = 0
}

struct LifecycleEvent: Equatable {
    let name: String
    let state: LifecycleSnapshot
}

@MainActor
class LifecycleStorage {
    @MainActor
    struct Download {
        unowned let owner: LifecycleStorage
        var downloadingID: String? {
            owner.record("download-read")
            return owner.stored.download
        }
    }

    var stored = LifecycleSnapshot()
    var events: [LifecycleEvent] = []
    var mutationAfterPendingWrite: LifecycleSnapshot?
    @MainActor init() {}

    func record(_ name: String) {
        events.append(LifecycleEvent(name: name, state: stored))
    }
    var visitStarted: Bool {
        get { record("visit-read"); return stored.started }
        set { stored.started = newValue; record("visit-write:\(newValue)") }
    }
    var needsNewVisitOnResume: Bool {
        get { record("pending-read"); return stored.pending }
        set {
            stored.pending = newValue
            record("pending-write:\(newValue)")
            if let mutation = mutationAfterPendingWrite {
                stored.started = mutation.started
                stored.access = mutation.access
                stored.applying = mutation.applying
                stored.download = mutation.download
                record("pending-setter-mutation")
            }
        }
    }
    var showAccessSetup: Bool { record("access-read"); return stored.access }
    var isApplying: Bool { record("applying-read"); return stored.applying }
    var remoteGallery: Download { Download(owner: self) }
    func beginGalleryVisit() {
        record("begin")
        stored.begins += 1
        visitStarted = true
    }

    func appear() { preconditionFailure("Fixture override required") }
    func disappear() { preconditionFailure("Fixture override required") }
    func change(_ phase: LifecyclePhase) { preconditionFailure("Fixture override required") }
}

@main
@MainActor
private enum LifecycleChecks {
    enum Action {
        case appear, disappear, change(LifecyclePhase)
        case access(Bool), applying(Bool), download(String?)
    }

    struct Step {
        let action: Action
        let names: [String]
        let started: Bool
        let pending: Bool
        let begins: Int
    }

    static let beginNames = ["begin", "visit-write:true"]
    static let allowedResumeNames = [
        "pending-read", "pending-write:false", "visit-read", "access-read",
        "applying-read", "download-read", "begin", "visit-write:true",
    ]

    static func fixtures(_ state: LifecycleSnapshot) -> [LifecycleStorage] {
        let result: [LifecycleStorage] = [PreviousLifecycleFixture(), OwnedLifecycleFixture()]
        for fixture in result { fixture.stored = state }
        return result
    }

    static func perform(_ action: Action, on fixture: LifecycleStorage) {
        switch action {
        case .appear: fixture.appear()
        case .disappear: fixture.disappear()
        case .change(let phase): fixture.change(phase)
        // These model external UI/operation state changes between callbacks.
        case .access(let value): fixture.stored.access = value
        case .applying(let value): fixture.stored.applying = value
        case .download(let value): fixture.stored.download = value
        }
    }

    static func assertEquivalent(_ pair: [LifecycleStorage], _ label: String) {
        precondition(pair[0].events == pair[1].events,
                     "Previous/owned event names or state snapshots differ: \(label)")
        precondition(pair[0].stored == pair[1].stored,
                     "Previous/owned final state differs: \(label)")
    }

    static func assertCase(_ pair: [LifecycleStorage], action: Action,
                           names: [String], final: LifecycleSnapshot, label: String) {
        for fixture in pair {
            perform(action, on: fixture)
            precondition(fixture.events.map(\.name) == names,
                         "Unexpected reads, writes or effects: \(label): \(fixture.events.map(\.name))")
            precondition(fixture.stored == final, "Unexpected final state: \(label)")
        }
        assertEquivalent(pair, label)
    }

    static func resumeGuardNames(_ state: LifecycleSnapshot) -> [String] {
        var names = ["visit-read"]
        if !state.started { return names }
        names.append("access-read")
        if state.access { return names }
        names.append("applying-read")
        if state.applying { return names }
        names.append("download-read")
        if state.download == nil { names += beginNames }
        return names
    }

    static func canResume(_ state: LifecycleSnapshot) -> Bool {
        state.started && !state.access && !state.applying && state.download == nil
    }

    static func allStates() -> [LifecycleSnapshot] {
        var result: [LifecycleSnapshot] = []
        for started in [false, true] {
            for pending in [false, true] {
                for access in [false, true] {
                    for applying in [false, true] {
                        for download in [nil, "", "in-progress"] as [String?] {
                            result.append(LifecycleSnapshot(started: started, pending: pending,
                                                            access: access, applying: applying,
                                                            download: download))
                        }
                    }
                }
            }
        }
        return result
    }

    static func checkExhaustiveCallbacks() -> (scene: Int, appear: Int, disappear: Int) {
        var sceneCases = 0
        var appearCases = 0
        var disappearCases = 0
        for initial in allStates() {
            var appeared = initial
            if !initial.started { appeared.started = true; appeared.begins += 1 }
            assertCase(fixtures(initial), action: .appear,
                       names: ["visit-read"] + (initial.started ? [] : beginNames),
                       final: appeared, label: "appear \(initial)")
            appearCases += 1

            var disappeared = initial
            if !initial.access { disappeared.started = false }
            assertCase(fixtures(initial), action: .disappear,
                       names: ["access-read"] + (initial.access ? [] : ["visit-write:false"]),
                       final: disappeared, label: "disappear \(initial)")
            disappearCases += 1

            for phase in LifecyclePhase.allCases {
                var names: [String] = []
                var final = initial
                switch phase {
                case .background:
                    names = ["visit-read"]
                    if initial.started {
                        names.append("pending-write:true")
                        final.pending = true
                    }
                case .active:
                    names = ["pending-read"]
                    if initial.pending {
                        names += ["pending-write:false"] + resumeGuardNames(initial)
                        final.pending = false
                        if canResume(initial) { final.begins += 1 }
                    }
                case .inactive, .future:
                    break
                }
                assertCase(fixtures(initial), action: .change(phase), names: names,
                           final: final, label: "\(phase) \(initial)")
                sceneCases += 1
            }
        }
        precondition(sceneCases == 192 && appearCases == 48 && disappearCases == 48)
        return (sceneCases, appearCases, disappearCases)
    }

    static func checkSetterMutations() -> Int {
        // Every pre-write guard combination is paired with every post-write
        // combination. Capturing even one guard before consuming the pending
        // flag changes either a read snapshot, the short circuit or the effect.
        let guards = allStates().filter { $0.pending }
        var cases = 0
        for initial in guards {
            for mutation in guards {
                let pair = fixtures(initial)
                for fixture in pair { fixture.mutationAfterPendingWrite = mutation }
                var final = mutation
                final.pending = false
                if canResume(mutation) { final.begins += 1 }
                let names = ["pending-read", "pending-write:false", "pending-setter-mutation"]
                    + resumeGuardNames(mutation)
                let label = "pending setter \(initial) -> \(mutation)"
                assertCase(pair, action: .change(.active), names: names, final: final, label: label)
                for fixture in pair {
                    var consumed = initial
                    consumed.pending = false
                    precondition(fixture.events[1].state == consumed,
                                 "Pending must be cleared before setter side effects: \(label)")
                    var mutated = mutation
                    mutated.pending = false
                    precondition(fixture.events[2].state == mutated && fixture.events[3].state == mutated,
                                 "Resume guards must observe post-write state: \(label)")
                }
                cases += 1
            }
        }
        precondition(cases == 576)
        return cases
    }

    static func checkTrace(_ label: String, initial: LifecycleSnapshot, steps: [Step]) -> Int {
        let pair = fixtures(initial)
        for (index, step) in steps.enumerated() {
            for fixture in pair {
                let previousEventCount = fixture.events.count
                perform(step.action, on: fixture)
                let names = fixture.events.dropFirst(previousEventCount).map(\.name)
                precondition(names == step.names, "Unexpected trace events: \(label), step \(index): \(names)")
                precondition(fixture.stored.started == step.started &&
                             fixture.stored.pending == step.pending && fixture.stored.begins == step.begins,
                             "Unexpected trace checkpoint: \(label), step \(index)")
            }
            assertEquivalent(pair, "\(label), step \(index)")
        }
        return steps.count
    }

    static func checkTraces() -> (traces: Int, steps: Int) {
        var traces = 0
        var steps = 0
        steps += checkTrace("access modal preserves visit and consumes blocked resume", initial: .init(), steps: [
            .init(action: .appear, names: ["visit-read"] + beginNames, started: true, pending: false, begins: 1),
            .init(action: .access(true), names: [], started: true, pending: false, begins: 1),
            .init(action: .disappear, names: ["access-read"], started: true, pending: false, begins: 1),
            .init(action: .appear, names: ["visit-read"], started: true, pending: false, begins: 1),
            .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 1),
            .init(action: .change(.inactive), names: [], started: true, pending: true, begins: 1),
            .init(action: .change(.active), names: ["pending-read", "pending-write:false", "visit-read", "access-read"], started: true, pending: false, begins: 1),
            .init(action: .access(false), names: [], started: true, pending: false, begins: 1),
            .init(action: .change(.active), names: ["pending-read"], started: true, pending: false, begins: 1),
            .init(action: .appear, names: ["visit-read"], started: true, pending: false, begins: 1),
            .init(action: .disappear, names: ["access-read", "visit-write:false"], started: false, pending: false, begins: 1),
            .init(action: .appear, names: ["visit-read"] + beginNames, started: true, pending: false, begins: 2),
        ])
        traces += 1

        steps += checkTrace("background inactive active and repeated writes", initial: .init(started: true), steps: [
            .init(action: .change(.inactive), names: [], started: true, pending: false, begins: 0),
            .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 0),
            .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 0),
            .init(action: .change(.inactive), names: [], started: true, pending: true, begins: 0),
            .init(action: .change(.future), names: [], started: true, pending: true, begins: 0),
            .init(action: .change(.active), names: allowedResumeNames, started: true, pending: false, begins: 1),
            .init(action: .change(.active), names: ["pending-read"], started: true, pending: false, begins: 1),
            .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 1),
            .init(action: .disappear, names: ["access-read", "visit-write:false"], started: false, pending: true, begins: 1),
            .init(action: .disappear, names: ["access-read", "visit-write:false"], started: false, pending: true, begins: 1),
            .init(action: .change(.active), names: ["pending-read", "pending-write:false", "visit-read"], started: false, pending: false, begins: 1),
            .init(action: .appear, names: ["visit-read"] + beginNames, started: true, pending: false, begins: 2),
        ])
        traces += 1

        steps += checkTrace("unstarted background and busy appearance", initial: .init(access: true, applying: true, download: ""), steps: [
            .init(action: .change(.background), names: ["visit-read"], started: false, pending: false, begins: 0),
            .init(action: .change(.active), names: ["pending-read"], started: false, pending: false, begins: 0),
            .init(action: .appear, names: ["visit-read"] + beginNames, started: true, pending: false, begins: 1),
            .init(action: .appear, names: ["visit-read"], started: true, pending: false, begins: 1),
        ])
        traces += 1

        steps += checkTrace("appearance preserves an already pending resume", initial: .init(pending: true), steps: [
            .init(action: .change(.background), names: ["visit-read"], started: false, pending: true, begins: 0),
            .init(action: .appear, names: ["visit-read"] + beginNames, started: true, pending: true, begins: 1),
            .init(action: .change(.active), names: allowedResumeNames, started: true, pending: false, begins: 2),
            .init(action: .appear, names: ["visit-read"], started: true, pending: false, begins: 2),
        ])
        traces += 1

        steps += checkTrace("applying consumes pending without retry", initial: .init(started: true, applying: true), steps: [
            .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 0),
            .init(action: .change(.active), names: ["pending-read", "pending-write:false", "visit-read", "access-read", "applying-read"], started: true, pending: false, begins: 0),
            .init(action: .applying(false), names: [], started: true, pending: false, begins: 0),
            .init(action: .change(.active), names: ["pending-read"], started: true, pending: false, begins: 0),
            .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 0),
            .init(action: .change(.active), names: allowedResumeNames, started: true, pending: false, begins: 1),
        ])
        traces += 1

        for download in ["", "in-progress"] {
            steps += checkTrace("download \(String(reflecting: download)) consumes pending without retry",
                                initial: .init(started: true, download: download), steps: [
                .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 0),
                .init(action: .change(.active), names: Array(allowedResumeNames.dropLast(2)), started: true, pending: false, begins: 0),
                .init(action: .download(nil), names: [], started: true, pending: false, begins: 0),
                .init(action: .change(.active), names: ["pending-read"], started: true, pending: false, begins: 0),
                .init(action: .change(.background), names: ["visit-read", "pending-write:true"], started: true, pending: true, begins: 0),
                .init(action: .change(.active), names: allowedResumeNames, started: true, pending: false, begins: 1),
            ])
            traces += 1
        }
        precondition(traces == 7 && steps == 50)
        return (traces, steps)
    }

    static func main() {
        let callbacks = checkExhaustiveCallbacks()
        let mutations = checkSetterMutations()
        let traces = checkTraces()
        let pairs = callbacks.scene + callbacks.appear + callbacks.disappear + mutations
        print("PASS: \(callbacks.scene) exhaustive scene cases, \(callbacks.appear) appearance and \(callbacks.disappear) disappearance cases, \(mutations) post-pending-write mutation cases; \(pairs * 2) previous/owned single-callback runs")
        print("PASS: \(traces.traces) lifecycle traces / \(traces.steps) steps / \(traces.steps * 2) previous/owned step runs; complete event/state equivalence, lazy guards, modal preservation, repeated writes, nil/empty downloads and consumed blocked resumes")
    }
}
