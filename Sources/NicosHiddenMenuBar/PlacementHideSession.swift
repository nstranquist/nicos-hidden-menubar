import Foundation

/// Pure ownership machine for collapse-time placement hide.
///
/// All cancel / park / verify / commit interleavings are decided here with no
/// AppKit or Task — the controller is only an I/O adapter. Commit is fail-closed:
/// only when this generation still owns parks, every planned ID is owned, and
/// verify says all are past the edge.
struct PlacementHideSession: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case idle
        case parking
        case verifying
        case committed
        case failed
        case cancelled
    }

    enum Event: Equatable, Sendable {
        case start(planned: [UInt32])
        /// Record a successful park for `windowID` on the active generation.
        case parkRecorded(windowID: UInt32, generation: UInt64)
        case cancel
        /// Frame verification result for the active generation.
        case verify(allHidden: Bool, generation: UInt64)
        case fail(reason: String, generation: UInt64)
    }

    enum Effect: Equatable, Sendable {
        case noop
        case restore(ids: [UInt32])
        case commitCollapse(parked: [UInt32])
        case reject(MenuBarCollapseFailure)
    }

    struct Transition: Equatable, Sendable {
        var session: PlacementHideSession
        var effects: [Effect]
    }

    private(set) var generation: UInt64 = 0
    private(set) var phase: Phase = .idle
    private(set) var planned: [UInt32] = []
    private(set) var ownedParks: [UInt32] = []

    var isActive: Bool {
        phase == .parking || phase == .verifying
    }

    mutating func handle(_ event: Event) -> Transition {
        switch event {
        case .start(let plannedIDs):
            return start(planned: plannedIDs)

        case .parkRecorded(let windowID, let gen):
            return parkRecorded(windowID: windowID, generation: gen)

        case .cancel:
            return cancel()

        case .verify(let allHidden, let gen):
            return verify(allHidden: allHidden, generation: gen)

        case .fail(let reason, let gen):
            return fail(reason: reason, generation: gen)
        }
    }

    // MARK: - Transitions

    private mutating func start(planned plannedIDs: [UInt32]) -> Transition {
        // Starting aborts any prior in-flight generation and restores its parks.
        var effects: [Effect] = []
        if isActive, !ownedParks.isEmpty {
            effects.append(.restore(ids: ownedParks))
        }

        generation &+= 1
        phase = plannedIDs.isEmpty ? .failed : .parking
        planned = plannedIDs
        ownedParks = []

        if plannedIDs.isEmpty {
            effects.append(.reject(.nothingToHide))
            return Transition(session: self, effects: effects.isEmpty ? [.reject(.nothingToHide)] : effects)
        }
        return Transition(session: self, effects: effects.isEmpty ? [.noop] : effects)
    }

    private mutating func parkRecorded(windowID: UInt32, generation gen: UInt64) -> Transition {
        guard gen == generation else {
            // Stale generation: if something was parked after we cancelled that
            // gen, the cancel already took ownership — late parks must restore.
            return Transition(session: self, effects: [.restore(ids: [windowID])])
        }
        guard phase == .parking || phase == .verifying else {
            // Terminal phase for this gen — never keep late parks.
            return Transition(session: self, effects: [.restore(ids: [windowID])])
        }
        guard planned.contains(windowID) else {
            return Transition(session: self, effects: [.restore(ids: [windowID])])
        }
        if !ownedParks.contains(windowID) {
            ownedParks.append(windowID)
        }
        return Transition(session: self, effects: [.noop])
    }

    private mutating func cancel() -> Transition {
        // Only active sessions own parks. Idle/terminal cancel is a pure noop
        // (do not flip idle → cancelled; that poisoned re-use diagnostics).
        guard isActive else {
            return Transition(session: self, effects: [.noop])
        }
        let parks = ownedParks
        phase = .cancelled
        ownedParks = []
        // planned retained for diagnostics; ownership released.
        if parks.isEmpty {
            return Transition(session: self, effects: [.noop])
        }
        return Transition(session: self, effects: [.restore(ids: parks)])
    }

    private mutating func verify(allHidden: Bool, generation gen: UInt64) -> Transition {
        guard gen == generation else {
            return Transition(session: self, effects: [.noop])
        }
        // Cancel / fail already released ownership — never commit.
        guard phase == .parking || phase == .verifying else {
            return Transition(session: self, effects: [.noop])
        }

        phase = .verifying

        // Hard commit invariants (AC1 fail-closed).
        let fullOwnership =
            !planned.isEmpty
            && ownedParks.count == planned.count
            && Set(ownedParks) == Set(planned)

        guard allHidden, fullOwnership else {
            let parks = ownedParks
            phase = .failed
            ownedParks = []
            var effects: [Effect] = [.reject(.hideUnavailable)]
            if !parks.isEmpty {
                effects.insert(.restore(ids: parks), at: 0)
            }
            return Transition(session: self, effects: effects)
        }

        let parked = ownedParks
        phase = .committed
        ownedParks = []
        return Transition(session: self, effects: [.commitCollapse(parked: parked)])
    }

    private mutating func fail(reason _: String, generation gen: UInt64) -> Transition {
        guard gen == generation else {
            return Transition(session: self, effects: [.noop])
        }
        guard isActive else {
            return Transition(session: self, effects: [.noop])
        }
        let parks = ownedParks
        phase = .failed
        ownedParks = []
        var effects: [Effect] = [.reject(.hideUnavailable)]
        if !parks.isEmpty {
            effects.insert(.restore(ids: parks), at: 0)
        }
        return Transition(session: self, effects: effects)
    }
}
