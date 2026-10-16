#!/usr/bin/env python3
"""Connect both exact Aura session/result bridges with simulated callbacks, never native execution."""
from pathlib import Path
import subprocess
import tempfile

import verify_eagle_aura_session_admission as session
import verify_eagle_aura_result_admission as result
from verify_eagle_dock_apply_flow import declaration, replace_once


def main():
    repo = Path(__file__).resolve().parents[1]
    view = (repo / session.VIEW).read_text()
    for check in (session, result):
        check.verify_texts(view, (repo / check.CORE).read_text())
    base = (repo / "scripts/verify_eagle_aura_session_admission.swift").read_text().split("@main struct Runner")[0]
    receipt = (repo / "scripts/verify_eagle_aura_result_admission.swift").read_text()
    base = replace_once(base, "    var events: [String] = []", '''    var delivery = 0
    var deliveryError: String?
    var deliveryResult: Int32 = 2
    var observedPID: Int32 = 101
    var duplicate = false
    var healthy = true
    var timedOut = [false, false]
    var timeoutIndex = 0
    var finished = false
    var consumed = 0
    var spanish = false
    var events: [String] = []''')
    base = replace_once(base, "struct Step { let flag: UInt32; let englishName: String }", '''struct Step {
    let flag: UInt32; let englishName: String
    var spanishName: String { englishName == "Island" ? "Isla" : "Dock" }
}''')
    host_signature = '''    func consume(process: Session?, sessionError: String?, operationID: String, operationSpringBoardPID: Int32, step: Step)'''
    result_signature = '''    func consume(process: Session, processError: String?, result: Int32, operationID: String,
                 operationSpringBoardPID: Int32, targetPID: Int32, springBoardPID: Int32, step: Step)'''
    base = replace_once(base, host_signature, host_signature + "\n" + result_signature)
    for marker in ("@MainActor enum AuraStudioDiagnostics", "@MainActor enum LaraL10n", "@MainActor struct Work"):
        base += "\n" + declaration(receipt, marker) + "\n"
    base += '\nextension Manager { func endExclusiveRemoteCall(label: String) { context.events.append("end.\\(label)") } }\n'
    base += "\nextension Session {\n"
    for marker in ("    var isHealthy: Bool", "    var lastCallTimedOut: Bool"):
        base += declaration(receipt, marker) + "\n"
    base += "}\nextension Host {\n"
    for marker in ("    var nativeFinished: Bool", "    var softProgressWork: Work", "    var hardDeadlineWork: Work", "    func failAfterNativeCall("):
        base += declaration(receipt, marker) + "\n"
    base += "}\n"
    # The only simulated native action is a recording event between the two
    # production bridges. Rejected sessions cannot reach it or consume results.
    delivery = '''
                context.events.append("native.simulated")
                context.admitted = process
                context.admittedPID = targetPID
                switch context.delivery {
                case 1: context.operationID = "next"
                case 2: context.applying = false
                case 3: context.livePID = 202
                case 4: context.finished = true
                case 5: context.healthy = false
                case 6: context.timedOut = [true]
                default: break
                }
                func deliver() {
                    consume(process: process, processError: context.deliveryError, result: context.deliveryResult,
                            operationID: operationID, operationSpringBoardPID: operationSpringBoardPID,
                            targetPID: targetPID, springBoardPID: context.observedPID, step: step)
                }
                deliver()
                if context.duplicate { deliver() }
'''
    for name, owned in [("PublicHost", False), ("OwnedHost", True)]:
        base += "\n@MainActor struct " + name + ": Host { let context: Context\ninit(_ context: Context) { self.context = context }\n"
        base += host_signature + " {\n" + (session.BRIDGE if owned else session.original()) + delivery + "\n}\n"
        base += result_signature + " {\n" + (result.BRIDGE if owned else result.original())
        base += '\ncontext.events.append("consume.\\(result)")\ncontext.consumed += 1\n}\n}\n'
    base += '''
@main struct Runner {
    @MainActor static func main() {
        var count = 0, accepted = 0
        for nilSession in [false, true] {
            for entry in 0..<6 {
                for delivery in 0..<7 {
                    for error in [nil, "", "transport failed"] as [String?] {
                        for code: Int32 in [-26, -17, -16, -15, -12, -1, 0, 1, 2, 3] {
                            for duplicate in [false, true] {
                                let old = PublicHost(Context()), owned = OwnedHost(Context())
                                for host in [old as any Host, owned as any Host] {
                                    let c = host.context
                                    c.delivery = delivery; c.deliveryError = error; c.deliveryResult = code
                                    c.duplicate = duplicate; c.spanish = duplicate
                                    switch entry {
                                    case 1: c.operationID = "stale"
                                    case 2: c.isolated = [false]
                                    case 3: c.livePID = 202
                                    case 4: c.exclusive = false
                                    case 5: c.pid = 0
                                    default: break
                                    }
                                    World.context = c
                                    let handle = Session(c)
                                    host.consume(process: nilSession ? nil : handle,
                                                 sessionError: entry == 1 ? "access is not ready" : "transport failed",
                                                 operationID: "run", operationSpringBoardPID: 101,
                                                 step: Step(flag: code % 2 == 0 ? 2 : 1,
                                                            englishName: code % 2 == 0 ? "Dock" : "Island"))
                                    if let admitted = c.admitted { precondition(admitted === handle) }
                                }
                                let a = old.context, b = owned.context
                                precondition(a.events == b.events && a.state == b.state)
                                precondition(a.finished == b.finished && a.consumed == b.consumed)
                                let expectedSession = !nilSession && entry == 0
                                precondition(a.events.contains("native.simulated") == expectedSession)
                                let expectedResult = expectedSession && delivery == 0 && error?.isEmpty != false
                                precondition(a.consumed == (expectedResult ? 1 : 0))
                                if expectedResult { accepted += 1 }
                                if !expectedSession {
                                    precondition(!a.events.contains("read.healthy"))
                                    precondition(!a.events.contains(where: { $0.hasPrefix("end.") }))
                                }
                                count += 1
                            }
                        }
                    }
                }
            }
        }
        print("PASS: \\(count) connected session/result journeys, \\(accepted) consumed exactly once; rejected sessions run no simulated native action")
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="eagle-aura-session-lifecycle-") as temporary:
        source = Path(temporary) / "Fixture.swift"
        source.write_text(base)
        for profile, flags in [("debug", ["-Onone", "-D", "DEBUG"]), ("release", ["-O"])]:
            binary = Path(temporary) / profile
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-parse-as-library", *flags,
                str(repo / session.CORE), str(repo / result.CORE), str(source), "-o", str(binary),
            ], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=60)
    print("PASS: connected actual Aura session/result bridges and public bodies; no native engine linked")


if __name__ == "__main__":
    main()
