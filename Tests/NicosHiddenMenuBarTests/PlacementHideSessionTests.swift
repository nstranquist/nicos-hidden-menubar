import XCTest
@testable import NicosHiddenMenuBar

/// Table-driven ownership interleavings for collapse-time placement hide.
/// These are the races skeptics kept inventing — pure, no Task/AppKit.
final class PlacementHideSessionTests: XCTestCase {
    private let planned: [UInt32] = [10, 20, 30]

    func testHappyPathParkAllVerifyCommit() {
        var session = PlacementHideSession()
        let start = session.handle(.start(planned: planned))
        XCTAssertEqual(start.session.phase, .parking)
        XCTAssertFalse(start.effects.contains { if case .commitCollapse = $0 { return true }; return false })
        session = start.session
        let gen = session.generation

        for id in planned {
            let t = session.handle(.parkRecorded(windowID: id, generation: gen))
            session = t.session
            XCTAssertEqual(t.effects, [.noop])
        }
        XCTAssertEqual(session.ownedParks.count, 3)

        let done = session.handle(.verify(allHidden: true, generation: gen))
        XCTAssertEqual(done.session.phase, .committed)
        XCTAssertEqual(done.effects, [.commitCollapse(parked: planned)])
        XCTAssertTrue(done.session.ownedParks.isEmpty)
    }

    func testPartialParkVerifyFailsAndRestores() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        session = session.handle(.parkRecorded(windowID: 10, generation: gen)).session

