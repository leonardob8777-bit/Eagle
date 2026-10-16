//
//  EagleDiagnosticLogger.swift
//  mowiwewgewawt
//  bacon why would you do that
//  teehee :3
//  yeah yeah teehee all you want 
//
//  I love that you just straight skidded this from jessi lmfao
//  skidding is my specialty.
//
//  Created by roooot on 15.11.25.
//

import Foundation
import Darwin
import Combine
import SwiftUI

class EagleDiagnosticLogger: ObservableObject {
    @Published var logs: [String] = []

    private var lastmessage: String?
    private var repeatCount = 0
    private var lastwasdivider = false
    private var pendingdivider = false
    private var stdoutpipe: Pipe?
    private var panding = ""
    private var ogstdout: Int32 = -1
    private var ogstderr: Int32 = -1
    private var logfileurl: URL?
    private var logfilehandle: FileHandle?
    private let fileLock = NSRecursiveLock()
    private var lastFileSync: TimeInterval = 0

    private func trimVisibleLogs() {
        // Both raw native lines and grouped UI messages must be bounded.
        if let index = logs.indices.last, logs[index].utf8.count > 8192 {
            logs[index] = String(logs[index].suffix(4096))
        }
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }

    func flushToDisk() {
        fileLock.lock()
        defer { fileLock.unlock() }
        try? logfilehandle?.synchronize()
        lastFileSync = ProcessInfo.processInfo.systemUptime
    }
    private let nobullshitkey: String
    private let logDirectory: URL?
    private let ignoredlogsubstrings = [
        "Faulty glyph",
        "outline detected - replacing with a space/null glyph",
        "Gesture:",
        "tcp_output [",
        "com.apple.UIKit.dragInitiation",
        "OSLOG",
        "_UISystemGestureGateGestureRecognizer",
        "UITouch",
        "gestureRecognizers",
        "graph: {(",
        "UILongPressGestureRecognizer",
        "UIScrollViewPanGestureRecognizer",
        "UIScrollViewDelayedTouchesBeganGestureRecognizer",
        "_UISwipeActionPanGestureRecognizer",
        "_UISecondaryClickDriverGestureRecognizer",
        "SwiftUI.UIHostingViewDebugLayer",
        "ValueType:",
        "EventType:",
        "AttributeDataLength:",
        "AttributeData:",
        "SenderID:",
        "Timestamp:",
        "TransducerType:",
        "TransducerIndex:",
        "GenerationCount:",
        "WillUpdateMask:",
        "DidUpdateMask:",
        "Pressure:",
        "AuxiliaryPressure:",
        "TiltX:",
        "TiltY:",
        "MajorRadius:",
        "MinorRadius:",
        "Accuracy:",
        "Quality:",
        "Density:",
        "Irregularity:",
        "Range:",
        "Touch:",
        "Events:",
        "ChildEvents:",
        "DisplayIntegrated:",
        "BuiltIn:",
        "EventMask:",
        "ButtonMask:",
        "Flags:",
        "Identity:",
        "Twist:",
        "X:",
        "Y:",
        "Z:",
        "Total Latency:",
        "Timestamp type:",
        "lara[",
        "};",
        "NSLayoutConstraint",
        "   \"",
    ]

    init(disableLogDividersKey: String, logDirectory: URL? = nil) {
        self.nobullshitkey = disableLogDividersKey
        self.logDirectory = logDirectory
        setuplogfile()
    }

    func log(_ message: String) {
        DispatchQueue.main.async {
            let dividersEnabled = !UserDefaults.standard.bool(forKey: self.nobullshitkey)
            if dividersEnabled && self.pendingdivider {
                self.divider()
                self.pendingdivider = false
            } else if !dividersEnabled {
                self.pendingdivider = false
                self.lastwasdivider = false
            }

            if message == self.lastmessage {
                self.repeatCount += 1
                if let lastIndex = self.logs.indices.last {
                    self.logs[lastIndex] = "\(message) (\(self.repeatCount + 1)x)"
                }
            } else {
                self.repeatCount = 0
                if dividersEnabled {
                    if self.lastwasdivider || self.logs.isEmpty {
                        self.logs.append(message)
                    } else {
                        self.logs[self.logs.count - 1] += "\n" + message
                    }
                } else {
                    self.logs.append(message)
                }
                self.lastmessage = message
            }

            self.lastwasdivider = false
            self.trimVisibleLogs()
        }

        appendtofile([message])
        emit(message)
    }

    func divider() {
        if UserDefaults.standard.bool(forKey: nobullshitkey) { return }
        DispatchQueue.main.async {
            self.lastwasdivider = true
            self.lastmessage = nil
            self.repeatCount = 0
        }
    }
    
    func enclosedlog(_ message: String) {
        if UserDefaults.standard.bool(forKey: nobullshitkey) {
            log(message)
            return
        }
        DispatchQueue.main.async {
            if !self.lastwasdivider && !self.logs.isEmpty {
                self.divider()
            }
            
            if self.lastwasdivider || self.logs.isEmpty {
                self.logs.append(message)
            } else {
                self.logs[self.logs.count - 1] += "\n" + message
            }
            
            self.lastwasdivider = false
            self.pendingdivider = true
            self.trimVisibleLogs()
        }
    }
    
