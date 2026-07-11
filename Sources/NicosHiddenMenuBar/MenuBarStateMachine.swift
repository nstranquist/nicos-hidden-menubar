import Foundation

enum MenuBarSectionMode: Equatable, Sendable {
    case expanded
    case collapsed
}

struct MenuBarState: Equatable, Sendable {
    var mode: MenuBarSectionMode = .expanded
}

struct MenuBarCollapsePlan: Equatable, Sendable {
    var primaryLength: Double
    var secondaryLength: Double
    var useCompactFallback: Bool
    var toggleMinX: Double?
    var targetDisplayID: UInt32?
}

enum MenuBarCollapseFailure: String, Equatable, Sendable {
    case invalidMarkerOrder = "invalid_marker_order"
    case unreadableGeometry = "geometry_unreadable"
    case reconciliationFailed = "reconciliation_failed"
}

enum MenuBarInput: Equatable, Sendable {
    case toggleRequested
    case expandRequested
    case reapplyRequested
    case collapseSucceeded(MenuBarCollapsePlan)
    case collapseRejected(MenuBarCollapseFailure)
    case repairRequested(MenuBarCollapseFailure)
}

enum MenuBarEffect: Equatable, Sendable {
    case attemptCollapse
    case applyExpanded
    case reapplyExpanded
    case applyCollapsed(MenuBarCollapsePlan)
    case enterRepair(MenuBarCollapseFailure)
}

struct MenuBarTransition: Equatable, Sendable {
    var previous: MenuBarState
    var current: MenuBarState
    var effects: [MenuBarEffect]
}

struct MenuBarStateMachine: Sendable {
    private(set) var state: MenuBarState

    init(initialState: MenuBarState = MenuBarState()) {
        state = initialState
    }

    mutating func handle(_ input: MenuBarInput) -> MenuBarTransition {
        let previous = state
        let effects: [MenuBarEffect]

        switch input {
        case .toggleRequested:
            switch state.mode {
            case .expanded:
                effects = [.attemptCollapse]
            case .collapsed:
                state.mode = .expanded
                effects = [.applyExpanded]
            }
        case .expandRequested:
            state.mode = .expanded
            effects = [.applyExpanded]
        case .reapplyRequested:
            effects = state.mode == .collapsed ? [.attemptCollapse] : [.reapplyExpanded]
        case .collapseSucceeded(let plan):
            state.mode = .collapsed
            effects = [.applyCollapsed(plan)]
        case .collapseRejected(let failure), .repairRequested(let failure):
            state.mode = .expanded
            effects = [.enterRepair(failure)]
        }

        return MenuBarTransition(previous: previous, current: state, effects: effects)
    }
}
