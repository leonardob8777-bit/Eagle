import Foundation

@MainActor
private final class Spy {
    let expectedData: Data
    let expectedURL: URL
    let failure: NSError?
    var calls = 0

    init(data: Data, url: URL, failure: NSError?) {
        expectedData = data
        expectedURL = url
        self.failure = failure
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        MainActor.preconditionIsolated()
        calls += 1
        precondition(data == expectedData, "Complete frame bytes changed")
        precondition(url == expectedURL && url.hasDirectoryPath == expectedURL.hasDirectoryPath, "Raw frame path or URL directory semantics changed")
        precondition(options == .atomic, "Atomic write options changed")
        if let failure { throw failure }
    }
}

private func verify(_ data: Data, path: String, failure: NSError? = nil) throws {
    let directory = URL(fileURLWithPath: "/synthetic/eagle frame cache", isDirectory: true)
    for reference in [true, false] {
        let spy = Spy(data: data, url: directory.appendingPathComponent(path), failure: failure)
        let write: EagleDockGalleryFrameWriter.Write = { data, url, options in
            try spy.write(data, to: url, options: options)
        }
        do {
            if reference { try publicDockFrameWrite(data, framePath: path, in: directory, using: write) }
            else { try EagleDockGalleryFrameWriter.write(data, framePath: path, in: directory, using: write) }
            precondition(failure == nil, "Write error was swallowed")
        } catch {
            guard let failure else { throw error }
            let received = error as NSError
            precondition(received === failure, "Write error identity was replaced")
            precondition(received.domain == failure.domain && received.code == failure.code)
            precondition(NSDictionary(dictionary: received.userInfo).isEqual(to: failure.userInfo))
        }
        precondition(spy.calls == 1, "Synchronous write count or retry policy changed")
    }
}

private func writeReal(_ data: Data, path: String, directory: URL, reference: Bool) throws {
    if reference {
        try publicDockFrameWrite(data, framePath: path, in: directory) { data, url, options in
            MainActor.preconditionIsolated()
            try data.write(to: url, options: options)
        }
    } else {
        try EagleDockGalleryFrameWriter.write(data, framePath: path, in: directory)
    }
}

private struct Failure: Equatable {
    let domain: String
    let code: Int
    let path: String?
    let underlyingDomain: String?
    let underlyingCode: Int?

    init(_ error: Error) {
        let value = error as NSError
        let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError
        domain = value.domain
        code = value.code
        path = value.userInfo[NSFilePathErrorKey] as? String
        underlyingDomain = underlying?.domain
        underlyingCode = underlying?.code
    }
}

private func verifyReal(root: URL, binary: Data) throws {
    for reference in [true, false] {
        let directory = root.appendingPathComponent(reference ? "public" : "core", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Repeat the same entry path to preserve the public overwrite order.
        let writes: [(String, Data)] = [
            ("frame01.png", Data()), ("frame02.png", binary),
            ("frame01.png", binary), ("frame01.png", Data([42, 0, 255])),
        ]
        for (path, data) in writes {
            try writeReal(data, path: path, directory: directory, reference: reference)
            let actual = try Data(contentsOf: directory.appendingPathComponent(path))
            precondition(actual == data, "Temporary frame creation/replacement or duplicate overwrite order changed")
        }
    }
    // Identical explicit temporary targets make Foundation error details comparable.
    let missingParent = root.appendingPathComponent("missing/frames", isDirectory: true)
    let existingParent = root.appendingPathComponent("directory-target", isDirectory: true)
    let existingDirectory = existingParent.appendingPathComponent("frame03.png", isDirectory: true)
    try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
    for (directory, path) in [(missingParent, "frame01.png"), (existingParent, "frame03.png")] {
        var previous: Failure?
        for reference in [true, false] {
            do {
                try writeReal(binary, path: path, directory: directory, reference: reference)
                preconditionFailure("Invalid temporary write target was accepted")
            } catch {
                let actual = Failure(error)
                if let previous { precondition(actual == previous, "Public Foundation write error changed") }
                previous = actual
            }
        }
    }
    precondition(!FileManager.default.fileExists(atPath: missingParent.path), "Missing parent was created")
    var isDirectory: ObjCBool = false
    precondition(FileManager.default.fileExists(atPath: existingDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
}

@main
private enum EagleDockFrameWriterContract {
    static func main() throws {
        MainActor.preconditionIsolated()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(root.lastPathComponent.hasPrefix("eagle-dock-frame-writer-"))
        let binary = Data((0...255).map { UInt8($0) })
        var cases = 0
        // Raw/unusual paths remain callback-only cases: no disk write occurs.
        for path in ["frame01.png", "frame17.png", "nested/frame01.png", "../frame01.png", "", "odd #?%.png", "folder/"] {
            for data in [Data(), binary] {
                try verify(data, path: path)
                cases += 1
            }
        }
        let sentinel = NSError(domain: "FrameWriteSentinel", code: 775, userInfo: ["payload": "retained"])
        try verify(binary, path: "frame01.png", failure: sentinel)
        cases += 1
        try verifyReal(root: root, binary: binary)
        print("PASS: \(cases) public atomic-write parity cases, exact bytes/URL/options/one MainActor call, unchanged error identity, temporary-only replacement/duplicate order and Foundation failure parity")
    }
}