        let t = session.handle(.verify(allHidden: false, generation: gen))
        XCTAssertEqual(t.session.phase, .failed)
        XCTAssertTrue(t.effects.contains(.restore(ids: [10])))
        XCTAssertTrue(t.effects.contains(.reject(.hideUnavailable)))
        XCTAssertFalse(t.effects.contains { if case .commitCollapse = $0 { return true }; return false })
    }

    func testPartialParkAllHiddenButIncompleteOwnershipFails() {
        // Frames claim all hidden but we only own 1 of 3 — still fail closed.
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        session = session.handle(.parkRecorded(windowID: 10, generation: gen)).session

        let t = session.handle(.verify(allHidden: true, generation: gen))
        XCTAssertEqual(t.session.phase, .failed)
        XCTAssertTrue(t.effects.contains(.restore(ids: [10])))
        XCTAssertTrue(t.effects.contains(.reject(.hideUnavailable)))
        XCTAssertFalse(t.effects.contains { if case .commitCollapse = $0 { return true }; return false })
    }

    func testCancelWithEmptyParksIsNoopNoCommit() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let t = session.handle(.cancel)
        XCTAssertEqual(t.session.phase, .cancelled)
        XCTAssertEqual(t.effects, [.noop])
        XCTAssertFalse(t.effects.contains { if case .commitCollapse = $0 { return true }; return false })
    }

    func testCancelAfterKParksRestoresThoseK() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        session = session.handle(.parkRecorded(windowID: 10, generation: gen)).session
        session = session.handle(.parkRecorded(windowID: 20, generation: gen)).session

        let t = session.handle(.cancel)
        XCTAssertEqual(t.session.phase, .cancelled)
        XCTAssertEqual(t.effects, [.restore(ids: [10, 20])])
        XCTAssertTrue(t.session.ownedParks.isEmpty)
    }

    func testCancelThenLateParkRecordedRestoresNotCommits() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        session = session.handle(.parkRecorded(windowID: 10, generation: gen)).session
        session = session.handle(.cancel).session

        // Late park from mover finishing after cancel.
        let late = session.handle(.parkRecorded(windowID: 20, generation: gen))
        XCTAssertEqual(late.effects, [.restore(ids: [20])])
        XCTAssertEqual(late.session.phase, .cancelled)
        XCTAssertFalse(late.effects.contains { if case .commitCollapse = $0 { return true }; return false })
    }

    /// Round-3 skeptic race: cancel takes ownership, then late verify tries to commit.
    func testCancelThenLateVerifyDoesNotCommitEvenIfAllHidden() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        for id in planned {
            session = session.handle(.parkRecorded(windowID: id, generation: gen)).session
        }
        let cancel = session.handle(.cancel)
        session = cancel.session
        XCTAssertEqual(cancel.effects, [.restore(ids: planned)])

        // Late verify (MainActor hop after cancel emptied owned parks).
        let late = session.handle(.verify(allHidden: true, generation: gen))
        XCTAssertEqual(late.effects, [.noop])
        XCTAssertEqual(late.session.phase, .cancelled)
        XCTAssertFalse(late.effects.contains { if case .commitCollapse = $0 { return true }; return false })
        // Must not promote empty parks into a collapsed claim.
        XCTAssertFalse(late.effects.contains(.commitCollapse(parked: [])))
    }

    func testCancelThenLateFailIsNoop() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        session = session.handle(.cancel).session
        let t = session.handle(.fail(reason: "item_move_failed", generation: gen))
        XCTAssertEqual(t.effects, [.noop])
        XCTAssertFalse(t.effects.contains { if case .commitCollapse = $0 { return true }; return false })
    }

    func testCancelFromIdleIsNoopDoesNotEnterCancelled() {
        var session = PlacementHideSession()
        XCTAssertEqual(session.phase, .idle)
        let t = session.handle(.cancel)
        XCTAssertEqual(t.effects, [.noop])
        XCTAssertEqual(t.session.phase, .idle)
    }

    func testNewSessionIgnoresOldGenerationEvents() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: [1, 2])).session
        let oldGen = session.generation
        session = session.handle(.parkRecorded(windowID: 1, generation: oldGen)).session

        // New collapse attempt supersedes old gen (restores old parks).
        let restart = session.handle(.start(planned: [100]))
        XCTAssertTrue(restart.effects.contains(.restore(ids: [1])))
        session = restart.session
        let newGen = session.generation
        XCTAssertNotEqual(oldGen, newGen)

        // Old gen events must not commit the new session.
        let stalePark = session.handle(.parkRecorded(windowID: 2, generation: oldGen))
        XCTAssertEqual(stalePark.effects, [.restore(ids: [2])])
        session = stalePark.session

        let staleVerify = session.handle(.verify(allHidden: true, generation: oldGen))
        XCTAssertEqual(staleVerify.effects, [.noop])
        XCTAssertFalse(staleVerify.effects.contains { if case .commitCollapse = $0 { return true }; return false })

        // New gen can still succeed.
        session = session.handle(.parkRecorded(windowID: 100, generation: newGen)).session
        let ok = session.handle(.verify(allHidden: true, generation: newGen))
        XCTAssertEqual(ok.effects, [.commitCollapse(parked: [100])])
    }

    func testEmptyPlannedStartRejectsNothingToHide() {
        var session = PlacementHideSession()
        let t = session.handle(.start(planned: []))
        XCTAssertEqual(t.session.phase, .failed)
        XCTAssertTrue(t.effects.contains(.reject(.nothingToHide)))
    }

    func testFailMidParkRestoresAndRejects() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        session = session.handle(.parkRecorded(windowID: 10, generation: gen)).session
        let t = session.handle(.fail(reason: "item_move_failed", generation: gen))
        XCTAssertEqual(t.session.phase, .failed)
        XCTAssertTrue(t.effects.contains(.restore(ids: [10])))
        XCTAssertTrue(t.effects.contains(.reject(.hideUnavailable)))
        XCTAssertFalse(t.effects.contains { if case .commitCollapse = $0 { return true }; return false })
    }

    func testCommitRequiresExactPlannedSetNotJustCount() {
        var session = PlacementHideSession()
        session = session.handle(.start(planned: planned)).session
        let gen = session.generation
        // Own three IDs but one is not in planned (shouldn't happen; still fail-closed).
        session = session.handle(.parkRecorded(windowID: 10, generation: gen)).session
        session = session.handle(.parkRecorded(windowID: 20, generation: gen)).session
        // Inject foreign via direct... can't; parkRecorded rejects non-planned with restore.
        let foreign = session.handle(.parkRecorded(windowID: 99, generation: gen))
        XCTAssertEqual(foreign.effects, [.restore(ids: [99])])
        session = foreign.session
        // Only 2 of 3 planned owned.
        let t = session.handle(.verify(allHidden: true, generation: gen))
        XCTAssertEqual(t.session.phase, .failed)
        XCTAssertTrue(t.effects.contains(.reject(.hideUnavailable)))
    }
}
