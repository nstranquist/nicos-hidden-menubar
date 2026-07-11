import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class StatusSectionController: NSObject {
    private static let deferredCollapseRetryDelay: TimeInterval = 0.75

    private enum ToggleState {
        case expanded
        case collapsed
    }

    private let preferencesStore: PreferencesStore
    private let profileStore: ProfileStore
    private let openSettings: () -> Void
    private let openDiagnostics: () -> Void
    private let openOnboarding: () -> Void

    private let toggleItem: NSStatusItem
    private let primarySeparatorItem: NSStatusItem
    private let secondarySeparatorItem: NSStatusItem
    private let contextMenu = NSMenu()

    private var toggleState: ToggleState = .expanded
    private var lastToggleAt = Date.distantPast
    private var lastScan: MenuBarItemScanner.Scan?
    private lazy var iceBar = IceBarPanel { [weak self] windowID in
        self?.activateHiddenItem(windowID)
    }
    private var autoCollapseWorkItem: DispatchWorkItem?
    private var revealWorkItem: DispatchWorkItem?
    private var geometryRefreshWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    init(
        preferencesStore: PreferencesStore = .shared,
        profileStore: ProfileStore = .shared,
        openSettings: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void,
        openOnboarding: @escaping () -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.profileStore = profileStore
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
        HiddenMenuBarTelemetry.menuBar.info("Status items configured")
    }

    func toggle() {
        guard Date().timeIntervalSince(lastToggleAt) >= 0.2 else {
            HiddenMenuBarTelemetry.menuBar.debug("Toggle ignored by debounce")
            return
        }
        lastToggleAt = Date()
        HiddenMenuBarTelemetry.menuBar.info("Toggle requested")
        switch toggleState {
        case .expanded:
            _ = collapse()
        case .collapsed:
            expand()
        }
    }

    /// User-facing reveal action. Automatic mode keeps the classic compact
    /// inline behavior on regular displays and uses the below-menu-bar panel
    /// where a notch splits the available menu-bar space.
    func toggleReveal() {
        let screen = revealTargetScreen()
        if shouldRevealBelowMenuBar(on: screen) {
            guard Date().timeIntervalSince(lastToggleAt) >= 0.2 else {
                HiddenMenuBarTelemetry.menuBar.debug("Reveal ignored by debounce")
                return
            }
            lastToggleAt = Date()
            openIceBar(on: screen)
        } else {
            toggle()
        }
    }

    func expand() {
        autoCollapseWorkItem?.cancel()
        toggleState = .expanded
        HiddenMenuBarTelemetry.menuBar.info("Expanding menu bar section")
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
            HiddenMenuBarTelemetry.menuBar.warning("Collapse rejected by invalid marker order")
            safeRepairPath()
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
            HiddenMenuBarTelemetry.menuBar.warning("Collapse rejected by unreadable geometry")
            preferencesStore.recordGeometryReadable(false, reason: "geometry_unreadable")
            safeRepairPath()
            return false
        }

        preferencesStore.recordGeometryReadable(true)
        autoCollapseWorkItem?.cancel()
        toggleState = .collapsed
        HiddenMenuBarTelemetry.menuBar.info("Collapsing menu bar section")
        primarySeparatorItem.length = CGFloat(collapseWidth)
        secondarySeparatorItem.length = secondaryExpandedLength(for: config)
        updateMarkerTitles()
        updateToggleAppearance()
        configureMenu()
        NSApplication.shared.setActivationPolicy(.accessory)
        scheduleCollapseVerification(toggleMinX: toggleX, screen: toggleItem.button?.window?.screen)
        return true
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
                HiddenMenuBarTelemetry.menuBar.warning(
                    "Collapse did not push any item off the visible edge (notch=\(scan.hasNotch))"
                )
            }
        }
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
                HiddenMenuBarTelemetry.menuBar.warning("Reveal deferred: status item geometry is not ready")
            }
            return
        }
        HiddenMenuBarTelemetry.menuBar.info("Opening below-menu-bar reveal panel")
        iceBar.toggle(near: anchor, on: screen)
    }

    /// Activate an item chosen in the IceBar. With the experimental mover enabled,
    /// move it into the visible section so it can be clicked; otherwise fall back
    /// to expanding the bar (safe, always works).
    private func activateHiddenItem(_ windowID: CGWindowID) {
        let movementEnabled = preferencesStore.config.isExperimentalItemMovementEnabled
        guard movementEnabled else {
            expand()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                if let toggleWindowID = self.toggleItem.button?.window.map({ CGWindowID($0.windowNumber) }) {
                    try await MenuBarItemMover.move(
                        windowID: windowID,
                        to: .rightOf(targetWindowID: toggleWindowID),
                        enabled: movementEnabled
                    )
                }
            } catch {
                HiddenMenuBarTelemetry.menuBar.error("IceBar activate move failed: \(String(describing: error))")
                self.expand()
            }
        }
    }

    func recomputeGeometry() {
        HiddenMenuBarTelemetry.menuBar.debug("Recomputing marker geometry")
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
        if toggleState == .collapsed {
            _ = collapse()
        } else {
            let isValid = currentMarkerOrderValid()
            preferencesStore.recordMarkerOrder(valid: isValid)
            if !isValid {
                safeRepairPath()
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
        HiddenMenuBarTelemetry.menuBar.info("Temporarily revealing markers")
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
        HiddenMenuBarTelemetry.menuBar.debug("Context menu rebuilt with SwiftUI rows")
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
        if toggleState == .collapsed {
            _ = collapse()
        } else {
            applyExpandedLengths()
        }
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
            HiddenMenuBarTelemetry.menuBar.debug("Auto-collapse delayed for pointer interaction")
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
    private func scanScreen(_ screen: NSScreen?, toggleMinX: Double?) -> MenuBarItemScanner.Scan? {
        guard let screen else {
            return nil
        }
        let scan = MenuBarItemScanner.scan(screen: screen, toggleMinX: toggleMinX)
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

    private func safeRepairPath() {
        autoCollapseWorkItem?.cancel()
        toggleState = .expanded
        HiddenMenuBarTelemetry.menuBar.warning("Entering marker repair path")
        applyExpandedLengths()
        updateToggleAppearance()
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
        HiddenMenuBarTelemetry.commandExecution.info("Context menu command: expand")
        expand()
    }

    @objc private func menuCollapse() {
        HiddenMenuBarTelemetry.commandExecution.info("Context menu command: collapse")
        _ = collapse()
    }

    @objc private func menuOpenIceBar() {
        HiddenMenuBarTelemetry.commandExecution.info("Context menu command: open IceBar")
        openIceBar()
    }

    @objc private func menuOpenSettings() {
        HiddenMenuBarTelemetry.commandExecution.info("Context menu command: open settings")
        openSettings()
    }

    @objc private func menuOpenDiagnostics() {
        HiddenMenuBarTelemetry.commandExecution.info("Context menu command: open diagnostics")
        openDiagnostics()
    }

    @objc private func menuRevealMarkers() {
        HiddenMenuBarTelemetry.commandExecution.info("Context menu command: reveal markers")
        temporarilyRevealMarkers()
    }

    @objc private func menuQuit() {
        HiddenMenuBarTelemetry.appLifecycle.info("Quit requested from context menu")
        NSApplication.shared.terminate(nil)
    }
}
