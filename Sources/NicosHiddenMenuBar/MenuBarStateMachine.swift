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
    /// Items that were visible in a hidden lane immediately before a spacer
    /// collapse. Live verification must observe all of them off-screen before
    /// the state may remain collapsed.
    var verificationWindowIDs: [UInt32] = []
    /// How items were (or will be) hidden. Spacer inflates a divider; placement
    /// moves hidden-lane items past the visible edge.
    var hideMechanism: MenuBarHideMechanism = .spacer
}

enum MenuBarHideMechanism: String, Equatable, Sendable {
    case spacer
    case placement
}

enum MenuBarCollapseFailure: String, Equatable, Sendable {
    case invalidMarkerOrder = "invalid_marker_order"
    case unreadableGeometry = "geometry_unreadable"
    case reconciliationFailed = "reconciliation_failed"
    /// Markers exist relative-order-valid but sit outside the target screen
    /// (autosave drift / multi-display orphan). Live evidence: minX ≈ −3780.
    case markersOffScreen = "markers_off_screen"
    /// Toggle has no hideable neighbors; inflating a spacer would only blank the bar.
    case nothingToHide = "nothing_to_hide"
    /// Real hide (spacer or placement) could not move any item off-screen.
    case hideUnavailable = "hide_unavailable"
    /// Collapse-time placement needs Accessibility.
    case accessibilityRequired = "accessibility_required"
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
