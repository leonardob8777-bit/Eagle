import Foundation

@main
private enum EagleDockSessionChecks {
    static func main() async {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func isReset(_ session: EagleDockGallerySession, started: Bool) -> Bool {
            session.visitStarted == started && session.mediaFilter == .still &&
                session.selectedRemoteID.isEmpty && session.readyRemotePreviewID.isEmpty &&
                session.shuffledRemoteIDs.isEmpty &&
                EagleDockGalleryMediaFilter.allCases.allSatisfy { session.rememberedSelections.restoredID(for: $0) == nil }
        }
        expect(isReset(EagleDockGallerySession(), started: false), "Initial session must retain all public defaults")
        let view = SessionBridgeFixture()
        view.selectedRemoteID = "selected"
        view.mediaFilter = .live
        view.readyRemotePreviewID = "ready"
        view.shuffledRemoteIDs.append(contentsOf: ["b", "a", "b"])
        view.rememberedSelections.remember(id: "saved-static", for: .still)
        view.rememberedSelections.remember(id: "", for: .favorites)
        view.visitStarted = true
        expect(view.session.selectedRemoteID == "selected" && view.session.mediaFilter == .live &&
               view.session.readyRemotePreviewID == "ready" && view.session.visitStarted,
               "Scalar screen setters must write the actual Core session")
        expect(view.session.shuffledRemoteIDs == ["b", "a", "b"], "Array mutation through bridge must write back without deduplication")
        expect(view.session.rememberedSelections.restoredID(for: .still) == "saved-static" &&
               view.session.rememberedSelections.restoredID(for: .favorites) == .some(""),
               "Nested memory mutation through bridge must write back")
        let snapshot = view.session
        view.session.selectedRemoteID = "from-core"
        expect(view.selectedRemoteID == "from-core", "Screen reads must reflect the session source of truth")
        expect(snapshot.selectedRemoteID == "selected", "Session snapshot must remain an independent value")
        view.rememberedSelections.remember(id: nil, for: .still)
        expect(view.rememberedSelections.restoredID(for: .still) == nil &&
               snapshot.rememberedSelections.restoredID(for: .still) == "saved-static", "Nested memory copies must remain isolated")
        view.visitStarted = false
        expect(view.selectedRemoteID == "from-core" && view.readyRemotePreviewID == "ready" &&
               view.shuffledRemoteIDs == ["b", "a", "b"], "Leaving a visit must not implicitly erase other transient fields")
        view.beginGalleryVisit()
        expect(isReset(view.session, started: true), "Begin visit must reset category, order, selection, preview and memory")
        expect(view.synchronized.count == 1 && isReset(view.synchronized[0], started: true),
               "Screen synchronization must run once after Core reset")
        view.beginGalleryVisit()
        expect(view.synchronized.count == 2 && isReset(view.session, started: true), "Repeated visit start must remain valid")
        let secondView = SessionBridgeFixture()
        expect(isReset(secondView.session, started: false), "Another screen session must not share visit state")
        let detached = await Task.detached {
            var copy = snapshot
            copy.beginVisit()
            return copy
        }.value
        expect(isReset(detached, started: true) && snapshot.selectedRemoteID == "selected" &&
               snapshot.rememberedSelections.restoredID(for: .favorites) == .some(""),
               "Owned session/reset must work as a Sendable value outside MainActor")
        print("PASS: \(checks) session assertions: defaults, real bridge reads/writes, nested writeback, copy/instance isolation, visit reset/synchronization and detached use")
    }
}
