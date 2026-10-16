// Compatibility names for existing log consumers; implementation is Eagle-owned.
typealias Logger = EagleDiagnosticLogger

let globallogger = Logger()

extension EagleDiagnosticLogger {
    convenience init() {
        self.init(disableLogDividersKey: EaglePreferenceKeys.disableLogDividers)
    }
}
