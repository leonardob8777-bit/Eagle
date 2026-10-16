import Foundation

private func theme(
    frames: Int, fps: Double? = nil, width: Int = 1146,
    height: Int = 318, bytes: Int = 1
) -> EagleDockGalleryTheme {
    EagleDockGalleryTheme(
        id: "fixture", version: 3, title: "Fixture", titleES: "Ejemplo",
        subtitle: "Cache", subtitleES: "Caché", accent: "#123456",
        previewURL: URL(string: "https://example.invalid/preview")!, animatedPreviewURL: nil,
        packageURL: URL(string: "https://example.invalid/package")!, sha256: "unused",
        byteCount: bytes, frameCount: frames, fps: fps ?? (frames == 17 ? 6 : 1),
        width: width, height: height
    )
}

private enum Event: Equatable {
    case read(Int)
    case validate(Int)
}

private func payload(_ index: Int) -> Data {
    Data([UInt8(index), 0, 127, 128, 255]) + Data("frame-\(index)".utf8)
}

@MainActor
private final class Spy {
    let fixture: EagleDockGalleryTheme
    let directory: URL
    let readErrorAt: Int?
    let invalidAt: Int?
    var events: [Event] = []
    var reads = 0
    var validations = 0

    init(_ fixture: EagleDockGalleryTheme, directory: URL, readErrorAt: Int?, invalidAt: Int?) {
        self.fixture = fixture
        self.directory = directory
        self.readErrorAt = readErrorAt
        self.invalidAt = invalidAt
    }

    func read(_ url: URL, options: Data.ReadingOptions) throws -> Data {
        MainActor.preconditionIsolated()
        reads += 1
        let digits = reads < 10 ? "0\(reads)" : "\(reads)"
        precondition(url == directory.appendingPathComponent("frame\(digits).png"), "Frame URL, order or repeat changed")
        precondition(options == .mappedIfSafe, "Read options changed")
        events.append(.read(reads))
        if reads == readErrorAt {
            throw NSError(domain: "FrameReadSentinel", code: 773, userInfo: ["payload": "retained"])
        }
        return payload(reads)
    }

    func validate(_ data: Data, theme: EagleDockGalleryTheme) -> Bool {
        MainActor.preconditionIsolated()
        validations += 1
        precondition(validations == reads, "Validation skipped or repeated a successful read")
        precondition(data == payload(reads) && theme == fixture, "Complete callback data/theme changed")
        events.append(.validate(reads))
        return reads != invalidAt
    }
}

private func verify(
    _ fixture: EagleDockGalleryTheme, supported: Bool,
    readErrorAt: Int? = nil, invalidAt: Int? = nil
) {
    // Every read is injected; this synthetic URL is never opened on disk.
    let directory = URL(fileURLWithPath: "/synthetic/eagle frame cache", isDirectory: true)
    var expectedEvents: [Event] = []
    if supported {
        for index in 1...fixture.frameCount {
            expectedEvents.append(.read(index))
            if index == readErrorAt { break }
            expectedEvents.append(.validate(index))
            if index == invalidAt { break }
        }
    }
    let expectedResult = supported && readErrorAt == nil && invalidAt == nil
    for reference in [true, false] {
        let spy = Spy(fixture, directory: directory, readErrorAt: readErrorAt, invalidAt: invalidAt)
        let read: EagleDockGalleryCachedFrames.Read = { url, options in
            try spy.read(url, options: options)
        }
        let validate: EagleDockGalleryCachedFrames.ValidateFrame = { data, theme in
            spy.validate(data, theme: theme)
        }
        let result = reference
            ? publicDockCachedFrames(in: directory, theme: fixture, read: read, validateFrame: validate)
            : EagleDockGalleryCachedFrames.areValid(in: directory, theme: fixture, read: read, validateFrame: validate)
        precondition(result == expectedResult, "Public result or error-to-false policy changed")
        precondition(spy.events == expectedEvents, "Gate, read/validate order or early stop changed")
        precondition(spy.reads == expectedEvents.filter { if case .read = $0 { return true }; return false }.count)
        precondition(spy.validations == expectedEvents.filter { if case .validate = $0 { return true }; return false }.count)
    }
}

@main
private enum EagleDockCachedFramesContract {
    static func main() {
        MainActor.preconditionIsolated()
        var cases = 0
        for frames in [1, 17] {
            let fixture = theme(frames: frames)
            verify(fixture, supported: true)
            cases += 1
            for index in frames == 1 ? [1] : [1, 9, 17] {
                verify(fixture, supported: true, readErrorAt: index)
                verify(fixture, supported: true, invalidAt: index)
                cases += 2
            }
        }
        // Validation failure prevents later reads; read failure prevents same-frame validation.
        verify(theme(frames: 17), supported: true, readErrorAt: 9, invalidAt: 1)
        verify(theme(frames: 17), supported: true, readErrorAt: 9, invalidAt: 9)
        cases += 2
        let unsupported = [
            theme(frames: -1), theme(frames: 0), theme(frames: 2),
            theme(frames: 1, fps: 6), theme(frames: 17, fps: 1),
            theme(frames: 1, width: 0), theme(frames: 17, height: 0),
            theme(frames: 1, bytes: 0), theme(frames: 17, bytes: 30 * 1024 * 1024 + 1),
        ]
        for fixture in unsupported {
            // Zero/negative frame counts must return before forming a ClosedRange.
            verify(fixture, supported: false, readErrorAt: 1, invalidAt: 1)
            cases += 1
        }
        print("PASS: \(cases) public cached-frame parity cases, support-before-range gating, exact URL/options/data/theme, ordered reads/validation, early stops and synchronous MainActor callbacks")
    }
}
