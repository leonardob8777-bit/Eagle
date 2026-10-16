import Foundation

/// Uses the same main queue and Dispatch work items as the public app; no Task hop or retry.
@MainActor
enum EagleAuraStudioProgressScheduler {
    static func start(
        progress: EagleAuraStudioStepProgress
    ) -> EagleAuraStudioProgressSchedule<DispatchWorkItem> {
        EagleAuraStudioProgressSchedule.start(
            progress: progress,
            makeWork: { action in
                DispatchWorkItem { action() }
            },
            scheduleAfter: { seconds, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: work)
            },
            cancel: { $0.cancel() }
        )
    }
}
