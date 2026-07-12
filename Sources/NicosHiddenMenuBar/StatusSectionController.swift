import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class StatusSectionController: NSObject {
    private static let deferredCollapseRetryDelay: TimeInterval = 0.75

    private let preferencesStore: PreferencesStore
    private let profileStore: ProfileStore
    private let services: MenuBarServices
    private let openSettings: () -> Void
    private let openDiagnostics: () -> Void
    private let openOnboarding: () -> Void

    private let toggleItem: NSStatusItem
    private let primarySeparatorItem: NSStatusItem
    private let secondarySeparatorItem: NSStatusItem
    private let contextMenu = NSMenu()

    private var stateMachine = MenuBarStateMachine()
    private var toggleState: MenuBarSectionMode { stateMachine.state.mode }
    private var lastToggleAt = Date.distantPast
    private var lastScan: MenuBarDiscoverySnapshot?
    private lazy var iceBar = IceBarPanel(
        discovery: services.discovery,
        capture: services.capture,
        onActivate: { [weak self] windowID in
            self?.activateHiddenItem(windowID)
        }
    )
    private var autoCollapseWorkItem: DispatchWorkItem?
    private var revealWorkItem: DispatchWorkItem?
    private var geometryRefreshWorkItem: DispatchWorkItem?
    private var compactFallbackDisplayIDs: Set<CGDirectDisplayID> = []
    private var cancellables: Set<AnyCancellable> = []

    init(
        preferencesStore: PreferencesStore = .shared,
        profileStore: ProfileStore = .shared,
        services: MenuBarServices,
        openSettings: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void,
        openOnboarding: @escaping () -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.profileStore = profileStore
        self.services = services
        self.openSettings = openSettings
        self.openDiagnostics = openDiagnostics
        self.openOnboarding = openOnboarding
        // Seed control-item positions before creating the status items so macOS
        // restores a stable layout on first run, then persists user drags via
        // autosaveName (the position-persistence Ice relies on).
        ControlSection.allCases.forEach(StatusItemDefaults.seedIfNeeded)
        self.toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.primarySeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.secondarySeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.toggleItem.autosaveName = ControlSection.visible.autosaveName
        self.primarySeparatorItem.autosaveName = ControlSection.hidden.autosaveName
        self.secondarySeparatorItem.autosaveName = ControlSection.alwaysHidden.autosaveName
        super.init()

        configureStatusItems()
        configureMenu()
        bindConfig()
        applyCurrentConfiguration()
        record("status_items_configured")
    }

    func toggle() {
        guard Date().timeIntervalSince(lastToggleAt) >= 0.2 else {
            record("toggle_ignored", level: .debug, fields: ["reason": "debounce"])
            return
        }
        lastToggleAt = Date()
        record("toggle_requested")
        perform(stateMachine.handle(.toggleRequested))
    }

    /// User-facing reveal action. Automatic mode keeps the classic compact
    /// inline behavior on regular displays and uses the below-menu-bar panel
    /// where a notch splits the available menu-bar space.
    func toggleReveal() {
        let screen = revealTargetScreen()
        if shouldRevealBelowMenuBar(on: screen) {
            guard Date().timeIntervalSince(lastToggleAt) >= 0.2 else {
                record("reveal_ignored", level: .debug, fields: ["reason": "debounce"])
                return
            }
            lastToggleAt = Date()
            openIceBar(on: screen)
        } else {
            toggle()
        }
    }

    func expand() {
        perform(stateMachine.handle(.expandRequested))
    }

    private func applyExpandedState() {
        autoCollapseWorkItem?.cancel()
        record("section_expanding")
        applyExpandedLengths()
        updateToggleAppearance()
        configureMenu()
        preferencesStore.recordGeometryReadable(true)
        preferencesStore.recordMarkerOrder(valid: currentMarkerOrderValid())
        let profile = profileStore.activeProfile
        let shouldUseRegularActivation = preferencesStore.config.useRegularActivationOnExpand || profile.useRegularActivationOnExpand
        NSApplication.shared.setActivationPolicy(shouldUseRegularActivation ? .regular : .accessory)
        scheduleAutoCollapseIfNeeded()
    }

    @discardableResult
    func collapse() -> Bool {
        let config = preferencesStore.config
        let geometrySnapshot = currentGeometrySnapshot()
        let toggleX = geometrySnapshot.toggleMinX
        let primaryX = geometrySnapshot.primaryMinX
        let secondaryX = geometrySnapshot.secondaryMinX
        preferencesStore.recordGeometrySnapshot(geometrySnapshot)
        let isValid = MarkerGeometry.isValidOrder(
            toggleX: toggleX,
            primaryX: primaryX,
            secondaryX: secondaryX,
            alwaysHiddenEnabled: config.lanes.alwaysHiddenEnabled
        )
        preferencesStore.recordMarkerOrder(valid: isValid)
        guard isValid else {
            record("collapse_rejected", level: .warning, fields: ["reason": "invalid_marker_order"])
            perform(stateMachine.handle(.collapseRejected(.invalidMarkerOrder)))
            return false
        }

        let visibleFrameMaxX = MarkerGeometry.preferredVisibleFrameMaxX(
            primaryMinX: primaryX,
            preferredVisibleFrameMaxX: [
                geometrySnapshot.toggleScreenVisibleMaxX,
                geometrySnapshot.primaryScreenVisibleMaxX,
                geometrySnapshot.mouseScreenVisibleMaxX,
            ],
            fallbackVisibleFrameMaxX: geometrySnapshot.allScreenVisibleMaxX
        )
        guard let collapseWidth = MarkerGeometry.collapsedWidth(
            visibleFrameMaxX: visibleFrameMaxX,
            primaryMinX: primaryX
        ) else {
            record("collapse_rejected", level: .warning, fields: ["reason": "geometry_unreadable"])
            preferencesStore.recordGeometryReadable(false, reason: "geometry_unreadable")
            perform(stateMachine.handle(.collapseRejected(.unreadableGeometry)))
            return false
        }

        preferencesStore.recordGeometryReadable(true)
        let targetScreen = toggleItem.button?.window?.screen ?? activeMouseScreen()
        let useCompactFallback = shouldUseCompactFallback(
            on: targetScreen,
            geometrySnapshot: geometrySnapshot
        )
        let plan = MenuBarCollapsePlan(
            primaryLength: useCompactFallback ? Double(primaryExpandedLength(for: config)) : collapseWidth,
            secondaryLength: Double(secondaryExpandedLength(for: config)),
            useCompactFallback: useCompactFallback,
            toggleMinX: toggleX,
            targetDisplayID: targetScreen?.displayID
        )
        perform(stateMachine.handle(.collapseSucceeded(plan)))
        return true
    }

    private func applyCollapsedState(_ plan: MenuBarCollapsePlan) {
        autoCollapseWorkItem?.cancel()
        if plan.useCompactFallback {
            record("compact_notch_fallback_applied")
        } else {
            record("section_collapsing")
        }
        primarySeparatorItem.length = CGFloat(plan.primaryLength)
        secondarySeparatorItem.length = CGFloat(plan.secondaryLength)
        updateMarkerTitles()
        updateToggleAppearance()
        configureMenu()
        NSApplication.shared.setActivationPolicy(.accessory)
        if !plan.useCompactFallback {
            let targetScreen = NSScreen.screens.first { $0.displayID == plan.targetDisplayID }
            scheduleCollapseVerification(toggleMinX: plan.toggleMinX, screen: targetScreen)
        }
    }

    /// After a collapse, the spacer reflow is async. Verify against real item
    /// frames that something actually moved off the visible edge. On a notched
    /// display this catches the failure mode where items get shoved under the
    /// notch instead of off-screen — the reason this approach needs Ice-style
    /// ground-truth verification rather than trusting the spacer alone.
    private func scheduleCollapseVerification(toggleMinX: Double?, screen: NSScreen?) {
        let target = screen ?? activeMouseScreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.toggleState == .collapsed else { return }
            guard let scan = self.scanScreen(target, toggleMinX: toggleMinX), scan.hideableItemCount > 0 else {
                self.preferencesStore.recordCollapseHidItems(nil)
                return
            }
            self.preferencesStore.recordCollapseHidItems(scan.anyItemHiddenPastEdge)
            if !scan.anyItemHiddenPastEdge {
                self.record(
                    "collapse_verification_failed",
                    level: .warning,
                    fields: ["notch": String(scan.hasNotch)]
                )
                if self.shouldRevealBelowMenuBar(on: target) {
                    if let target {
                        self.compactFallbackDisplayIDs.insert(target.displayID)
                    }
                    self.record("ineffective_spacer_released")
                    self.applyExpandedLengths()
                    self.preferencesStore.recordGeometrySnapshot(self.currentGeometrySnapshot())
                }
            }
        }
    }

    private func shouldUseCompactFallback(
        on screen: NSScreen?,
        geometrySnapshot: HiddenBarGeometrySnapshot
    ) -> Bool {
        guard let screen, shouldRevealBelowMenuBar(on: screen) else {
            return false
        }
        if compactFallbackDisplayIDs.contains(screen.displayID) {
            return true
        }
        let priorFailureMatchesNotchedScreen = geometrySnapshot.notchDetected == true
            && MarkerGeometry.shouldUseCompactFallback(
                revealsBelowMenuBar: true,
                collapseHidItems: preferencesStore.diagnostics.lastCollapseHidItems
            )
        if priorFailureMatchesNotchedScreen {
            compactFallbackDisplayIDs.insert(screen.displayID)
        }
        return priorFailureMatchesNotchedScreen
    }

    /// Open the IceBar popover of hidden items. The real notch fix: hidden items
    /// are shown in a floating panel rather than reflowed into the menu bar.
    func openIceBar() {
        openIceBar(on: revealTargetScreen())
    }

    private func openIceBar(on screen: NSScreen?, retryCount: Int = 0) {
        guard let screen else { return }
        let anchor = asDouble(toggleItem.button?.window?.frame.midX)
        let screenMinX = Double(screen.frame.minX)
        let screenMidX = Double(screen.frame.midX)
        let screenMaxX = Double(screen.frame.maxX)
        let anchorIsReady = MarkerGeometry.isReadyStatusItemAnchor(
            anchor,
            screenMinX: screenMinX,
            screenMidX: screenMidX,
            screenMaxX: screenMaxX
        )
        guard anchorIsReady else {
            if retryCount < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.openIceBar(on: self.revealTargetScreen(), retryCount: retryCount + 1)
                }
            } else {
                record("reveal_deferred", level: .warning, fields: ["reason": "anchor_not_ready"])
            }
            return
        }
        record("reveal_panel_opening")
        iceBar.toggle(near: anchor, on: screen)
    }

    /// Activate an item chosen in the IceBar through the injected owner. The live
    /// owner preserves the v0.1 behavior: opt-in placement into the visible lane,
    /// otherwise expanding the bar as the fail-closed fallback.
    private func activateHiddenItem(_ windowID: CGWindowID) {
        guard
            let screen = revealTargetScreen(),
            let toggleWindowID = toggleItem.button?.window.map({ CGWindowID($0.windowNumber) })
        else {
            record("item_activation_failed", level: .warning, fields: ["reason": "missing_target"])
            expand()
            return
        }

        let request = MenuBarActivationRequest(
            item: MenuBarItemHandle(windowID: windowID),
            targetDisplay: MenuBarDisplayHandle(rawValue: screen.displayID),
            visibleAnchor: MenuBarItemHandle(windowID: toggleWindowID)
        )
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.services.activation.activate(request)
            switch outcome {
            case .revealedForActivation:
                self.record("item_revealed_for_activation", fields: ["window_id": String(windowID)])
            case .permissionRequired:
                self.record("item_activation_failed", level: .warning, fields: ["reason": "permission_required"])
                self.expand()
            case .unsupported(let reason):
                self.record("item_activation_fallback", level: .info, fields: ["reason": reason])
                self.expand()
            case .failed(let reason):
                self.record("item_activation_failed", level: .error, fields: ["reason": reason])
                self.expand()
            }
        }
    }

    func recomputeGeometry() {
        record("geometry_recomputing", level: .debug)
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
        if toggleState == .collapsed {
            _ = collapse()
        } else {
            let isValid = currentMarkerOrderValid()
            preferencesStore.recordMarkerOrder(valid: isValid)
            if !isValid {
                perform(stateMachine.handle(.repairRequested(.reconciliationFailed)))
            } else {
                preferencesStore.recordGeometryReadable(true)
            }
        }
        let targetScreen = revealTargetScreen()
        if let targetScreen {
            iceBar.refreshIfVisible(
                near: asDouble(toggleItem.button?.window?.frame.midX),
                on: targetScreen
            )
        }
        scheduleGeometryRefresh()
    }

    func temporarilyRevealMarkers() {
        revealWorkItem?.cancel()
        let shouldRestoreCollapsed = (toggleState == .collapsed)
        record("markers_temporarily_revealed")
        expand()
        openOnboarding()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if shouldRestoreCollapsed {
                self.attemptRevealCollapse()
            }
        }
        revealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }

    private func configureStatusItems() {
        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(handleToggleButton(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if let primaryButton = primarySeparatorItem.button {
            primaryButton.isBordered = false
        }
        if let secondaryButton = secondarySeparatorItem.button {
            secondaryButton.isBordered = false
        }
    }

    private func configureMenu() {
        contextMenu.removeAllItems()
        contextMenu.addItem(hostedMenuItem(
            HiddenMenuSummaryRow(
                profileName: profileStore.activeProfileName,
                toggleState: toggleState == .collapsed ? "collapsed" : "expanded",
                autoCollapseText: autoCollapseSummary()
            )
        ))
        contextMenu.addItem(hostedMenuItem(
            HiddenMenuDiagnosticsRow(
                markerStatus: preferencesStore.diagnostics.markerOrderStatus.rawValue,
                geometryStatus: preferencesStore.diagnostics.geometryReadable ? "readable" : "needs repair",
                bridgeStatus: HammerspoonBridge.shared.status.code.rawValue
            )
        ))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Expand Inline", action: #selector(menuExpand), keyEquivalent: "e"))
        contextMenu.addItem(NSMenuItem(title: "Collapse", action: #selector(menuCollapse), keyEquivalent: "c"))
        contextMenu.addItem(NSMenuItem(title: "Show Below Menu Bar", action: #selector(menuOpenIceBar), keyEquivalent: "i"))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Open Settings", action: #selector(menuOpenSettings), keyEquivalent: ","))
        contextMenu.addItem(NSMenuItem(title: "Open Diagnostics", action: #selector(menuOpenDiagnostics), keyEquivalent: "d"))
        contextMenu.addItem(NSMenuItem(title: "Reveal Markers", action: #selector(menuRevealMarkers), keyEquivalent: "r"))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q"))
        contextMenu.items.forEach { item in
            if item.action != nil {
                item.target = self
            }
        }
        record("context_menu_rebuilt", level: .debug)
    }

    private func bindConfig() {
        preferencesStore.$config
            .sink { [weak self] _ in
                self?.applyCurrentConfiguration()
                self?.configureMenu()
            }
            .store(in: &cancellables)

        profileStore.$activeProfileName
            .sink { [weak self] _ in
                self?.configureMenu()
            }
            .store(in: &cancellables)
    }

    private func applyCurrentConfiguration() {
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
        perform(stateMachine.handle(.reapplyRequested))
        scheduleAutoCollapseIfNeeded()
        updateToggleAppearance()
        updateMarkerTitles()
        scheduleGeometryRefresh()
    }

    private func applyExpandedLengths() {
        let config = preferencesStore.config
        primarySeparatorItem.length = primaryExpandedLength(for: config)
        secondarySeparatorItem.length = secondaryExpandedLength(for: config)
        updateMarkerTitles()
    }

    private func primaryExpandedLength(for config: HiddenBarConfig) -> CGFloat {
        config.lanes.primarySeparatorVisibleWhenExpanded ? 8.0 : 0.0
    }

    private func secondaryExpandedLength(for config: HiddenBarConfig) -> CGFloat {
        guard config.lanes.alwaysHiddenEnabled else {
            return 0.0
        }
        return config.lanes.secondarySeparatorVisibleWhenExpanded ? 8.0 : 0.0
    }

    private func hostedMenuItem<Content: View>(_ content: Content) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuItemHostingView(rootView: AnyView(content))
        return item
    }

    private func autoCollapseSummary() -> String {
        let profile = profileStore.activeProfile
        if profile.autoCollapseEnabled {
            return "auto-collapse \(profile.autoCollapseSeconds)s"
        }
        return "manual collapse"
    }

    private func updateToggleAppearance() {
        guard let button = toggleItem.button else {
            return
        }
        let revealsBelow = revealAppearanceUsesBelowMenuBar
        let symbolName = revealsBelow ? "chevron.down" : ((toggleState == .collapsed) ? "chevron.right" : "chevron.left")
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Hidden Bar Toggle")
        button.imagePosition = .imageOnly
        button.toolTip = revealsBelow
            ? "Show hidden items below the menu bar"
            : ((toggleState == .collapsed) ? "Expand hidden menu items" : "Collapse menu items")
    }

    private func updateMarkerTitles() {
        // The primary item becomes a wide invisible spacer while collapsed.
        // Drawing the divider then centers it inside the empty region, which
        // looks like a stray marker in the middle of the display.
        let hideMarkers = toggleState == .collapsed
            || (preferencesStore.config.hideMarkersWhileExpanded && toggleState == .expanded)
        primarySeparatorItem.button?.title = hideMarkers ? "" : "¦"
        secondarySeparatorItem.button?.title = hideMarkers ? "" : "¦"
    }

    private func scheduleAutoCollapseIfNeeded() {
        autoCollapseWorkItem?.cancel()
        let profile = profileStore.activeProfile
        guard toggleState == .expanded, profile.autoCollapseEnabled else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptAutoCollapse()
        }
        autoCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(profile.autoCollapseSeconds), execute: workItem)
    }

    private func attemptAutoCollapse() {
        guard toggleState == .expanded else {
            return
        }
        guard !shouldPauseCollapseForInteraction() else {
            record("auto_collapse_delayed", level: .debug, fields: ["reason": "pointer_interaction"])
            scheduleAutoCollapseRetry()
            return
        }
        _ = collapse()
    }

    private func scheduleAutoCollapseRetry(after delay: TimeInterval? = nil) {
        autoCollapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptAutoCollapse()
        }
        autoCollapseWorkItem = workItem
        let retryDelay = delay ?? Self.deferredCollapseRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
    }

    private func attemptRevealCollapse() {
        guard toggleState == .expanded else {
            return
        }
        guard !shouldPauseCollapseForInteraction() else {
            scheduleRevealCollapseRetry()
            return
        }
        _ = collapse()
    }

    private func scheduleRevealCollapseRetry(after delay: TimeInterval? = nil) {
        revealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptRevealCollapse()
        }
        revealWorkItem = workItem
        let retryDelay = delay ?? Self.deferredCollapseRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
    }

    private func currentMarkerOrderValid() -> Bool {
        let primaryX = compactPrimaryMinX()
        return MarkerGeometry.isValidOrder(
            toggleX: asDouble(toggleItem.button?.window?.frame.minX),
            primaryX: primaryX,
            secondaryX: asDouble(secondarySeparatorItem.button?.window?.frame.minX),
            alwaysHiddenEnabled: preferencesStore.config.lanes.alwaysHiddenEnabled
        )
    }

    private func asDouble(_ value: CGFloat?) -> Double? {
        value.map(Double.init)
    }

    private func currentGeometrySnapshot() -> HiddenBarGeometrySnapshot {
        let toggleX = asDouble(toggleItem.button?.window?.frame.minX)
        // Normalize to the compact divider position. Without this, every
        // geometry refresh while collapsed treats the already-inflated
        // spacer's minX as a new baseline and grows it again.
        let primaryX = compactPrimaryMinX()
        let secondaryX = asDouble(secondarySeparatorItem.button?.window?.frame.minX)
        let toggleScreen = toggleItem.button?.window?.screen
        let primaryScreen = primarySeparatorItem.button?.window?.screen
        let mouseScreen = activeMouseScreen()
        let toggleScreenVisibleWidth = asDouble(toggleScreen?.visibleFrame.width)
        let primaryScreenVisibleWidth = asDouble(primaryScreen?.visibleFrame.width)
        let mouseScreenVisibleWidth = asDouble(mouseScreen?.visibleFrame.width)
        let toggleScreenVisibleMaxX = asDouble(toggleScreen?.visibleFrame.maxX)
        let primaryScreenVisibleMaxX = asDouble(primaryScreen?.visibleFrame.maxX)
        let mouseScreenVisibleMaxX = asDouble(mouseScreen?.visibleFrame.maxX)

        func rawWidth(_ visibleMaxX: Double?, _ primaryMinX: Double?) -> Double? {
            guard let visibleMaxX, let primaryMinX else {
                return nil
            }
            return visibleMaxX - primaryMinX
        }

        let scan = scanScreen(toggleScreen ?? mouseScreen, toggleMinX: toggleX)

        return HiddenBarGeometrySnapshot(
            toggleMinX: toggleX,
            primaryMinX: primaryX,
            secondaryMinX: secondaryX,
            toggleScreenName: toggleScreen?.localizedName,
            primaryScreenName: primaryScreen?.localizedName,
            mouseScreenName: mouseScreen?.localizedName,
            toggleScreenVisibleWidth: toggleScreenVisibleWidth,
            primaryScreenVisibleWidth: primaryScreenVisibleWidth,
            mouseScreenVisibleWidth: mouseScreenVisibleWidth,
            toggleScreenVisibleMaxX: toggleScreenVisibleMaxX,
            primaryScreenVisibleMaxX: primaryScreenVisibleMaxX,
            mouseScreenVisibleMaxX: mouseScreenVisibleMaxX,
            allScreenVisibleWidths: NSScreen.screens.map { Double($0.visibleFrame.width) },
            allScreenVisibleMaxX: NSScreen.screens.map { Double($0.visibleFrame.maxX) },
            rawWidthFromToggleScreen: rawWidth(toggleScreenVisibleMaxX, primaryX),
            rawWidthFromPrimaryScreen: rawWidth(primaryScreenVisibleMaxX, primaryX),
            rawWidthFromMouseScreen: rawWidth(mouseScreenVisibleMaxX, primaryX),
            realItemCount: scan?.items.count,
            realHideableItemCount: scan?.hideableItemCount,
            realLeftmostMinX: scan?.leftmostMinX,
            notchDetected: scan?.hasNotch
        )
    }

    private func compactPrimaryMinX() -> Double? {
        MarkerGeometry.compactMinX(
            currentMinX: asDouble(primarySeparatorItem.button?.window?.frame.minX),
            currentWidth: asDouble(primarySeparatorItem.button?.window?.frame.width),
            compactWidth: Double(primaryExpandedLength(for: preferencesStore.config))
        )
    }

    @discardableResult
    private func scanScreen(_ screen: NSScreen?, toggleMinX: Double?) -> MenuBarDiscoverySnapshot? {
        guard let screen else {
            return nil
        }
        let scan = services.discovery.snapshot(
            on: MenuBarDisplayHandle(rawValue: screen.displayID),
            toggleMinX: toggleMinX
        )
        lastScan = scan
        return scan
    }

    private func activeMouseScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }

    private func revealTargetScreen() -> NSScreen? {
        // The status item window is authoritative when macOS has placed the
        // menu extra on a display. Mouse/main are only startup fallbacks.
        toggleItem.button?.window?.screen ?? activeMouseScreen() ?? NSScreen.main
    }

    private func shouldRevealBelowMenuBar(on screen: NSScreen?) -> Bool {
        let hasNotch: Bool
        if let screen {
            hasNotch = scanScreen(screen, toggleMinX: asDouble(toggleItem.button?.window?.frame.minX))?.hasNotch ?? false
        } else {
            hasNotch = false
        }
        return preferencesStore.config.resolvedRevealMode(hasNotch: hasNotch) == .belowMenuBar
    }

    private var revealAppearanceUsesBelowMenuBar: Bool {
        switch preferencesStore.config.configuredRevealMode {
        case .belowMenuBar:
            return true
        case .inline:
            return false
        case .automatic:
            return lastScan?.hasNotch ?? false
        }
    }

    private func shouldPauseCollapseForInteraction() -> Bool {
        if NSEvent.pressedMouseButtons != 0 {
            return true
        }
        return isMouseInMenuBarBand()
    }

    private func isMouseInMenuBarBand() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            MarkerGeometry.isPointInMenuBarBand(
                mouseLocation,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    private func scheduleGeometryRefresh() {
        geometryRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.preferencesStore.recordGeometrySnapshot(self.currentGeometrySnapshot())
            if self.toggleState == .collapsed {
                _ = self.collapse()
            } else {
                let isValid = self.currentMarkerOrderValid()
                self.preferencesStore.recordMarkerOrder(valid: isValid)
                self.preferencesStore.recordGeometryReadable(isValid, reason: isValid ? nil : "geometry_unreadable")
            }
        }
        geometryRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func applyRepairState(_ failure: MenuBarCollapseFailure) {
        autoCollapseWorkItem?.cancel()
        record("marker_repair_entered", level: .warning, fields: ["reason": failure.rawValue])
        applyExpandedLengths()
        updateToggleAppearance()
    }

    private func perform(_ transition: MenuBarTransition) {
        for effect in transition.effects {
            switch effect {
            case .attemptCollapse:
                _ = collapse()
            case .applyExpanded:
                applyExpandedState()
            case .reapplyExpanded:
                applyExpandedLengths()
            case .applyCollapsed(let plan):
                applyCollapsedState(plan)
            case .enterRepair(let failure):
                applyRepairState(failure)
            }
        }
    }

    private func record(
        _ name: String,
        level: MenuBarDiagnosticLevel = .info,
        fields: [String: String] = [:]
    ) {
        services.diagnostics.record(
            MenuBarDiagnosticEvent(name: name, level: level, fields: fields)
        )
    }

    @objc private func handleToggleButton(_ sender: NSStatusBarButton?) {
        guard let event = NSApp.currentEvent else {
            toggleReveal()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            if event.modifierFlags.contains(.option) {
                temporarilyRevealMarkers()
            } else {
                toggleItem.menu = contextMenu
                toggleItem.button?.performClick(nil)
                toggleItem.menu = nil
            }
            return
        }

        toggleReveal()
    }

    @objc private func menuExpand() {
        record("context_menu_command", fields: ["command": "expand"])
        expand()
    }

    @objc private func menuCollapse() {
        record("context_menu_command", fields: ["command": "collapse"])
        _ = collapse()
    }

    @objc private func menuOpenIceBar() {
        record("context_menu_command", fields: ["command": "open_ice_bar"])
        openIceBar()
    }

    @objc private func menuOpenSettings() {
        record("context_menu_command", fields: ["command": "open_settings"])
        openSettings()
    }

    @objc private func menuOpenDiagnostics() {
        record("context_menu_command", fields: ["command": "open_diagnostics"])
        openDiagnostics()
    }

    @objc private func menuRevealMarkers() {
        record("context_menu_command", fields: ["command": "reveal_markers"])
        temporarilyRevealMarkers()
    }

    @objc private func menuQuit() {
        record("context_menu_command", fields: ["command": "quit"])
        NSApplication.shared.terminate(nil)
    }
}
