import XCTest
@testable import NicosHiddenMenuBar

final class MenuBarStateMachineTests: XCTestCase {
    func testARC001ToggleFromExpandedRequestsCollapseWithoutChangingState() {
        var machine = MenuBarStateMachine()

        let transition = machine.handle(.toggleRequested)

        XCTAssertEqual(transition.previous.mode, .expanded)
        XCTAssertEqual(transition.current.mode, .expanded)
        XCTAssertEqual(transition.effects, [.attemptCollapse])
    }

    func testARC001SuccessfulCollapseProducesTypedPlanEffect() {
        var machine = MenuBarStateMachine()
        let plan = MenuBarCollapsePlan(
            primaryLength: 240,
            secondaryLength: 8,
            useCompactFallback: false,
            toggleMinX: 1_200,
            targetDisplayID: 7
        )

        let transition = machine.handle(.collapseSucceeded(plan))

        XCTAssertEqual(transition.current.mode, .collapsed)
        XCTAssertEqual(transition.effects, [.applyCollapsed(plan)])
    }

    func testARC001ToggleFromCollapsedAppliesExpandedState() {
        var machine = MenuBarStateMachine(initialState: MenuBarState(mode: .collapsed))

        let transition = machine.handle(.toggleRequested)

        XCTAssertEqual(transition.current.mode, .expanded)
        XCTAssertEqual(transition.effects, [.applyExpanded])
    }

    func testARC001RejectedCollapseEntersRepairState() {
        var machine = MenuBarStateMachine(initialState: MenuBarState(mode: .collapsed))

        let transition = machine.handle(.collapseRejected(.unreadableGeometry))

        XCTAssertEqual(transition.current.mode, .expanded)
        XCTAssertEqual(transition.effects, [.enterRepair(.unreadableGeometry)])
    }

    func testARC001ReapplyUsesCurrentStateWithoutAppKit() {
        var expanded = MenuBarStateMachine()
        var collapsed = MenuBarStateMachine(initialState: MenuBarState(mode: .collapsed))

        XCTAssertEqual(expanded.handle(.reapplyRequested).effects, [.reapplyExpanded])
        XCTAssertEqual(collapsed.handle(.reapplyRequested).effects, [.attemptCollapse])
    }

    func testARC001MarkersOffScreenAndNothingToHideEnterRepair() {
        var machine = MenuBarStateMachine(initialState: MenuBarState(mode: .expanded))
        let offScreen = machine.handle(.collapseRejected(.markersOffScreen))
        XCTAssertEqual(offScreen.current.mode, .expanded)
        XCTAssertEqual(offScreen.effects, [.enterRepair(.markersOffScreen)])

        let nothing = machine.handle(.collapseRejected(.nothingToHide))
        XCTAssertEqual(nothing.current.mode, .expanded)
        XCTAssertEqual(nothing.effects, [.enterRepair(.nothingToHide)])
    }

    func testARC001HideUnavailableAndAccessibilityRequiredFailClosed() {
        var machine = MenuBarStateMachine(initialState: MenuBarState(mode: .expanded))
        let hideFail = machine.handle(.collapseRejected(.hideUnavailable))
        XCTAssertEqual(hideFail.current.mode, .expanded)
        XCTAssertEqual(hideFail.effects, [.enterRepair(.hideUnavailable)])

        let ax = machine.handle(.collapseRejected(.accessibilityRequired))
        XCTAssertEqual(ax.current.mode, .expanded)
        XCTAssertEqual(ax.effects, [.enterRepair(.accessibilityRequired)])
    }

    func testARC001PlacementCollapsePlanSucceedsOnlyViaSucceededInput() {
        var machine = MenuBarStateMachine()
        let plan = MenuBarCollapsePlan(
            primaryLength: 8,
            secondaryLength: 0,
            useCompactFallback: true,
            toggleMinX: 1_400,
            targetDisplayID: 1,
            hideMechanism: .placement
        )
        // Attempt does not flip mode until collapseSucceeded after verified hide.
        XCTAssertEqual(machine.state.mode, .expanded)
        let done = machine.handle(.collapseSucceeded(plan))
        XCTAssertEqual(done.current.mode, .collapsed)
        XCTAssertEqual(done.effects, [.applyCollapsed(plan)])
    }
}