    func flushdivider() {
        if UserDefaults.standard.bool(forKey: nobullshitkey) { return }
        DispatchQueue.main.async {
            if self.pendingdivider {
                self.divider()
                self.pendingdivider = false
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.lastwasdivider = false
            self.pendingdivider = false
            self.lastmessage = nil
            self.repeatCount = 0
        }
        fileLock.lock()
        defer { fileLock.unlock() }
        if let url = logfileurl {
            try? logfilehandle?.close()
            try? "".write(to: url, atomically: true, encoding: .utf8)
            logfilehandle = try? FileHandle(forWritingTo: url)
        }
    }

    func capture() {
        if stdoutpipe != nil { return }
        reopenlogfileondemand()

        let pipe = Pipe()
        stdoutpipe = pipe

        ogstdout = dup(STDOUT_FILENO)
        ogstderr = dup(STDERR_FILENO)

        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            self?.appendraw(chunk)
        }
    }

    func stopcapture() {
        guard let pipe = stdoutpipe else { return }
        pipe.fileHandleForReading.readabilityHandler = nil

        if ogstdout != -1 {
            dup2(ogstdout, STDOUT_FILENO)
            close(ogstdout)
            ogstdout = -1
        }
        if ogstderr != -1 {
            dup2(ogstderr, STDERR_FILENO)
            close(ogstderr)
            ogstderr = -1
        }

        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
        stdoutpipe = nil

        fileLock.lock()
        defer { fileLock.unlock() }
        if let handle = logfilehandle {
            try? handle.synchronize()
            try? handle.close()
            logfilehandle = nil
        }
    }

    private func appendraw(_ chunk: String) {
        let text = panding + chunk
        var lines = text.components(separatedBy: "\n")
        panding = String(lines.removeLast().suffix(16 * 1024))
        if !lines.isEmpty {
            let filtered = lines.filter { !shouldignore($0) }.map { String($0.prefix(8192)) }
            DispatchQueue.main.async {
                self.logs.append(contentsOf: filtered.suffix(400))
                self.trimVisibleLogs()
            }
            appendtofile(filtered)
            for line in filtered {
                emit(line)
            }
        }
    }

    private func emit(_ message: String) {
        if shouldignore(message) { return }
        guard ogstdout != -1 else { return }
        let line = message + "\n"
        line.withCString { ptr in
            _ = Darwin.write(ogstdout, ptr, strlen(ptr))
        }
    }

    private func shouldignore(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if isgarbageline(trimmed) {
            return true
        }
        for fragment in ignoredlogsubstrings {
            if message.contains(fragment) {
                return true
            }
        }
        return false
    }

    private func isgarbageline(_ line: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789-+|*.:(){}[]/\\_ \t")
        if line.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return true
        }
        if line == ")}" || line == ")}," || line == ")}))" {
            return true
        }
        return false
    }

    private func setuplogfile() {
        let docs = logDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("lara.log")
        let previousURL = docs.appendingPathComponent("lara.previous.log")
        let olderURL = docs.appendingPathComponent("lara.previous.2.log")
        logfileurl = url

        // Preserve the end of the previous session before opening a new log.
        // This runs once during Logger initialization, before stdout capture or
        // Prepare; it never writes while ds_run is executing. If preservation
        // fails, keep the existing file and append instead of destroying evidence.
        let rotated = preservePreviousLog(
            currentURL: url,
            previousURL: previousURL,
            olderURL: olderURL,
            maximumBytes: 512 * 1024
        )
        if rotated, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
                FileAttributeKey.protectionKey: FileProtectionType.none
            ])
        }
        
        logfilehandle = try? FileHandle(forWritingTo: url)
        _ = try? logfilehandle?.seekToEnd()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let separator = "lara started: \(formatter.string(from: Date()))"
        self.logs = [separator]
        self.lastwasdivider = true
        
        if let data = (separator + "\n").data(using: .utf8) {
            try? logfilehandle?.write(contentsOf: data)
            try? logfilehandle?.synchronize()
        }
    }

    private func preservePreviousLog(
        currentURL: URL,
        previousURL: URL,
        olderURL: URL,
        maximumBytes: Int
    ) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: currentURL.path) else { return true }

        do {
            if manager.fileExists(atPath: previousURL.path) {
                let olderData = try tailData(
                    from: previousURL,
                    maximumBytes: maximumBytes
                )
                if !olderData.isEmpty {
                    try olderData.write(to: olderURL, options: .atomic)
                }
            }

            let data = try tailData(
                from: currentURL,
                maximumBytes: maximumBytes
            )
            guard !data.isEmpty else { return true }
            try data.write(to: previousURL, options: .atomic)
            for preservedURL in [previousURL, olderURL]
            where manager.fileExists(atPath: preservedURL.path) {
                try? manager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: preservedURL.path
                )
            }
            return true
        } catch {
            return false
        }
    }

    private func tailData(from url: URL, maximumBytes: Int) throws -> Data {
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard byteCount > 0 else { return Data() }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = UInt64(max(1, maximumBytes))
        if byteCount > limit {
            try handle.seek(toOffset: byteCount - limit)
        }
        return try handle.readToEnd() ?? Data()
    }

    private func reopenlogfileondemand() {
        fileLock.lock()
        defer { fileLock.unlock() }
        if logfilehandle != nil { return }
        guard let url = logfileurl else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
                FileAttributeKey.protectionKey: FileProtectionType.none
            ])
        }
        logfilehandle = try? FileHandle(forWritingTo: url)
        _ = try? logfilehandle?.seekToEnd()
    }

    private func appendtofile(_ lines: [String]) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let handle = logfilehandle else { return }
        let filtered = lines.filter { !shouldignore($0) }
        guard !filtered.isEmpty else { return }
        let text = filtered.joined(separator: "\n") + "\n"
        if let data = text.data(using: .utf8) {
            try? handle.write(contentsOf: data)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastFileSync >= 1 {
                try? handle.synchronize()
                lastFileSync = now
            }
        }
    }
}
