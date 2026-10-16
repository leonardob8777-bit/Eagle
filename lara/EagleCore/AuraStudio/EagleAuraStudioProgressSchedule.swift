import Foundation

/// Owns the two progress jobs, not the native operation. Work creation and timing are injected.
@MainActor
struct EagleAuraStudioProgressSchedule<Work> {
    private let softProgressWork: Work
    private let hardDeadlineWork: Work
    private let cancel: (Work) -> Void

    static func start(
        progress: EagleAuraStudioStepProgress,
        makeWork: (@escaping @MainActor () -> Void) -> Work,
        scheduleAfter: (Int, Work) -> Void,
        cancel: @escaping (Work) -> Void
    ) -> Self {
        let softProgressWork = makeWork {
            progress.reportProgress()
        }
        scheduleAfter(10, softProgressWork)

        // Device evidence on iOS 18.6.2 shows a healthy, verified
        // Island call can take ~17 seconds. The hard deadline is a
        // circuit breaker, not a false failure: the in-flight result
        // is still consumed, but an automatic retry can never start.
        let hardDeadlineWork = makeWork {
            progress.deadlineReached()
        }
        scheduleAfter(60, hardDeadlineWork)
        return Self(
            softProgressWork: softProgressWork,
            hardDeadlineWork: hardDeadlineWork,
            cancel: cancel
        )
    }

    func cancelSoftProgress() {
        cancel(softProgressWork)
    }

    func cancelHardDeadline() {
        cancel(hardDeadlineWork)
    }
}
