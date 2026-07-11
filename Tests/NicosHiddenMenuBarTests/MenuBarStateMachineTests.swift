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
}
