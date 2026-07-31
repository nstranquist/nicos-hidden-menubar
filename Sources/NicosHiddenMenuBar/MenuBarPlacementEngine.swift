import CoreGraphics
import Foundation

/// Pure placement retry / timeout / rollback planner (MOVE-001).
///
/// Live AppKit movement is performed by `MenuBarItemMover`; this engine owns the
/// deterministic control flow so tests do not need a window server.
struct MenuBarPlacementEngine: Equatable, Sendable {
    struct Config: Equatable, Sendable {
        var maxAttempts: Int
        var settleMilliseconds: Int
        var timeoutMilliseconds: Int

        static let `default` = Config(
            maxAttempts: 3,
            settleMilliseconds: 40,
            timeoutMilliseconds: 1_200
        )
    }

    enum Phase: String, Equatable, Sendable {
        case idle
        case moving
        case settling
        case verifying
        case succeeded
        case retrying
        case rollingBack
        case failed
        case cancelled
    }

    enum Event: Equatable, Sendable {
        case start
        case frameObserved(matched: Bool)
        case settleElapsed
        case attemptFailed
        case cancel
        case timeout
    }

    enum Effect: Equatable, Sendable {
        case performMove
        case waitSettle(milliseconds: Int)
        case observeFrame
        case performRollback
        case completeSuccess
        case completeFailure(reason: String)
        case completeCancelled
    }

    struct State: Equatable, Sendable {
        var phase: Phase
        var attempt: Int
        var elapsedMilliseconds: Int
        var lastReason: String?

        static let initial = State(phase: .idle, attempt: 0, elapsedMilliseconds: 0, lastReason: nil)
    }

    struct Transition: Equatable, Sendable {
        var state: State
        var effects: [Effect]
    }

    var config: Config

    init(config: Config = .default) {
        self.config = config
    }

    func handle(_ event: Event, state: State) -> Transition {
        var next = state
        var effects: [Effect] = []

        switch (state.phase, event) {
        case (.idle, .start):
            next.phase = .moving
            next.attempt = 1
            next.elapsedMilliseconds = 0
            effects = [.performMove]

        case (.moving, .frameObserved(true)):
            next.phase = .settling
            effects = [.waitSettle(milliseconds: config.settleMilliseconds)]

        case (.moving, .frameObserved(false)), (.moving, .attemptFailed):
            effects = retryOrFail(&next, reason: "move_unobserved")

        case (.settling, .settleElapsed):
            next.phase = .verifying
            next.elapsedMilliseconds += config.settleMilliseconds
            effects = [.observeFrame]

        case (.verifying, .frameObserved(true)):
            next.phase = .succeeded
            effects = [.completeSuccess]

        case (.verifying, .frameObserved(false)):
            effects = retryOrFail(&next, reason: "settle_mismatch")

        case (_, .timeout):
            next.phase = .rollingBack
            next.lastReason = "timeout"
            effects = [.performRollback, .completeFailure(reason: "timeout")]
            next.phase = .failed

        case (_, .cancel) where state.phase != .succeeded && state.phase != .failed:
            next.phase = .cancelled
            effects = [.performRollback, .completeCancelled]

        default:
            break
        }

        return Transition(state: next, effects: effects)
    }

    private func retryOrFail(_ state: inout State, reason: String) -> [Effect] {
        state.lastReason = reason
        if state.attempt < config.maxAttempts {
            state.phase = .retrying
            state.attempt += 1
            state.phase = .moving
            return [.performMove]
        }
        state.phase = .rollingBack
        let effects: [Effect] = [.performRollback, .completeFailure(reason: reason)]
        state.phase = .failed
        return effects
    }
}
