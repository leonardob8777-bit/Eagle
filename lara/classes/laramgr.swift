//
//  laramgr.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import Combine
import Foundation
import Darwin
import notify
import UIKit
import WebKit

private func loadMutablePropertyListDictionary(from url: URL) throws -> NSMutableDictionary {
    let data = try Data(contentsOf: url)
    var format = PropertyListSerialization.PropertyListFormat.binary
    let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [.mutableContainersAndLeaves],
        format: &format
    )
    guard let dict = plist as? NSMutableDictionary else {
        throw "Property list root is not a dictionary."
    }
    return dict
}

private func clearImmutableForOverwriteIfNeeded(path: String) -> String? {
    let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    guard majorVersion == 16 else { return nil }

    let fm = FileManager.default
    guard let attributes = try? fm.attributesOfItem(atPath: path) else { return nil }

    var updates: [FileAttributeKey: Any] = [:]
    if (attributes[.immutable] as? NSNumber)?.boolValue == true {
        updates[.immutable] = false
    }
    if (attributes[.appendOnly] as? NSNumber)?.boolValue == true {
        updates[.appendOnly] = false
    }
    guard !updates.isEmpty else { return nil }

    do {
        try fm.setAttributes(updates, ofItemAtPath: path)
        return nil
    } catch {
        return "clear immutable failed: \(error.localizedDescription)"
    }
}

#if !DISABLE_REMOTECALL
/// Main-thread-owned state for one asynchronous RemoteCall preparation. A
/// reference token avoids sharing a stack `Bool` between timeout and late
/// completion closures and makes stale completions easy to identify.
private final class RemoteCallPreparationState {
    let generation: UInt64
    let process: String
    let startedAt = Date()
    var completed = false

    init(generation: UInt64, process: String) {
        self.generation = generation
        self.process = process
    }
}

private struct RemoteCallDaemonRequest {
    let serviceName: String
    let framework: String?
    let process: String
    let migbypass: Bool
    let completion: ((RemoteCall?) -> Void)?
}
#endif

final class laramgr: ObservableObject {
    private let diagnostics: EagleDiagnosticDelivery
    private var logHistory: EagleLogHistory { diagnostics.history }
    private var logHistoryObservation: AnyCancellable?
    var log: String {
        get { logHistory.text }
        set { logHistory.text = newValue }
    }
    // DarkSword can emit bursts of native log and progress callbacks while its
    // race is active. Sending every callback to the main queue individually
    // can starve SwiftUI even though the exploit itself runs in the background.
    // Coalesce those callbacks into a single UI update per display interval.
    private let dsUICallbackLock = NSLock()
    private var pendingDSLogLines: [String] = []
    private var pendingDSProgress: Double?
    private var dsUIFlushScheduled = false
    @Published var hasOffsets: Bool = false {
        didSet {
            if hasOffsets {
                EaglePrepareAttemptJournal.mark(
                    prepareAttemptID,
                    stage: .compatibilityDataReady,
                    detail: "kernelcache compatibility data resolved"
                )
            }
        }
    }
    @Published var dsrunning: Bool = false {
        didSet {
            #if !DISABLE_REMOTECALL
            if dsrunning { beginRemoteBackgroundTask() }
            else { DispatchQueue.main.async { [weak self] in self?.finishRemoteWorkIfIdle() } }
            #endif
        }
    }
    @Published var dsready: Bool = false
    @Published var dsattempted: Bool = false
    @Published var dsfailed: Bool = false
    @Published var dsprogress: Double = 0.0
    @Published var kernbase: UInt64 = 0
    @Published var kernslide: UInt64 = 0
    
    @Published var kaccessready: Bool = false
    @Published var kaccesserror: String?
    @Published var fileopinprogress: Bool = false {
        didSet {
            #if !DISABLE_REMOTECALL
            if !fileopinprogress { DispatchQueue.main.async { [weak self] in self?.finishRemoteWorkIfIdle() } }
            #endif
        }
    }
    @Published var testresult: String?
    #if !DISABLE_REMOTECALL
    @Published var rcrunning: Bool = false {
        didSet {
            // Reserve execution time before native work starts, including if
            // the user switches apps halfway through an apply operation.
            if rcrunning { beginRemoteBackgroundTask() }
            else {
                DispatchQueue.main.async { [weak self] in
                    self?.finishRemoteWorkIfIdle()
                }
            }
        }
    }
    @Published var eligibilitystate: Bool?
    @Published var eu1progress: Double = 0.0
    @Published var eu1running: Bool = false
    @Published var eu2progress: Double = 0.0
    @Published var eu2running: Bool = false
    @Published var rcLastError: String?
    #endif
    
    @Published var vfsready: Bool = false
    @Published var vfsinitlog: String = ""
    @Published var vfsattempted: Bool = false
    @Published var vfsfailed: Bool = false
    @Published var vfsrunning: Bool = false
    @Published var vfsprogress: Double = 0.0
    @Published var sbxready: Bool = false
    @Published var sbxattempted: Bool = false
    @Published var sbxfailed: Bool = false
    @Published var sbxrunning: Bool = false
    @Published var rcready: Bool = false
    @Published var rcfailed: Bool = false
    @Published private(set) var rcSafetyLocked: Bool = false
    @Published private(set) var rcSafetyReason: String?
    @Published var showrespring: Bool = false
    
    @Published var showLogs: Bool = false
    
    private var storedSBProc: RemoteCall?
    var sbProc: RemoteCall? {
        get {
            #if !DISABLE_REMOTECALL
            guard Thread.isMainThread, rcready,
                  let storedSBProc else {
                return storedSBProc
            }
            if let issue = remoteCallSessionIssue(storedSBProc, process: "SpringBoard") {
                rcLastError = issue
                rcready = false
                // Reading a property must not launch untracked teardown while
                // preparation or another worker is about to use the transport.
                logmsg("invalid SpringBoard session awaiting serialized cleanup: \(issue)")
                return nil
            }
            #endif
            return storedSBProc
        }
        set {
            storedSBProc = newValue
        }
    }
    private var rcGeneration: UInt64 = 0
    private var rcFreshSessionInFlight = false
    private var rcNativeCallInFlight = false
    private var rcNativeCallLabel: String?
    private var rcDaemonRunning = false
    private var rcDaemonQueue: [RemoteCallDaemonRequest] = []
    private var remoteBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var remoteCleanupPending = false
    private var appIsBackgrounded = false

