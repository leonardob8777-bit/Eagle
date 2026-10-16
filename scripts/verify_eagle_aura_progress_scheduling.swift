import Foundation

@MainActor final class State {
    var activeID: String? = "run"
    var finished = false
    var deadline = false
    var stage = ""
    var blocked = false
    var locked = false
    var events: [String] = []
    var works: [DispatchWorkItem] = []
    var delays: [Int] = []
    func progress() -> EagleAuraStudioStepProgress {
        EagleAuraStudioStepProgress(
            operationID: "run",
            step: EagleAuraStudioOperationStep(flag: 32, englishName: "Dock", spanishName: "Dock"),
            readOperationID: { self.activeID },
            readApplying: { true },
            readFinished: { self.finished },
            writeStage: { self.stage = $0; self.events.append("stage") },
            writeDeadlineExceeded: { self.deadline = $0; self.events.append("deadline") },
            localizedText: { en, _ in en },
            log: { key, _ in self.events.append(key) },
            quarantine: { _ in self.events.append("quarantine") },
            writeSafetyBlocked: { self.blocked = $0; self.events.append("blocked") },
            lockGate: { self.locked = true; self.events.append("locked") }
        )
    }
}
@main struct DispatchTests {
    @MainActor static func main() {
        var cases = 0
        for cancelSoft in [false, true] {
            for cancelHard in [false, true] {
                for stale in [false, true] {
                    for finished in [false, true] {
                        let state = State()
                        let schedule = EagleAuraStudioProgressSchedule.start(
                            progress: state.progress(),
                            makeWork: { action in
                                let item = DispatchWorkItem {
                                    precondition(Thread.isMainThread)
                                    action()
                                }
                                state.works.append(item)
                                return item
                            },
                            scheduleAfter: { seconds, work in
                                precondition(work === state.works.last!)
                                state.delays.append(seconds)
                            },
                            cancel: { work in
                                state.events.append(work === state.works[0] ? "cancel.soft" : "cancel.hard")
                                work.cancel()
                            }
                        )
                        precondition(state.delays == [10, 60] && state.works.count == 2)
                        if cancelSoft { schedule.cancelSoftProgress() }
                        if cancelHard { schedule.cancelHardDeadline() }
                        precondition(state.works[0].isCancelled == cancelSoft)
                        precondition(state.works[1].isCancelled == cancelHard)
                        if stale { state.activeID = "other" }
                        state.finished = finished
                        state.works[0].perform()
                        state.works[1].perform()
                        let canFire = !stale && !finished
                        precondition(state.events.contains("step.native.progress") == (canFire && !cancelSoft))
                        precondition(state.deadline == (canFire && !cancelHard))
                        precondition(state.blocked == state.deadline && state.locked == state.deadline)
                        // Cancelling repeatedly never runs either action or clears the other item.
                        let actions = state.events.filter { !$0.hasPrefix("cancel.") }
                        schedule.cancelSoftProgress(); schedule.cancelHardDeadline()
                        schedule.cancelSoftProgress(); schedule.cancelHardDeadline()
                        precondition(state.events.filter { !$0.hasPrefix("cancel.") } == actions)
                        cases += 1
                        // Break only fixture-owned references; production has the Dispatch queue's lifecycle.
                        state.works.removeAll()
                    }
                }
            }
        }
        print("PASS: \(cases) real DispatchWorkItem cases; separate cancellation, main-thread effects, stale/finished guards and repeated cancel; no wall-clock wait")
    }
}
