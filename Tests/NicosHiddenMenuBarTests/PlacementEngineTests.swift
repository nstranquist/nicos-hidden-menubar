import XCTest
@testable import NicosHiddenMenuBar

final class PlacementEngineTests: XCTestCase {
    func testMOVE001SuccessfulCollapsePath() {
        let engine = MenuBarPlacementEngine(config: .default)
        var state = MenuBarPlacementEngine.State.initial

        var t = engine.handle(.start, state: state)
        state = t.state
        XCTAssertEqual(state.phase, .moving)
        XCTAssertEqual(t.effects, [.performMove])

        t = engine.handle(.frameObserved(matched: true), state: state)
        state = t.state
        XCTAssertEqual(state.phase, .settling)

        t = engine.handle(.settleElapsed, state: state)
        state = t.state
        XCTAssertEqual(state.phase, .verifying)

        t = engine.handle(.frameObserved(matched: true), state: state)
        state = t.state
        XCTAssertEqual(state.phase, .succeeded)
        XCTAssertEqual(t.effects, [.completeSuccess])
    }

    func testMOVE001RetriesThenFailsWithRollback() {
        let config = MenuBarPlacementEngine.Config(maxAttempts: 2, settleMilliseconds: 10, timeoutMilliseconds: 100)
        let engine = MenuBarPlacementEngine(config: config)
        var state = MenuBarPlacementEngine.State.initial

        var t = engine.handle(.start, state: state)
        state = t.state

        t = engine.handle(.attemptFailed, state: state)
        state = t.state
        XCTAssertEqual(state.attempt, 2)
        XCTAssertEqual(state.phase, .moving)
        XCTAssertEqual(t.effects, [.performMove])

        t = engine.handle(.attemptFailed, state: state)
        state = t.state
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(
            t.effects,
            [.performRollback, .completeFailure(reason: "move_unobserved")]
        )
    }

    func testMOVE001TimeoutRollsBack() {
        let engine = MenuBarPlacementEngine()
        var state = MenuBarPlacementEngine.State.initial
        state = engine.handle(.start, state: state).state

        let t = engine.handle(.timeout, state: state)
        XCTAssertEqual(t.state.phase, .failed)
        XCTAssertTrue(t.effects.contains(.performRollback))
        XCTAssertTrue(t.effects.contains(.completeFailure(reason: "timeout")))
    }

    func testMOVE001CancelRollsBack() {
        let engine = MenuBarPlacementEngine()
        var state = MenuBarPlacementEngine.State.initial
        state = engine.handle(.start, state: state).state

        let t = engine.handle(.cancel, state: state)
        XCTAssertEqual(t.state.phase, .cancelled)
        XCTAssertEqual(t.effects, [.performRollback, .completeCancelled])
    }
}