    func remoteAppDidEnterBackground() {
        precondition(Thread.isMainThread)
        appIsBackgrounded = true
        remoteCleanupPending = true
        if storedSBProc != nil || rcrunning || dsrunning { beginRemoteBackgroundTask() }
        finishRemoteWorkIfIdle()
    }

    func remoteAppDidBecomeActive() {
        precondition(Thread.isMainThread)
        appIsBackgrounded = false
        remoteCleanupPending = false
        finishRemoteWorkIfIdle()
    }

    private func beginRemoteBackgroundTask() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.beginRemoteBackgroundTask() }
            return
        }
        guard remoteBackgroundTask == .invalid else { return }
        remoteBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "EagleRemoteOperation") { [weak self] in
            guard let self else { return }
            // Expiration cannot cancel an in-flight native call. Do not race
            // its teardown or allow another operation to reuse this session.
            if self.fileopinprogress || self.dsrunning || self.rcrunning || self.rcNativeCallInFlight || self.rcFreshSessionInFlight {
                self.quarantineRemoteCall(reason: "Background time expired before the remote operation completed")
            }
            self.endRemoteBackgroundTask()
        }
    }

    private func endRemoteBackgroundTask() {
        guard remoteBackgroundTask != .invalid else { return }
        let task = remoteBackgroundTask
        remoteBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    private func finishRemoteWorkIfIdle() {
        precondition(Thread.isMainThread)
        guard !fileopinprogress, !dsrunning, !rcrunning, !rcFreshSessionInFlight, !rcNativeCallInFlight,
              !rcDaemonRunning else { return }
        if appIsBackgrounded, remoteCleanupPending, !rcSafetyLocked {
            remoteCleanupPending = false
            // Read the stored object even when validation has marked it stale.
            if storedSBProc != nil {
                rcdestroy { [weak self] in self?.finishRemoteWorkIfIdle() }
                return
            }
        }
        endRemoteBackgroundTask()
    }
    // YouTube is optional. Constructing this at manager startup used to probe
    // for a process that often is not installed (and before Prepare was ready),
    // producing a misleading RemoteCall failure in every diagnostic report.
    lazy var ytProc = RemoteCall(process: "youtube", useMigFilterBypass: false)
    private var prepareAttemptID: String?
    
    static let shared = laramgr(diagnostics: EagleAppDiagnostics.shared)
    static let fontpath = "/System/Library/Fonts/Core/SFUI.ttf"
    static let italicfontpath = "/System/Library/Fonts/Core/SFUIItalic.ttf"
    static let monofontpath = "/System/Library/Fonts/Core/SFUIMono.ttf"
    init(diagnostics: EagleDiagnosticDelivery? = nil) {
        self.diagnostics = diagnostics ?? EagleAppDiagnostics.makeDelivery()
        logHistoryObservation = logHistory.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func enqueueDSLog(_ message: String) {
        scheduleDSUIFlush(logLine: message, progress: nil)
    }

    private func enqueueDSProgress(_ progress: Double) {
        scheduleDSUIFlush(logLine: nil, progress: progress)
    }

    private func scheduleDSUIFlush(logLine: String?, progress: Double?) {
        dsUICallbackLock.lock()
        if let logLine {
            pendingDSLogLines.append(String(logLine.prefix(8192)))
            if pendingDSLogLines.count > 400 {
                pendingDSLogLines.removeFirst(pendingDSLogLines.count - 400)
            }
        }
        if let progress {
            pendingDSProgress = progress
        }
        let shouldSchedule = !dsUIFlushScheduled
        if shouldSchedule {
            dsUIFlushScheduled = true
        }
        dsUICallbackLock.unlock()

        guard shouldSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.flushPendingDSUI()
        }
    }

    private func flushPendingDSUI() {
        dsUICallbackLock.lock()
        let lines = pendingDSLogLines
        let progress = pendingDSProgress
        pendingDSLogLines.removeAll(keepingCapacity: true)
        pendingDSProgress = nil
        dsUIFlushScheduled = false
        dsUICallbackLock.unlock()

        if !lines.isEmpty {
            let batch = lines.joined(separator: "\n")
            logHistory.append(batch)
            globallogger.log(batch)
        }
        if let progress {
            dsprogress = progress
        }
    }

    private func resetPreparedSubsystemStateForNewRun() {
        kaccessready = false
        kaccesserror = nil
        testresult = nil
        vfsready = false
        vfsattempted = false
        vfsfailed = false
        vfsrunning = false
        vfsprogress = 0.0
        sbxready = false
        sbxattempted = false
        sbxfailed = false
        sbxrunning = false
        kernbase = 0
        kernslide = 0
    }

    #if !DISABLE_REMOTECALL
    private func runningPID(for process: String) -> Int32 {
        process.withCString { pointer in
            Int32(find_process_pid(pointer))
        }
    }

    private func remoteCallSessionIssue(
        _ session: RemoteCall?,
        process: String
    ) -> String? {
        guard let session else {
            return "missing \(process) RemoteCall object"
        }
        guard session.isHealthy else {
            return session.lastError?.isEmpty == false
                ? session.lastError
                : "\(process) RemoteCall is unhealthy"
        }
        guard !session.lastCallTimedOut else {
            return "\(process) RemoteCall timed out"
        }
        guard session.pid > 0 else {
            return "\(process) RemoteCall has no verified pid"
        }

        let currentPID = runningPID(for: process)
        guard currentPID > 0 else {
            return "\(process) is not running"
        }
        guard currentPID == session.pid else {
            return "\(process) pid changed from \(session.pid) to \(currentPID)"
        }

        return nil
    }

    private func detachRemoteCallStateForPrepareStart() -> RemoteCall? {
        rcGeneration &+= 1
        let previousSession = storedSBProc
        sbProc = nil
        rcready = false
        rcfailed = false
        rcLastError = nil
        rcFreshSessionInFlight = false
        rcNativeCallInFlight = false
        rcNativeCallLabel = nil
        return previousSession
    }
    #endif

    struct AppInfo {
        let executable: String
        let displayName: String
        let bundleName: String
        let dataFolder: String
        let bundleFolder: String
    }
    
    func run(completion: ((Bool) -> Void)? = nil) {
        guard !dsrunning, !fileopinprogress else {
            completion?(false)
            return
        }
        #if !DISABLE_REMOTECALL
        guard !rcrunning, !rcFreshSessionInFlight,
              !rcNativeCallInFlight, !rcSafetyLocked else {
            rcLastError = rcSafetyReason ??
                "Finish or reopen Eagle before running Prepare again"
            completion?(false)
            return
        }
        #endif
        let support = eagleSupportAssessment()
        guard support.allowsPrepare else {
            globallogger.log("(prepare) blocked before DarkSword: \(support.reason.rawValue)")
            completion?(false)
            return
        }

        resetPreparedSubsystemStateForNewRun()
        #if !DISABLE_REMOTECALL
        let previousRemoteCallSession = detachRemoteCallStateForPrepareStart()
        #endif

        let systemBuild = eagleSystemBuild()?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let machine = devicemachine()
        let route = eaglePrepareExecutionRoute(
            version: ProcessInfo.processInfo.operatingSystemVersion,
            machine: machine,
            systemBuild: systemBuild
        )
        if route == .a18KernelStageLab {
            // The private lab owns its deliberately one-shot journal record.
            // Do not replace it with the rolling public-attempt record.
            prepareAttemptID = nil
        } else {
            prepareAttemptID = EaglePrepareAttemptJournal.beginLatest(
                route: route.rawValue,
                machine: machine,
                systemBuild: systemBuild.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
            )
        }
        let attemptID = prepareAttemptID
        dsrunning = true
        dsready = false
        dsfailed = false
        dsattempted = true
        dsprogress = 0.0
        log = ""
        
        ds_set_log_callback { messageCStr in
            guard let messageCStr else { return }
            let message = String(cString: messageCStr)
            laramgr.shared.enqueueDSLog("(ds) \(message)")
        }
        ds_set_progress_callback { progress in
            laramgr.shared.enqueueDSProgress(progress)
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            #if !DISABLE_REMOTECALL
            // Finish the old transport before Prepare changes shared kernel
            // state. Previously these ran on two unrelated global workers.
            if let previousRemoteCallSession {
                EaglePrepareAttemptJournal.mark(
                    attemptID,
                    stage: .armed,
                    detail: "cleaning previous remote session before DarkSword"
                )
                if previousRemoteCallSession.destroy() != 0 {
                    EaglePrepareAttemptJournal.finish(
                        attemptID,
                        succeeded: false,
                        detail: "previous remote session cleanup failed; DarkSword was not entered"
                    )
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.dsrunning = false
                        self.dsfailed = true
                        self.storedSBProc = previousRemoteCallSession
                        self.quarantineRemoteCall(reason: "Previous remote session could not be cleaned up before Prepare")
                        completion?(false)
                    }
                    return
                }
            }
            #endif
            EaglePrepareAttemptJournal.mark(
                attemptID,
                stage: .darkSwordRunning,
                detail: "native exploit entered"
            )
            let result = ds_run()
            
            DispatchQueue.main.async {
                guard let self else { return }
                self.dsrunning = false
                let success = result == 0 &&
                    ds_is_ready() &&
                    ds_get_our_proc() != 0 &&
                    ds_get_our_task() != 0 &&
                    ds_get_kernel_base() != 0
                if success {
                    self.dsready = true
                    self.dsfailed = false
                    self.kernbase = ds_get_kernel_base()
                    self.kernslide = ds_get_kernel_slide()
                    self.logmsg("\n(ds) exploit success!")
                    self.logmsg(String(format: "(ds) kernel_base:  0x%llx", self.kernbase))
                    self.logmsg(String(format: "(ds) kernel_slide: 0x%llx\n", self.kernslide))
                    globallogger.log("(ds) exploit success!")
                    globallogger.log(String(format: "(ds) kernel_base:  0x%llx", self.kernbase))
                    globallogger.log(String(format: "(ds) kernel_slide: 0x%llx", self.kernslide))
                    globallogger.divider()
                    EaglePrepareAttemptJournal.mark(
                        self.prepareAttemptID,
                        stage: .darkSwordReady,
                        detail: "kernel primitive verified"
                    )
                } else {
                    self.dsfailed = true
                    self.logmsg("\nexploit failed.\n")
                    globallogger.log("exploit failed.")
                    globallogger.divider()
                    EaglePrepareAttemptJournal.finish(
                        self.prepareAttemptID,
                        succeeded: false,
                        detail: "DarkSword returned without a verified primitive"
                    )
                }
                self.dsprogress = 1.0
                completion?(success)
            }
        }
    }
    
    func logmsg(_ message: String) {
        diagnostics.enqueue(message, retaining: self)
    }
    
    func kread64(address: UInt64) -> UInt64 {
        guard dsready else { return 0 }
        return ds_kread64(address)
    }
    
    func kwrite64(address: UInt64, value: UInt64) {
        guard dsready else { return }
        ds_kwrite64(address, value)
    }
    
    func kread32(address: UInt64) -> UInt32 {
        guard dsready else { return 0 }
        return ds_kread32(address)
    }
    
    func kwrite32(address: UInt64, value: UInt32) {
        guard dsready else { return }
        ds_kwrite32(address, value)
    }
    
    func panic() {
        guard dsready else { return }
        
        globallogger.log("triggering panic")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let kernbase = ds_get_kernel_base()
            globallogger.log("writing to read-only memory at kernel base")
            ds_kwrite64(kernbase, 0xDEADBEEF)
        }
    }
    
    func respring() {
        showrespring = true
    }
    
    func vfsinit(completion: ((Bool) -> Void)? = nil) {
        guard dsready, hasOffsets, !vfsrunning else {
            completion?(false)
            return
        }
        vfs_setlogcallback(laramgr.vfslogcallback)
        vfs_setprogresscallback { progress in
            DispatchQueue.main.async {
                laramgr.shared.vfsprogress = progress
            }
        }
        vfsattempted = true
        vfsfailed = false
        vfsrunning = true
        vfsprogress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = vfs_init()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.vfsready = (r == 0 && vfs_isready())
                if self.vfsready {
                    self.vfsfailed = false
                    self.logmsg("\nvfs ready!\n")
                } else {
                    self.vfsfailed = true
                    self.logmsg("\nvfs init failed.\n")
                }
                self.vfsrunning = false
                self.vfsprogress = 1.0
                completion?(self.vfsready)
            }
        }
    }
    
    func sbxescape(completion: ((Bool) -> Void)? = nil) {
        guard dsready, hasOffsets, !sbxrunning else {
            completion?(false)
            return
        }
        EaglePrepareAttemptJournal.mark(
            prepareAttemptID,
            stage: .sandboxOpening,
            detail: "sandbox escape entered"
        )
        sbxattempted = true
        sbxfailed = false
        sbxrunning = true
        
        sbx_setlogcallback(laramgr.sbxlogcallback)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = sbx_escape(ds_get_our_proc())
            DispatchQueue.main.async {
                guard let self else { return }
                self.sbxready = (r == 0)
                if self.sbxready {
                    self.sbxfailed = false
                    self.logmsg("\nsandbox escape ready!\n")
                    EaglePrepareAttemptJournal.finish(
                        self.prepareAttemptID,
                        succeeded: true,
                        detail: "kernel primitive, compatibility data, and sandbox verified"
                    )
                } else {
                    self.sbxfailed = true
                    self.logmsg("\nsandbox escape failed.\n")
                    EaglePrepareAttemptJournal.finish(
                        self.prepareAttemptID,
                        succeeded: false,
                        detail: "sandbox escape returned failure"
                    )
                }
                self.sbxrunning = false
                completion?(self.sbxready)
            }
        }
    }
    
    private static let sbxlogcallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { msg in
        guard let msg = msg else { return }
        let s = String(cString: msg)
        DispatchQueue.main.async {
            laramgr.shared.logmsg("(sbx) " + s)
        }
    }
    
    private static let vfslogcallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { msg in
        guard let msg = msg else { return }
        let s = String(cString: msg)
        DispatchQueue.main.async {
            laramgr.shared.vfsinitlog += "(vfs) " + s + "\n"
            laramgr.shared.logmsg("(vfs) " + s)
        }
    }
    
    func vfslistdir(path: String) -> [(name: String, isDir: Bool)]? {
        guard vfsready else {
            logmsg(" listdir: not ready (\(path))")
            return nil
        }
        var ptr: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        let r = vfs_listdir(path, &ptr, &count)
        guard r == 0, let entries = ptr else {
            logmsg(" listdir failed (\(path)) r=\(r)")
            return nil
        }
        defer { vfs_freelisting(entries) }
        
        var items: [(String, Bool)] = []
        for i in 0..<Int(count) {
            let e = entries[i]
            let name = withUnsafePointer(to: e.name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            items.append((name, e.d_type == 4))
        }
        logmsg(" listdir \(path) -> \(items.count)")
        return items.sorted { $0.0.lowercased() < $1.0.lowercased() }
    }
    
    func vfsread(path: String, maxSize: Int = 512 * 1024) -> Data? {
        guard vfsready else { return nil }
        let fsz = vfs_filesize(path)
        if fsz <= 0 { return nil }
        let toRead = min(Int(fsz), maxSize)
        var buf = [UInt8](repeating: 0, count: toRead)
        let n = vfs_read(path, &buf, toRead, 0)
        if n <= 0 { return nil }
        return Data(buf.prefix(Int(n)))
    }
    
    func vfswrite(path: String, data: Data) -> Bool {
        guard vfsready else { return false }
        var written = 0
        return data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return data.isEmpty }
            while written < data.count {
                let n = vfs_write(
                    path,
                    base.advanced(by: written),
                    data.count - written,
                    off_t(written)
                )
                if n <= 0 { return false }
                written += Int(n)
            }
            return true
        }
    }
    
    func vfssize(path: String) -> Int64 {
        guard vfsready else { return -1 }
        return vfs_filesize(path)
    }
    
    func vfsoverwritefromlocalpath(target: String, source: String) -> Bool {
        print("(vfs) target \(source) -> \(target)")
        
        guard vfsready else {
            print("(vfs) not ready")
            return false
        }
        
        guard FileManager.default.fileExists(atPath: source) else {
            print("(vfs) source file not found: \(source)")
            return false
        }
        
        let r = vfs_overwritefile(target, source)
        
        print("(vfs) vfs_overwritefile returned: \(r)")
        
        if r == 0 {
            print("(vfs) file overwritten")
        } else {
            print("(vfs) failed to overwrite file")
        }
        
        return r == 0
    }
    
    func vfsoverwritewithdata(target: String, data: Data) -> Bool {
        guard vfsready else { return false }
        let tmp = NSTemporaryDirectory() + "vfs_src_\(arc4random()).bin"
        do { try data.write(to: URL(fileURLWithPath: tmp)) } catch { return false }
        let ok = vfsoverwritefromlocalpath(target: target, source: tmp)
        try? FileManager.default.removeItem(atPath: tmp)
        return ok
    }
    
    private func sbxoverwrite(path: String, data: Data) -> (ok: Bool, message: String) {
        let immutableMessage = clearImmutableForOverwriteIfNeeded(path: path)
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd == -1 {
            let prefix = immutableMessage.map { "\($0), " } ?? ""
            return (false, "\(prefix)sbx open failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }
        
        var total = 0
        let wroteAll = data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return ptr.count == 0 }
            while total < ptr.count {
                let n = write(fd, base.advanced(by: total), ptr.count - total)
                if n <= 0 { return false }
                total += n
            }
            return true
        }
        
        if !wroteAll {
            return (false, "sbx write failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }

        if ftruncate(fd, off_t(total)) != 0 {
            return (false, "sbx truncate failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }
        
        return (true, "ok (\(total) bytes)")
    }
    
    @discardableResult
    func lara_overwritefile(target: String, source: String, fallback_vfs: Bool = true) -> (ok: Bool, message: String) {
        guard FileManager.default.fileExists(atPath: source) else {
            return (false, "source file not found: \(source)")
        }
        
        let result: (ok: Bool, message: String)
        if sbxready {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: source))
                result = sbxoverwrite(path: target, data: data)
            } catch {
                result = (false, "sbx read source failed: \(error.localizedDescription)")
            }
        } else {
            result = (false, "sbx not ready")
        }
        
        if result.ok {
            return result
        }

        guard fallback_vfs else {
            return result
        }
        
        guard vfsready else {
            return (false, result.message + " | vfs not ready")
        }
        
        let ok = vfsoverwritefromlocalpath(target: target, source: source)
        return ok ? (true, "ok (vfs overwrite)") : (false, result.message + " | vfs overwrite failed")
    }
    
    @discardableResult
    func lara_overwritefile(target: String, data: Data, fallback_vfs: Bool = true) -> (ok: Bool, message: String) {
        let result = sbxready ? sbxoverwrite(path: target, data: data) : (false, "sbx not ready")
        if result.0 {
            return result
        }

        guard fallback_vfs else {
            return result
        }
        
        guard vfsready else {
            return (false, result.1 + ", vfs not ready")
        }
        
        let ok = vfsoverwritewithdata(target: target, data: data)
        return ok ? (true, "vfs overwrite ok") : (false, result.1 + ", vfs overwrite failed")
    }
    
    func vfszeropage(at path: String, dumb: Bool) -> Bool {
        guard vfsready else {
            self.logmsg("(vfs) zero failed (vfs not ready)")
            return false
        }

        if dumb {
            let ok = path.withCString { vfs_zerofile($0) } == 0

            if !ok {
                self.logmsg("(vfs) zerofile failed")
                return false
            }
            
            self.logmsg("(vfs) zeroed \(path)")
            return true
        } else {
            let result = path.withCString { cpath in
                vfs_zeropage(cpath, 0)
            }

            if result != 0 {
                self.logmsg("(vfs) zeropage failed")
                return false
            }
    
            self.logmsg("(vfs) zeroed first page of \(path)")
            return true
        }
    }
    
    func sbxgettoken(pid: Int32) -> UInt64? {
        let addr = sbx_gettoken(pid)

        guard addr != 0 else {
            return nil
        }

        return addr
    }

    func sbxgettokenstring(pid: Int32) -> String? {
        guard let cstr = sbx_copytoken(pid) else {
            return nil
        }
        defer { sbx_freestr(cstr) }
        return String(cString: cstr)
    }

    func sbxissuetoken(extClass: String, path: String) -> String? {
        guard let cstr = sbx_issue_token(extClass, path) else {
            return nil
        }
        defer { sbx_freestr(cstr) }
        return String(cString: cstr)
    }
    
    func sbxelevate() {
        DispatchQueue.main.async {
            sbx_elevate();
        }
    }
    
    func isapfs(_ path: String) -> Bool {
        var s = statfs()
        guard path.withCString({ statfs($0, &s) }) == 0 else {
            return false
        }
        
        let fstypename = s.f_fstypename
        return withUnsafePointer(to: fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: fstypename)) {
                String(cString: $0) == "apfs"
            }
        }
    }

    // inspired by nugget from leminlimez
    func PPHelper() -> Bool {
        do {
            let dataFolder = "/private/var/mobile/Containers/Data/Application"
            var bundleIDs = ["com.apple.PosterBoard"]
            if UIDevice.current.userInterfaceIdiom == .phone {
                bundleIDs.append("com.apple.CarPlayWallpaper")
            }
            guard let appList = getAppList() else { return false}
            var hashes: [String:String] = [:]
            for bundleID in bundleIDs {
                if let appInfo = appList[bundleID] {
                    hashes[bundleID] = appInfo.dataFolder
                } else {
                    // this shouldn't happen
                    logmsg("Could not find app with bundle ID \(bundleID).")
                    return false
                }
            }
            var PPbundleID = "com.leemin.Pocket-Poster"
            for (bundleID, info) in appList {
                if info.executable == "Pocket Poster" {
                    PPbundleID = bundleID
                    break
                } else if info.executable == "LiveContainer" {
                    PPbundleID = bundleID
                }
            }
            if let PPHash = appList[PPbundleID]?.dataFolder {
                for bundleID in hashes.keys {
                    let fileName = "Nugget" + bundleID.replacingOccurrences(of: "com.apple.", with: "") + "Hash"
                    let content = hashes[bundleID]!
                    let filePath = dataFolder + "/" + PPHash + "/Documents/" + fileName
                    try content.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
                    logmsg("Wrote hash \(content) to \(filePath)")
                }
                return true
            } else {
                logmsg("Please install Pocket Poster before using Pocket Poster Helper. If you do have Pocket Poster installed, make sure you did not modify the bundle ID. If you installed Pocket Poster inside of LiveContainer, make sure you also did not modify the bundle ID of LiveContainer.")
                return false
            }
        } catch {
            logmsg("Error with Pocket Poster Helper: \(error.localizedDescription)")
            return false
        }
    }

    func getAppList() -> [String:AppInfo]? {
        let fm = FileManager.default
        let dataFolder = "/private/var/mobile/Containers/Data/Application"
        let bundleFolder = "/private/var/containers/Bundle/Application"
        var appList: [String:AppInfo] = [:]
        do {
            let appData = try fm.contentsOfDirectory(atPath: dataFolder)
            for app in appData {
                if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: dataFolder + "/" + app + "/.com.apple.mobile_container_manager.metadata.plist")),
                    let bundleID = plist["MCMMetadataIdentifier"] as? String {
                    appList[bundleID] = AppInfo(executable: "", displayName: "", bundleName: "", dataFolder: app, bundleFolder: "")
                }
            }

            let appBundles = try fm.contentsOfDirectory(atPath: bundleFolder)
            for app in appBundles {
                let appPath = bundleFolder + "/" + app
                let contents = try fm.contentsOfDirectory(atPath: appPath)
                for item in contents {
                    if item.hasSuffix(".app") {
                        if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: appPath + "/" + item + "/Info.plist")),
                            let bundleID = plist["CFBundleIdentifier"] as? String {
                            let executable = plist["CFBundleExecutable"] as? String ?? ""
                            let displayName = plist["CFBundleDisplayName"] as? String ?? ""
                            let bundleName = plist["CFBundleName"] as? String ?? ""
                            let dataFolderID = appList[bundleID]?.dataFolder ?? ""
                            let appInfo = AppInfo(executable: executable, displayName: displayName, bundleName: bundleName, dataFolder: dataFolderID, bundleFolder: app)
                            appList[bundleID] = appInfo
                        }
                        break
                    }
                }

            }
        } catch {
            logmsg("Error getting app list: \(error.localizedDescription)")
            return nil
        }
        return appList
    }
    
    func setplistvalue(path: String, key: (key: String, value: Any?), force: Bool = false) -> (ok: Bool, message: String) {
        do {
            let fm = FileManager.default
            var dict = NSMutableDictionary()
            if !fm.fileExists(atPath: path) {
                if !force { return (false, "file at \(path) does not exist or couldn't be found") }
            } else {
                dict = try loadMutablePropertyListDictionary(from: URL(fileURLWithPath: path))
            }
            if let value = key.value {
                dict[key.key] = value
            } else {
                dict.removeObject(forKey: key.key)
            }
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .binary,
                options: 0
            )
            let result = self.lara_overwritefile(
                target: path,
                data: data
            )
            if result.ok {
                return (true, "overwrote plist at path \(path)")
            } else {
                return(false, "overwrite failed: \(result.message)")
            }
        } catch {
            return (false, "an error occurred: \(error)")
        }
    }

    func getplistvalue(path: String, key: String) -> (ok: Bool, message: String, value: Any?) {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: path) {
                let dict = try loadMutablePropertyListDictionary(from: URL(fileURLWithPath: path))
                if let value = dict[key] {
                    return (true, "success", value)
                } else {
                    return (false, "key \(key) not found", nil)
                }
            } else {
                return (false, "file at \(path) does not exist or couldn't be found", nil)
            }
        } catch {
            return (false, "an error occurred: \(error)", nil)
        }
    }

    @discardableResult
    func apfsown(path: String, uid: UInt32, gid: UInt32) -> Bool {
        if !isapfs(path) {
            print("\(path) is apfs!")
        }
        
        let result = path.withCString { cPath in
            apfs_own(cPath, uid_t(uid), gid_t(gid))
        }
        
        if result != 0 {
            print("failed to chown \(path)")
            return false
        }
        
        print("changed owner of \(path) to \(uid):\(gid)!")
        return true
    }
    
    #if !DISABLE_REMOTECALL
    func rcinit(process: String, migbypass: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !fileopinprogress else { completion?(false); return }
        guard UIApplication.shared.applicationState == .active else {
            completion?(false)
            return
        }
        guard dsready else {
            completion?(false)
            return
        }
        guard !rcSafetyLocked else {
            rcLastError = rcSafetyReason ?? "RemoteCall is safety locked for this app run"
            completion?(false)
            return
        }
        guard !rcrunning, !rcFreshSessionInFlight,
              !rcNativeCallInFlight else {
            rcLastError = "Another RemoteCall operation is still running"
            completion?(false)
            return
        }
        if rcready, sbProc != nil {
            if let issue = remoteCallSessionIssue(sbProc, process: process) {
                rcLastError = issue
                logmsg("discarding stale remote call session: \(issue)")
                rcGeneration &+= 1
                let repairGeneration = rcGeneration
                let staleSession = sbProc
                sbProc = nil
                rcready = false
                rcrunning = true
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let cleanupResult = staleSession?.destroy() ?? 0
                    DispatchQueue.main.async {
                        guard let self else {
                            completion?(false)
                            return
                        }
                        guard self.rcGeneration == repairGeneration else {
                            self.rcrunning = false
                            completion?(false)
                            return
                        }
                        self.rcrunning = false
                        guard cleanupResult == 0 else {
                            self.storedSBProc = staleSession
                            self.quarantineRemoteCall(reason: "Stale remote session cleanup failed")
                            completion?(false)
                            return
                        }
                        self.rcinit(
                            process: process,
                            migbypass: migbypass,
                            completion: completion
                        )
                    }
                }
                return
            }
            completion?(true)
            return
        }
        if rcready {
            rcready = false
        }
        // Repair split state left by an interrupted RemoteCall lifecycle before
        // creating another session. Never overwrite a live object and leak its
        // exception ports/thread state.
        if let staleSession = storedSBProc {
            rcGeneration &+= 1
            let repairGeneration = rcGeneration
            sbProc = nil
            rcready = false
            rcrunning = true
            logmsg("repairing incomplete remote call session...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let cleanupResult = staleSession.destroy()
                DispatchQueue.main.async {
                    guard let self else {
                        completion?(false)
                        return
                    }
                    guard self.rcGeneration == repairGeneration else {
                        self.rcrunning = false
                        completion?(false)
                        return
                    }
                    self.rcrunning = false
                    guard cleanupResult == 0 else {
                        self.storedSBProc = staleSession
                        self.quarantineRemoteCall(reason: "Incomplete remote session cleanup failed")
                        completion?(false)
                        return
                    }
                    self.rcinit(
                        process: process,
                        migbypass: migbypass,
                        completion: completion
                    )
                }
            }
            return
        }
        rcready = false
        
        rcrunning = true
        rcGeneration &+= 1
        let generation = rcGeneration
        rcLastError = nil
        logmsg("initializing remote call on \(process)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let candidate: RemoteCall? = RemoteCall(
                process: process,
                useMigFilterBypass: migbypass
            )
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.rcGeneration == generation else {
                    self.rcrunning = false
                    if let candidate {
                        DispatchQueue.global(qos: .utility).async {
                            candidate.destroy()
                        }
                    }
                    completion?(false)
                    return
                }
                if let candidate,
                   let issue = self.remoteCallSessionIssue(
                    candidate,
                    process: process
                ) {
                    self.rcLastError = issue
                    self.logmsg("remote call verification failed on \(process): \(issue)")
                    self.rcrunning = false
                    self.quarantineRemoteCall(reason: issue)
                    DispatchQueue.global(qos: .utility).async {
                        candidate.destroy()
                    }
                    completion?(false)
                    return
                }
                self.sbProc = candidate
                let success = candidate != nil
                if success {
                    self.logmsg("remote call initialized on \(process)")
                    self.rcLastError = nil
                    self.rcrunning = false
                    self.rcready = true
                } else {
                    self.logmsg("remote call init failed on \(process)")
                    let error = RemoteCall.lastInitError()
                    self.rcLastError = error
                    if let error, !error.isEmpty {
                        self.logmsg("remote call init failed on \(process): \(error)")
                    } else {
                        self.logmsg("remote call init failed on \(process)")
                    }
                    self.rcrunning = false
                }
                completion?(success)
            }
        }
    }

    /// Builds a brand-new RemoteCall session without ever overlapping teardown
    /// and initialization. Aura Studio uses this before every individual
    /// SpringBoard module so a stale exception port cannot leak into the next
    /// mutation. A timeout invalidates the generation; late work is discarded
    /// and never starts another session.
    func prepareFreshRemoteCall(
        process: String,
        migbypass: Bool = false,
        timeout: TimeInterval = 12,
        completion: @escaping (RemoteCall?, String?) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.prepareFreshRemoteCall(
                    process: process,
                    migbypass: migbypass,
                    timeout: timeout,
                    completion: completion
                )
            }
            return
        }
        guard dsready else {
            completion(nil, "Eagle access is not ready")
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            completion(nil, "Return to Eagle before applying a change")
            return
        }
        guard !rcSafetyLocked else {
            completion(
                nil,
                rcSafetyReason ?? "RemoteCall is safety locked for this app run"
            )
            return
        }
        guard !fileopinprogress, !rcFreshSessionInFlight, !rcrunning,
              !rcNativeCallInFlight else {
            completion(nil, "Another RemoteCall lifecycle operation is still running")
            return
        }

        rcFreshSessionInFlight = true
        rcrunning = true
        rcready = false
        rcfailed = false
        rcLastError = nil
        rcGeneration &+= 1
        let generation = rcGeneration
        let preparation = RemoteCallPreparationState(
            generation: generation,
            process: process
        )
        let previousSession = storedSBProc
        sbProc = nil

        func complete(_ session: RemoteCall?, _ error: String?) {
            precondition(Thread.isMainThread)
            guard !preparation.completed else {
                if let session {
                    DispatchQueue.global(qos: .utility).async {
                        session.destroy()
                    }
                }
                return
            }
            preparation.completed = true
            rcFreshSessionInFlight = false
            rcrunning = false
            let elapsed = Date().timeIntervalSince(preparation.startedAt)
            if let session {
                sbProc = session
                rcready = true
                rcfailed = false
                rcLastError = nil
            } else {
                rcready = false
                rcfailed = true
                rcLastError = error
            }
            logmsg(
                String(
                    format: "remote call preparation finished on %@ in %.3fs (%@)",
                    preparation.process,
                    elapsed,
                    session == nil ? "failed" : "ready"
                )
            )
            completion(session, error)
        }

        let deadline = max(4, timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
            guard let self,
                  self.rcGeneration == generation,
                  !preparation.completed else { return }
            let reason = "Fresh SpringBoard session timed out after \(Int(deadline)) seconds"
            self.rcGeneration &+= 1
            complete(nil, reason)
            // A timeout does not cancel Objective-C/native work. Keep all
            // retries locked for this process; a late candidate is discarded
            // by the generation check and can never become the active session.
            self.quarantineRemoteCall(reason: reason)
        }

        logmsg("preparing a fresh remote call session on \(process)...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cleanupResult = previousSession?.destroy() ?? 0
            DispatchQueue.main.async {
                guard let self,
                      self.rcGeneration == generation,
                      !preparation.completed else { return }
                guard cleanupResult == 0 else {
                    let reason = "Previous remote session cleanup failed"
                    self.storedSBProc = previousSession
                    complete(nil, reason)
                    self.quarantineRemoteCall(reason: reason)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let candidate = RemoteCall(
                        process: process,
                        useMigFilterBypass: migbypass
                    )
                    DispatchQueue.main.async {
                        guard let self,
                              self.rcGeneration == generation,
                              !preparation.completed else {
                            if let candidate {
                                DispatchQueue.global(qos: .utility).async {
                                    candidate.destroy()
                                }
                            }
                            return
                        }
                        if let candidate,
                           let issue = self.remoteCallSessionIssue(
                            candidate,
                            process: process
                        ) {
                            self.logmsg("fresh remote call verification failed on \(process): \(issue)")
                            self.quarantineRemoteCall(reason: issue)
                            DispatchQueue.global(qos: .utility).async {
                                candidate.destroy()
                            }
                            complete(nil, issue)
                        } else if let candidate {
                            self.logmsg("fresh remote call initialized on \(process)")
                            complete(candidate, nil)
                        } else {
                            let detail = RemoteCall.lastInitError()
                            let error: String
                            if let detail, !detail.isEmpty {
                                error = detail
                            } else {
                                error = "Fresh RemoteCall initialization failed on \(process)"
                            }
                            self.logmsg(error)
                            complete(nil, error)
                        }
                    }
                }
            }
        }
    }

    /// Prevents any retry after an unverified native mutation. The live object
    /// is deliberately retained and not destroyed here because it may still be
    /// unwinding a timed-out remote call. Closing and reopening Eagle is the
    /// only reset, which keeps a late callback from starting another mutation.
    func quarantineRemoteCall(reason: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.quarantineRemoteCall(reason: reason)
            }
            return
        }
        rcGeneration &+= 1
        rcFreshSessionInFlight = false
        rcrunning = false
        rcready = false
        rcfailed = true
        rcSafetyLocked = true
        rcSafetyReason = reason
        rcLastError = reason
        logmsg("remote call safety lock: \(reason)")
    }

    func beginExclusiveRemoteCall(label: String, expectedSession: RemoteCall) -> Bool {
        precondition(Thread.isMainThread)
        guard !fileopinprogress else { return false }
        guard UIApplication.shared.applicationState == .active else { return false }
        // Awaiting preparation yields the main actor. Another caller may have
        // replaced (and destroyed) that session before this caller resumes.
        // Compare identity before reading any native session properties.
        guard let session = storedSBProc, session === expectedSession,
              rcready, !rcrunning,
              !rcNativeCallInFlight, !rcSafetyLocked else {
            return false
        }
        if let issue = remoteCallSessionIssue(session, process: "SpringBoard") {
            rcLastError = issue
            rcready = false
            logmsg("remote call operation rejected: \(issue)")
            return false
        }
        rcNativeCallInFlight = true
        rcNativeCallLabel = label
        rcrunning = true
        logmsg("remote call operation started: \(label)")
        return true
    }

    func endExclusiveRemoteCall(label: String) {
        precondition(Thread.isMainThread)
        guard rcNativeCallInFlight else {
            logmsg("ignored duplicate remote call completion: \(label)")
            return
        }
        guard rcNativeCallLabel == label else {
            logmsg(
                "remote call completion label mismatch: " +
                "active=\(rcNativeCallLabel ?? "none"), finishing=\(label)"
            )
            return
        }
        rcNativeCallInFlight = false
        rcNativeCallLabel = nil
        rcrunning = false
        logmsg("remote call operation finished: \(label)")
    }
    
    func rcinitDaemon(serviceName: String, framework: String? = nil, process: String, migbypass: Bool = false, completion: ((RemoteCall?) -> Void)? = nil) {
        let request = RemoteCallDaemonRequest(
            serviceName: serviceName,
            framework: framework,
            process: process,
            migbypass: migbypass,
            completion: completion
        )

        guard !fileopinprogress, dsready, !rcSafetyLocked, sbProc != nil else {
            completion?(nil)
            return
        }

        guard !rcFreshSessionInFlight, !rcNativeCallInFlight else {
            rcLastError = "A serialized RemoteCall operation is still running"
            completion?(nil)
            return
        }

        if rcDaemonRunning {
            rcDaemonQueue.append(request)
            logmsg("queued remote call daemon session on \(process)")
            return
        }

        guard !rcrunning else {
            rcLastError = "Another RemoteCall operation is still running"
            completion?(nil)
            return
        }

        startRemoteCallDaemon(request)
    }

    private func startRemoteCallDaemon(_ request: RemoteCallDaemonRequest) {
        guard dsready, !rcrunning, !rcSafetyLocked, let sbProc else {
            request.completion?(nil)
            return
        }

        rcDaemonRunning = true
        rcrunning = true
        logmsg("initializing remote call on \(request.process)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if request.process.withCString({ proc_find_by_name($0) == 0 }) {
                wake_up_daemon(sbProc, request.serviceName, request.framework)
                sleep(1) // give the daemon some time to start up
            }
            
            let proc = RemoteCall(
                process: request.process,
                useMigFilterBypass: request.migbypass
            )
            let initError = RemoteCall.lastInitError()
            request.completion?(proc)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let success = proc != nil
                if success {
                    self.logmsg("remote call initialized on \(request.process)")
                } else {
                    if let error = initError, !error.isEmpty {
                        self.logmsg("remote call init failed on \(request.process): \(error)")
                    } else {
                        self.logmsg("remote call init failed on \(request.process)")
                    }
                }

                self.rcrunning = false
                self.rcDaemonRunning = false

                if !self.rcDaemonQueue.isEmpty {
                    let next = self.rcDaemonQueue.removeFirst()
                    self.startRemoteCallDaemon(next)
                }
            }
        }
    }
    
    func rcdestroy(completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.rcdestroy(completion: completion) }
            return
        }
        guard !rcrunning, !rcFreshSessionInFlight,
              !rcNativeCallInFlight, !rcSafetyLocked else {
            rcLastError = "A serialized or quarantined RemoteCall operation is still running"
            completion?()
            return
        }
        rcGeneration &+= 1
        let generation = rcGeneration
        guard rcready || storedSBProc != nil else {
            rcready = false
            completion?()
            return
        }
        
        logmsg("destroying remote call session...")
        let session = storedSBProc
        sbProc = nil
        rcready = false
        rcrunning = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = session?.destroy() ?? 0
            
            DispatchQueue.main.async {
                if self?.rcGeneration == generation {
                    self?.rcrunning = false
                    if result != 0 {
                        self?.storedSBProc = session
                        self?.quarantineRemoteCall(reason: "Remote session teardown did not finish safely")
                    }
                }
                self?.logmsg(result == 0 ? "remote call session destroyed" : "remote call cleanup failed; further changes are locked")
                completion?()
            }
        }
    }

    func stashKRWToLaunchd(completion: ((Bool) -> Void)? = nil) {
        guard dsready, !rcrunning else {
            completion?(false)
            return
        }

        rcrunning = true
        rcLastError = nil
        logmsg("(persist) manually transferring KRW primitives to launchd...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = transfer_krw_to_launchd()

            DispatchQueue.main.async {
                guard let self else { return }
                self.rcrunning = false
                if success {
                    self.rcLastError = nil
                    self.logmsg("(persist) manual KRW transfer to launchd succeeded")
                } else {
                    let error = RemoteCall.lastInitError()
                    self.rcLastError = error
                    if let error, !error.isEmpty {
                        self.logmsg("(persist) manual KRW transfer to launchd failed: \(error)")
                    } else {
                        self.logmsg("(persist) manual KRW transfer to launchd failed")
                    }
                }
                completion?(success)
            }
        }
    }
    
    //  params:
    //  - name: function to call
    //  - args: up to 8 args in registers (x0-x7) and extra args passed to stack pointer
    //  - timeout: timeout in ms
    //  ret: return value from rc
    func rccall(name: String, args: [UInt64] = [], timeout: Int32 = 100) -> UInt64 {
        guard rcready, !rcrunning, !rcSafetyLocked,
              let session = sbProc,
              remoteCallSessionIssue(session, process: "SpringBoard") == nil else {
            return 0
        }
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        guard let ptr = dlsym(RTLD_DEFAULT, name) else {
            rcLastError = "RemoteCall symbol not found: \(name)"
            logmsg("(rc) symbol not found: \(name)")
            return 0
        }
        var argsCopy = args
        return name.withCString { (cName: UnsafePointer<CChar>) -> UInt64 in
            UInt64(argsCopy.withUnsafeMutableBufferPointer { buffer in
                session.doStable(
                    withTimeout: timeout,
                    functionName: UnsafeMutablePointer(mutating: cName),
                    functionPointer: ptr,
                    args: buffer.baseAddress,
                    argCount: UInt(args.count)
                )
            })
        }
    }
    #endif
}
