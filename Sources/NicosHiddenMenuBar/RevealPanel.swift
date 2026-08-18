import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Non-activating status panel that can still become key for drag sessions.
/// Plain `NSPanel` + `.nonactivatingPanel` often refuses to start SwiftUI/AppKit
/// drags, which made panel reorder feel completely dead.
private final class RevealNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Below-menu-bar **Reveal Panel**: floating chrome that lists currently hidden
/// menu bar items. Inspired by the same product shape as other menu-bar managers
/// (e.g. Ice's panel), but named and owned as our own surface — not a product clone.
@MainActor
final class RevealPanel {
    private var panel: NSPanel?
    private let model: RevealPanelModel
    private let onActivate: (CGWindowID) -> Void
    /// Live menu-bar reorder after a successful panel ⌘-drag (windowID, beforeWindowID?).
    private let onReorder: ((CGWindowID, CGWindowID?) -> Void)?
    /// Panel tile unhide into the regular menu bar. Completion is `true` only when
    /// the live move succeeded — panel list must not drop the tile on failure.
    private let onUnhide: ((CGWindowID, @escaping (Bool) -> Void) -> Void)?
    /// External menu-bar window dropped onto the open panel to hide.
    private let onHideFromMenuBar: ((CGWindowID) -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onPerformance: ((RevealPerformanceSample) -> Void)?
    private var reloadTask: Task<Void, Never>?
    private var externalLocalMonitor: Any?
    private var externalGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var trackedExternalWindowID: CGWindowID?
    private var hasCompletedPresentation = false

    init(
        discovery: any MenuBarItemDiscovering,
        capture: any MenuBarItemCapturing,
        onActivate: @escaping (CGWindowID) -> Void,
        onReorder: ((CGWindowID, CGWindowID?) -> Void)? = nil,
        onUnhide: ((CGWindowID, @escaping (Bool) -> Void) -> Void)? = nil,
        onHideFromMenuBar: ((CGWindowID) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onPerformance: ((RevealPerformanceSample) -> Void)? = nil
    ) {
        self.model = RevealPanelModel(discovery: discovery, capture: capture)
        self.onActivate = onActivate
        self.onReorder = onReorder
        self.onUnhide = onUnhide
        self.onHideFromMenuBar = onHideFromMenuBar
        self.onOpenSettings = onOpenSettings
        self.onPerformance = onPerformance
    }

    /// Remove a panel tile by window id (only after a successful unhide move).
    func removePanelItem(windowID: CGWindowID) {
        model.items.removeAll { $0.item.handle.windowID == windowID }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Panel frame in screen coordinates (for cross-bar drop hit tests).
    var panelScreenFrame: CGRect? {
        panel?.frame
    }

    func toggle(
        near anchorMinX: Double?,
        on screen: NSScreen,
        laneBounds: MenuBarLaneBounds? = nil,
        parkedWindowIDs: [CGWindowID] = [],
        notch: NotchBandGeometry? = nil,
        overflow: MenuBarOverflowLayout? = nil,
        notchSupportEnabled: Bool = true
    ) {
        if isVisible {
            hide()
        } else {
            show(
                near: anchorMinX,
                on: screen,
                laneBounds: laneBounds,
                parkedWindowIDs: parkedWindowIDs,
                notch: notch,
                overflow: overflow,
                notchSupportEnabled: notchSupportEnabled
            )
        }
    }

    func show(
        near anchorMinX: Double?,
        on screen: NSScreen,
        laneBounds: MenuBarLaneBounds? = nil,
        parkedWindowIDs: [CGWindowID] = [],
        notch: NotchBandGeometry? = nil,
        overflow: MenuBarOverflowLayout? = nil,
        notchSupportEnabled: Bool = true,
        alwaysShowNamespaces: Set<String> = []
    ) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let warm = hasCompletedPresentation
        let panel = panel ?? makePanel()
        self.panel = panel

        reloadTask?.cancel()
        // Open shell immediately with last/empty content, then stream items.
        positionPanel(panel, near: anchorMinX, on: screen)

        let bounds = laneBounds ?? MenuBarLaneBounds(
            toggleX: anchorMinX,
            primaryX: nil,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: Double(screen.frame.minX),
            screenMaxX: Double(screen.frame.maxX)
        )
        let resolvedNotch = notch ?? (notchSupportEnabled ? NotchBandGeometry.forScreen(screen) : nil)
        let resolvedOverflow = overflow
            ?? (notchSupportEnabled ? MenuBarOverflowLayout.forScreen(screen) : nil)

        installExternalDragMonitorIfNeeded()
        installEscapeMonitorIfNeeded()
        // Become key so Escape / typing reach us when the panel is frontmost.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        let shellItemCount = model.items.count
        let shellMilliseconds = max(
            0,
            (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
        reloadTask = Task { [weak self] in
            guard let self else { return }
            await model.reload(
                on: screen,
                laneBounds: bounds,
                parkedWindowIDs: parkedWindowIDs,
                notch: resolvedNotch,
                overflow: resolvedOverflow,
                notchSupportEnabled: notchSupportEnabled,
                alwaysShowNamespaces: alwaysShowNamespaces
            )
            guard !Task.isCancelled else { return }
            positionPanel(panel, near: anchorMinX, on: screen)
            let contentMilliseconds = max(
                shellMilliseconds,
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
            hasCompletedPresentation = true
            onPerformance?(
                RevealPerformanceSample(
                    shellMilliseconds: shellMilliseconds,
                    contentMilliseconds: contentMilliseconds,
                    shellItemCount: shellItemCount,
                    itemCount: model.items.count,
                    imageCount: model.items.filter { $0.image != nil }.count,
                    accessibilityTrusted: PrivacyPermissions.isAccessibilityTrusted,
                    screenRecordingGranted: MenuBarItemImageCapture.hasScreenRecordingPermission(),
                    warm: warm,
                    observedAt: hiddenBarTimestampString(Date())
                )
            )
        }
    }

    func refreshIfVisible(
        near anchorMinX: Double?,
        on screen: NSScreen,
        laneBounds: MenuBarLaneBounds? = nil,
        parkedWindowIDs: [CGWindowID] = [],
        notch: NotchBandGeometry? = nil,
        overflow: MenuBarOverflowLayout? = nil,
        notchSupportEnabled: Bool = true,
        alwaysShowNamespaces: Set<String> = []
    ) {
        guard isVisible else { return }
        show(
            near: anchorMinX,
            on: screen,
            laneBounds: laneBounds,
            parkedWindowIDs: parkedWindowIDs,
            notch: notch,
            overflow: overflow,
            notchSupportEnabled: notchSupportEnabled,
            alwaysShowNamespaces: alwaysShowNamespaces
        )
    }

    func hide() {
        reloadTask?.cancel()
        reloadTask = nil
        removeExternalDragMonitor()
        removeEscapeMonitor()
        panel?.orderOut(nil)
        model.prepareForHide()
        // Defensive: if a hide-move was mid-flight, ensure the cursor is free.
        MouseCursorBridge.forceRestore(to: MouseCursorBridge.location)
    }

    func presentStatus(_ message: String) {
        model.statusMessage = message
    }

    private func installExternalDragMonitorIfNeeded() {
        guard externalGlobalMonitor == nil else { return }
        // Global: cmd+press on menu-bar band, release over panel → hide into lane.
        externalGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        ) { [weak self] event in
            self?.handleExternalCrossBarEvent(event)
        }
        externalLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        ) { [weak self] event in
            self?.handleExternalCrossBarEvent(event)
            return event
        }
    }

    /// Escape dismisses the reveal panel (local when we are key; global when another
    /// app is frontmost but the panel is still on screen).
    private func installEscapeMonitorIfNeeded() {
        guard escapeLocalMonitor == nil else { return }
        let isEscape: (NSEvent) -> Bool = { event in
            event.type == .keyDown && event.keyCode == 53 // kVK_Escape
        }
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard isEscape(event) else { return event }
            self?.hide()
            return nil // swallow
        }
        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard isEscape(event) else { return }
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeLocalMonitor {
            NSEvent.removeMonitor(escapeLocalMonitor)
            self.escapeLocalMonitor = nil
        }
        if let escapeGlobalMonitor {
            NSEvent.removeMonitor(escapeGlobalMonitor)
            self.escapeGlobalMonitor = nil
        }
    }

    private func handleExternalCrossBarEvent(_ event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let loc = NSEvent.mouseLocation
        if !command {
            if event.type == .leftMouseUp || event.type == .leftMouseDragged {
                // keep tracking until up clears
            }
            if event.type == .leftMouseUp {
                trackedExternalWindowID = nil
                presentStatusIfVisible(nil)
            }
            return
        }
        switch event.type {
        case .leftMouseDown:
            if let panelFrame = panelScreenFrame, panelFrame.contains(loc) {
                trackedExternalWindowID = nil
                return
            }
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }),
                  MenuBarBridging.isInMenuBarBand(
                    loc,
                    screen: screen.frame,
                    visible: screen.visibleFrame
                  ),
                  let windowID = MenuBarBridging.windowIDAtScreenPoint(loc)
            else {
                trackedExternalWindowID = nil
                return
            }
            trackedExternalWindowID = windowID
            presentStatusIfVisible("Drag into this panel and release to hide…")
        case .leftMouseDragged:
            guard trackedExternalWindowID != nil else { return }
            if let panelFrame = panelScreenFrame, panelFrame.contains(loc) {
                presentStatusIfVisible("Release to hide into the panel")
            } else {
                presentStatusIfVisible("Drag into this panel and release to hide…")
            }
        case .leftMouseUp:
            defer {
                trackedExternalWindowID = nil
            }
            guard let windowID = trackedExternalWindowID,
                  let panelFrame = panelScreenFrame,
                  panelFrame.contains(loc)
            else {
                presentStatusIfVisible(nil)
                return
            }
            onHideFromMenuBar?(windowID)
        default:
            break
        }
    }

    private func presentStatusIfVisible(_ message: String?) {
        guard isVisible else { return }
        model.statusMessage = message
    }

    private func removeExternalDragMonitor() {
        if let externalGlobalMonitor {
            NSEvent.removeMonitor(externalGlobalMonitor)
            self.externalGlobalMonitor = nil
        }
        if let externalLocalMonitor {
            NSEvent.removeMonitor(externalLocalMonitor)
            self.externalLocalMonitor = nil
        }
        trackedExternalWindowID = nil
    }

    private func makePanel() -> NSPanel {
        // Subclass allows key when needed so SwiftUI/AppKit drag sessions can start
        // from a nonactivating menubar utility panel.
        let panel = RevealNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        // canJoinAllSpaces and moveToActiveSpace are mutually exclusive.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = RevealPanelView(
            model: model,
            onActivate: { [weak self] windowID in
                self?.onActivate(windowID)
            },
            onReorder: { [weak self] draggedID, beforeID in
                self?.onReorder?(draggedID, beforeID)
            },
            onUnhide: { [weak self] windowID, completion in
                guard let self, let onUnhide = self.onUnhide else {
                    completion(false)
                    return
                }
                onUnhide(windowID, completion)
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func positionPanel(_ panel: NSPanel, near anchorMinX: Double?, on screen: NSScreen) {
        let count = model.filteredItems.isEmpty ? model.items.count : model.filteredItems.count
        let layout = RevealPanelLayout.calculate(
            itemCount: max(0, count),
            visibleFrame: screen.visibleFrame
        )
        model.columnCount = layout.columnCount
        model.needsScroll = layout.needsScroll
        model.showsSearch = layout.showsSearch
        let menuBarBottom = screen.visibleFrame.maxY
        let y = max(screen.visibleFrame.minY + 6, menuBarBottom - layout.height - 6)
        let anchor = CGFloat(anchorMinX ?? Double(screen.frame.midX))
        var x = anchor - layout.width / 2
        x = max(screen.visibleFrame.minX + 6, min(x, screen.visibleFrame.maxX - layout.width - 6))
        panel.setFrame(NSRect(x: x, y: y, width: layout.width, height: layout.height), display: true)
    }
}

struct RevealPanelLayout: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let columnCount: Int
    /// When false, SwiftUI should not wrap the grid in a ScrollView.
    let needsScroll: Bool
    /// Show search only for large sets (not for typical 3–12 item hides).
    let showsSearch: Bool

    /// Tile metrics must match `RevealPanelView` cell size so the panel height fits
    /// content without an inner scroll region in the common case.
    static let itemWidth: CGFloat = 80
    static let rowHeight: CGFloat = 54
    static let chromeWidth: CGFloat = 24
    static let chromeHeight: CGFloat = 20
    static let searchHeight: CGFloat = 32
    static let statusHeight: CGFloat = 20
    /// Prefer one row up to this many columns before wrapping.
    static let maxColumnsPreferred = 10
    /// Search field only when item count exceeds this.
    static let searchThreshold = 14

    static func calculate(itemCount: Int, visibleFrame: CGRect) -> RevealPanelLayout {
        let horizontalMargin: CGFloat = 16
        let verticalMargin: CGFloat = 32
        let count = max(0, itemCount)
        let showsSearch = count > searchThreshold
        let searchH: CGFloat = showsSearch ? searchHeight : 0
        let statusH = statusHeight
        let maxWidth = max(180, visibleFrame.width - horizontalMargin)
        let maxColumns = max(
            1,
            min(maxColumnsPreferred, Int((maxWidth - chromeWidth) / itemWidth))
        )
        // Use as many columns as needed so we stay on one row when possible.
        let columnCount = count == 0 ? 1 : min(maxColumns, max(1, count))
        let rowCount = count == 0 ? 1 : max(1, Int(ceil(Double(count) / Double(columnCount))))
        let width = min(
            maxWidth,
            max(180, CGFloat(columnCount) * itemWidth + chromeWidth)
        )
        let naturalHeight =
            CGFloat(rowCount) * rowHeight + chromeHeight + searchH + statusH
        // Allow a tall panel before scrolling — only extreme counts should scroll.
        let maxHeight = max(100, min(520, visibleFrame.height - verticalMargin))
        let needsScroll = naturalHeight > maxHeight + 0.5
        return RevealPanelLayout(
            width: width,
            height: min(maxHeight, max(64, naturalHeight)),
            columnCount: columnCount,
            needsScroll: needsScroll,
            showsSearch: showsSearch
        )
    }
}

// MARK: - Panel reorder (pure)

enum RevealPanelReorder {
    struct Result {
        var items: [MenuBarCapturedItem]
        var draggedWindowID: CGWindowID
        var beforeWindowID: CGWindowID?
    }

    /// Move `draggedKey` so it lands immediately before `beforeKey` (or at end if nil).
    static func move(
        items: [MenuBarCapturedItem],
        draggedKey: String,
        beforeKey: String?
    ) -> Result? {
        guard let from = items.firstIndex(where: { $0.item.identity.key == draggedKey }) else {
            return nil
        }
        if let beforeKey, beforeKey == draggedKey { return nil }
        let beforeWindowID = beforeKey.flatMap { key in
            items.first(where: { $0.item.identity.key == key })?.item.handle.windowID
        }
        var next = items
        let moved = next.remove(at: from)
        let draggedWindowID = moved.item.handle.windowID
        if let beforeKey, let to = next.firstIndex(where: { $0.item.identity.key == beforeKey }) {
            next.insert(moved, at: to)
        } else {
            next.append(moved)
        }
        // No-op if order unchanged.
        if next.map(\.item.identity.key) == items.map(\.item.identity.key) {
            return nil
        }
        return Result(
            items: next,
            draggedWindowID: draggedWindowID,
            beforeWindowID: beforeWindowID
        )
    }
}

// MARK: - Drop preview (pure)

/// Maps a hover target key to an insertion index for landing-line preview.
enum RevealPanelDropPreview: Equatable, Sendable {
    /// Insertion index in the **display** order (0…count after removing dragged).
    /// `beforeKey == nil` means append at the end (rightmost).
    static func insertionIndex(
        orderedKeys: [String],
        draggedKey: String,
        beforeKey: String?
    ) -> Int {
        let keys = orderedKeys.filter { $0 != draggedKey }
        guard !keys.isEmpty else { return 0 }
        if let beforeKey, let idx = keys.firstIndex(of: beforeKey) {
            return idx
        }
        return keys.count
    }

    /// Whether `beforeKey` is a valid landing highlight for `draggedKey`.
    static func shouldHighlightTarget(draggedKey: String?, beforeKey: String) -> Bool {
        guard let draggedKey, !draggedKey.isEmpty, draggedKey != CrossBarDropPolicy.cancelSentinel else {
            return false
        }
        return draggedKey != beforeKey
    }

    /// Dock-like horizontal shifts (points) for each key while dragging.
    /// Items open a gap at `insertIndex` and close the hole left by the source.
    static func horizontalShifts(
        orderedKeys: [String],
        draggedKey: String,
        insertIndex: Int,
        gap: CGFloat
    ) -> [String: CGFloat] {
        guard let from = orderedKeys.firstIndex(of: draggedKey) else { return [:] }
        var remaining = orderedKeys
        remaining.remove(at: from)
        let clampedInsert = min(max(0, insertIndex), remaining.count)
        var shifts: [String: CGFloat] = [draggedKey: 0]
        for (i, key) in remaining.enumerated() {
            var shift: CGFloat = 0
            // Close hole: items that were right of the source slide left.
            if let original = orderedKeys.firstIndex(of: key), original > from {
                shift -= gap
            }
            // Open gap at insertion point.
            if i >= clampedInsert {
                shift += gap
            }
            shifts[key] = shift
        }
        return shifts
    }

    /// Resolve drop against a tile using local X (left half = before, right half = after).
    static func beforeKeyForTileDrop(
        orderedKeys: [String],
        draggedKey: String,
        targetKey: String,
        dropXInTile: CGFloat,
        tileWidth: CGFloat
    ) -> String? {
        guard tileWidth > 0,
              let targetIdx = orderedKeys.firstIndex(of: targetKey)
        else { return targetKey }
        let dropAfter = dropXInTile > tileWidth * 0.5
        if !dropAfter {
            return targetKey // insert before target
        }
        // Insert after target → before the next key, or nil for end.
        let next = targetIdx + 1
        if next < orderedKeys.count {
            let nextKey = orderedKeys[next]
            return nextKey == draggedKey
                ? (next + 1 < orderedKeys.count ? orderedKeys[next + 1] : nil)
                : nextKey
        }
        return nil // end of list
    }
}

// MARK: - Cross-bar drop classification (pure)

enum CrossBarDropKind: String, Equatable, Sendable {
    /// Reorder within the panel (before a tile or at end).
    case panelReorder
    /// Panel item → visible menu bar (unhide).
    case unhideToMenuBar
    /// External menu-bar item → hidden lane / park (hide).
    case hideIntoPanel
}

enum CrossBarDropPolicy {
    /// Drag started without ⌘ — drop handlers ignore this payload.
    static let cancelSentinel = "__reveal_panel_drag_cancel__"

    /// Classify a completed drop. Pure so tests cover fail-closed paths.
    static func classify(
        draggedFromPanel: Bool,
        dropOnUnhideZone: Bool,
        dropOnPanelTileOrBackground: Bool,
        dropOnMenuBarBand: Bool
    ) -> CrossBarDropKind? {
        if draggedFromPanel {
            if dropOnUnhideZone || dropOnMenuBarBand {
                return .unhideToMenuBar
            }
            if dropOnPanelTileOrBackground {
                return .panelReorder
            }
            return nil
        }
        // External (menu bar) drag.
        if dropOnPanelTileOrBackground || dropOnUnhideZone {
            return .hideIntoPanel
        }
        return nil
    }

    /// Panel list mutation is success-gated: only remove after live move OK.
    static func shouldRemovePanelItemAfterUnhide(moveSucceeded: Bool) -> Bool {
        moveSucceeded
    }
}

// MARK: - Presentation refine (pure)

/// Filters / collapses Reveal Panel noise so the panel is usable without hunting
/// through six identical “Control Center N” tiles.
enum RevealPanelPresentation {
    /// Drop system Control Center / Siri modules unless we explicitly parked them
    /// **or** they sit under the notch (those are exactly the overflow icons users
    /// need). Generic empty-title CC peers collapse to at most one when parked.
    static func refine(
        _ items: [MenuBarDiscoveredItem],
        parkedWindowIDs: Set<CGWindowID>,
        keepWindowIDs: Set<CGWindowID> = []
    ) -> [MenuBarDiscoveredItem] {
        var result: [MenuBarDiscoveredItem] = []
        var includedGenericParkedCC = false
        let ordered = items.sorted { $0.frame.midX < $1.frame.midX }

        for item in ordered {
            let ns = item.identity.namespace.lowercased()
            let isControlCenter = ns.contains("controlcenter")
                || ns == ControlCenterModules.controlCenterNamespace
            let isSiri = ns.contains("siri")
            let parked = parkedWindowIDs.contains(item.handle.windowID)
            let keep = keepWindowIDs.contains(item.handle.windowID)

            if isSiri, !keep {
                // Never useful unless notch support explicitly kept it.
                continue
            }

            if isControlCenter {
                // Keep under-notch / parked CC modules; drop the rest of the noise.
                guard parked || keep else { continue }
                let module = item.identity.moduleID ?? "module"
                let isGeneric = module == "module" || module.isEmpty
                if isGeneric, !keep {
                    if includedGenericParkedCC { continue }
                    includedGenericParkedCC = true
                }
                result.append(item)
                continue
            }

            result.append(item)
        }
        return result
    }
}

/// Panel tile with its reveal section (notch / always-hidden / hidden).
struct RevealPanelEntry: Identifiable, Sendable {
    var item: MenuBarCapturedItem
    var section: RevealPanelSection

    var id: String { item.item.identity.key }
    var key: String { item.item.identity.key }
}

/// Observable model holding the captured hidden items for the RevealPanel.
@MainActor
final class RevealPanelModel: ObservableObject {
    @Published var items: [MenuBarCapturedItem] = []
    /// Parallel section tags for `items` (same order / length).
    @Published var sections: [RevealPanelSection] = []
    @Published var usesImages = false
    @Published var query: String = ""
    @Published var columnCount = 1
    @Published var needsScroll = false
    @Published var showsSearch = false
    @Published var isLoading = false
    @Published var statusMessage: String?

    private let discovery: any MenuBarItemDiscovering
    private let capture: any MenuBarItemCapturing
    /// Last classification inputs so capture callbacks can re-tag sections.
    private var lastSectionByKey: [String: RevealPanelSection] = [:]

    init(
        discovery: any MenuBarItemDiscovering,
        capture: any MenuBarItemCapturing
    ) {
        self.discovery = discovery
        self.capture = capture
    }

    var filteredItems: [MenuBarCapturedItem] {
        filteredEntries.map(\.item)
    }

    var filteredEntries: [RevealPanelEntry] {
        let paired = zip(items, sections).map { RevealPanelEntry(item: $0.0, section: $0.1) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base: [RevealPanelEntry]
        if q.isEmpty {
            base = paired
        } else {
            base = paired.filter {
                $0.item.item.displayName.lowercased().contains(q)
                    || $0.item.item.identity.key.lowercased().contains(q)
            }
        }
        return base.sorted {
            if $0.section != $1.section {
                return $0.section < $1.section
            }
            return $0.item.item.frame.midX < $1.item.item.frame.midX
        }
    }

    /// Grouped sections for the multi-section panel chrome.
    var groupedSections: [(section: RevealPanelSection, entries: [RevealPanelEntry])] {
        let ordered = filteredEntries
        var groups: [(RevealPanelSection, [RevealPanelEntry])] = []
        for entry in ordered {
            if let last = groups.last, last.0 == entry.section {
                groups[groups.count - 1].1.append(entry)
            } else {
                groups.append((entry.section, [entry]))
            }
        }
        return groups.map { (section: $0.0, entries: $0.1) }
    }

    /// Reorder panel tiles by identity key (⌘-drag). Returns the moved window id
    /// and the window id it should sit left of (nil = end), for live menu-bar move.
    @discardableResult
    func reorder(draggedKey: String, beforeKey: String?) -> (dragged: CGWindowID, before: CGWindowID?)? {
        guard let result = RevealPanelReorder.move(
            items: items,
            draggedKey: draggedKey,
            beforeKey: beforeKey
        ) else { return nil }
        // Keep section tags aligned with the reordered item list.
        let sectionByKey = Dictionary(uniqueKeysWithValues: zip(items.map(\.item.identity.key), sections))
        items = result.items
        sections = result.items.map { sectionByKey[$0.item.identity.key] ?? .hidden }
        return (result.draggedWindowID, result.beforeWindowID)
    }

    func reload(
        on screen: NSScreen,
        laneBounds: MenuBarLaneBounds,
        parkedWindowIDs: [CGWindowID] = [],
        notch: NotchBandGeometry? = nil,
        overflow: MenuBarOverflowLayout? = nil,
        notchSupportEnabled: Bool = true,
        alwaysShowNamespaces: Set<String> = []
    ) async {
        await reload(
            on: MenuBarDisplayHandle(rawValue: screen.displayID),
            laneBounds: laneBounds,
            parkedWindowIDs: parkedWindowIDs,
            excludingOwnerPID: ProcessInfo.processInfo.processIdentifier,
            notch: notch,
            overflow: overflow ?? (notchSupportEnabled ? MenuBarOverflowLayout.forScreen(screen) : nil),
            notchSupportEnabled: notchSupportEnabled,
            alwaysShowNamespaces: alwaysShowNamespaces
        )
    }

    func reload(
        on display: MenuBarDisplayHandle,
        laneBounds: MenuBarLaneBounds,
        parkedWindowIDs: [CGWindowID] = [],
        excludingOwnerPID: Int32?,
        notch: NotchBandGeometry? = nil,
        overflow: MenuBarOverflowLayout? = nil,
        notchSupportEnabled: Bool = true,
        alwaysShowNamespaces: Set<String> = []
    ) async {
        isLoading = true
        statusMessage = nil
        var discovered = discovery.discoverItems(on: display)
        // Ensure collapse-parked windows appear even if midX is past the screen.
        // Same assigner as the main scan — do not fall back to app-only names.
        let known = Set(discovered.map(\.handle.windowID))
        let parkedInfos = parkedWindowIDs.compactMap { windowID -> MenuBarWindowInfo? in
            guard !known.contains(windowID) else { return nil }
            return MenuBarWindowInfo.read(windowID: windowID)
        }
        if !parkedInfos.isEmpty {
            discovered.append(
                contentsOf: LiveMenuBarDiscoveryService.discoveredItems(
                    from: parkedInfos,
                    axLabels: [],
                    appNameForPID: { pid in
                        guard pid != 0 else { return nil }
                        return NSRunningApplication(processIdentifier: pid)?.localizedName
                    }
                )
            )
        }
        let classified = RevealPanelModel.classifiedCandidates(
            discovered,
            laneBounds: laneBounds,
            parkedWindowIDs: Set(parkedWindowIDs),
            excludingOwnerPID: excludingOwnerPID,
            notch: notch,
            overflow: overflow,
            notchSupportEnabled: notchSupportEnabled,
            alwaysShowNamespaces: alwaysShowNamespaces
        )
        // Keep overflow windows through refine (CC modules often live there).
        let overflowIDs = Set(
            classified.filter { $0.section == .overflow }.map(\.item.handle.windowID)
        )
        let refinedItems = RevealPanelPresentation.refine(
            classified.map(\.item),
            parkedWindowIDs: Set(parkedWindowIDs),
            keepWindowIDs: overflowIDs
        )
        let refinedKeys = Set(refinedItems.map(\.identity.key))
        let refinedClassified = classified.filter { refinedKeys.contains($0.item.identity.key) }
        lastSectionByKey = Dictionary(
            uniqueKeysWithValues: refinedClassified.map { ($0.item.identity.key, $0.section) }
        )

        let overflowCount = refinedClassified.filter { $0.section == .overflow }.count
        let hiddenCount = refinedClassified.filter { $0.section == .hidden || $0.section == .alwaysHidden }.count
        if refinedClassified.isEmpty && !laneBounds.geometryUsable {
            statusMessage = "Markers need repair — right-click the chevron → Repair Marker Positions."
        } else if refinedClassified.isEmpty {
            statusMessage = notchSupportEnabled
                ? "No hidden or overflow items."
                : "No hidden items in the hidden lane."
        } else {
            var parts: [String] = []
            if hiddenCount > 0 { parts.append("\(hiddenCount) hidden") }
            if overflowCount > 0 {
                parts.append("\(overflowCount) overflow")
                // Off-screen extras can't be screen-captured — set expectations.
                parts.append("icons N/A off-screen")
            }
            statusMessage = parts.joined(separator: " · ") + " · Esc closes"
        }

        // Stable ordinals for anonymous overflow extras (pid 0 / no owner).
        let overflowKeys = refinedClassified
            .filter { $0.section == .overflow }
            .sorted { $0.item.frame.midX < $1.item.frame.midX }
            .map(\.item.identity.key)
        let overflowIndexByKey: [String: Int] = Dictionary(
            uniqueKeysWithValues: overflowKeys.enumerated().map { ($0.element, $0.offset + 1) }
        )

        // CAP-001: shell-first placeholders, then incremental icons.
        // Off-screen overflow often has no capturable image — placeholders are expected.
        await capture.captureIncremental(refinedItems, on: display) { [weak self] captured in
            guard let self, !Task.isCancelled else { return }
            self.usesImages = captured.contains { $0.image != nil }
            self.items = captured.map { entry in
                guard let idx = overflowIndexByKey[entry.item.identity.key] else {
                    return entry
                }
                let name = entry.item.displayName
                let anonymous = entry.item.ownerPID == 0
                    || name == "Menu extra"
                    || name == "Unknown"
                    || name.isEmpty
                guard anonymous else { return entry }
                var discovered = entry.item
                discovered.displayName = "Overflow \(idx)"
                return MenuBarCapturedItem(
                    item: discovered,
                    image: entry.image,
                    scale: entry.scale,
                    isPlaceholder: entry.isPlaceholder || entry.image == nil
                )
            }
            self.sections = self.items.map { self.lastSectionByKey[$0.item.identity.key] ?? .hidden }
        }
        guard !Task.isCancelled else { return }
        isLoading = false
    }

    func clear() {
        items.removeAll(keepingCapacity: false)
        sections.removeAll(keepingCapacity: false)
        lastSectionByKey.removeAll(keepingCapacity: false)
        usesImages = false
        query = ""
        columnCount = 1
        needsScroll = false
        showsSearch = false
        isLoading = false
        statusMessage = nil
    }

    /// Keep metadata for an immediate warm shell, but release this model's image
    /// references so the bounded capture cache remains the sole warm-image
    /// owner and can respond correctly to memory pressure.
    func prepareForHide() {
        items = items.map { entry in
            MenuBarCapturedItem(
                item: entry.item,
                image: nil,
                scale: entry.scale,
                isPlaceholder: true
            )
        }
        usesImages = false
        query = ""
        isLoading = false
        statusMessage = nil
    }

    struct ClassifiedItem: Equatable, Sendable {
        var item: MenuBarDiscoveredItem
        var section: RevealPanelSection
    }

    /// Hidden-lane + overflow candidates for the reveal panel.
    ///
    /// Uses the Ice-style primary…toggle lane when markers are on-screen.
    /// With notch/overflow support, also includes status extras cut off by the
    /// usable menu-bar strip (would appear on a wider display). Always includes
    /// collapse-parked window IDs. When geometry is unusable, falls back so the
    /// panel is never a dead end.
    nonisolated static func classifiedCandidates(
        _ items: [MenuBarDiscoveredItem],
        laneBounds: MenuBarLaneBounds,
        parkedWindowIDs: Set<CGWindowID> = [],
        excludingOwnerPID: Int32? = nil,
        notch: NotchBandGeometry? = nil,
        overflow: MenuBarOverflowLayout? = nil,
        notchSupportEnabled: Bool = true,
        alwaysShowNamespaces: Set<String> = []
    ) -> [ClassifiedItem] {
        let resolvedOverflow: MenuBarOverflowLayout? = {
            if let overflow { return overflow }
            guard let notch else { return nil }
            return MenuBarOverflowLayout(
                leftUsableMaxX: notch.leftUsableMaxX,
                rightUsableMinX: notch.rightUsableMinX,
                rightUsableMaxX: notch.rightUsableMaxX ?? notch.screenMaxX,
                visibleMaxX: notch.screenMaxX ?? notch.rightUsableMinX + 400,
                screenMinX: notch.screenMinX ?? 0,
                screenMaxX: notch.screenMaxX ?? (notch.rightUsableMinX + 400)
            )
        }()

        let withoutOwn = items.filter { item in
            guard item.ownerPID != excludingOwnerPID else { return false }
            return RevealPanelItemQuality.isUsablePanelItem(
                ownerName: item.ownerName,
                namespace: item.identity.namespace,
                displayName: item.displayName,
                frameWidth: Double(item.frame.width),
                frameHeight: Double(item.frame.height),
                itemMidX: Double(item.frame.midX),
                leftUsableMaxX: resolvedOverflow?.leftUsableMaxX ?? notch?.leftUsableMaxX
            )
        }

        if laneBounds.geometryUsable || (notchSupportEnabled && (notch != nil || overflow != nil)) {
            var result: [ClassifiedItem] = []
            for item in withoutOwn {
                let minX = Double(item.frame.minX)
                let maxX = Double(item.frame.maxX)
                let midX = Double(item.frame.midX)
                let parked = parkedWindowIDs.contains(item.handle.windowID)
                if let section = RevealPanelClassifier.section(
                    itemMinX: minX,
                    itemMaxX: maxX,
                    itemMidX: midX,
                    laneBounds: laneBounds,
                    notch: notch,
                    overflow: resolvedOverflow,
                    notchSupportEnabled: notchSupportEnabled,
                    isParked: parked
                ) {
                    result.append(ClassifiedItem(item: item, section: section))
                    continue
                }
                if parked {
                    result.append(ClassifiedItem(item: item, section: .hidden))
                    continue
                }
                // User-pinned apps: always list in Hidden even when fully visible.
                let ns = item.identity.namespace
                if alwaysShowNamespaces.contains(ns)
                    || alwaysShowNamespaces.contains(where: { ns.localizedCaseInsensitiveContains($0) })
                {
                    result.append(ClassifiedItem(item: item, section: .hidden))
                }
            }
            var seen = Set<CGWindowID>()
            return result.filter { seen.insert($0.item.handle.windowID).inserted }
        }

        // Repair fallback: show on-screen third-party items so the user can
        // still reach them while markers are fixed.
        return withoutOwn.compactMap { item in
            if parkedWindowIDs.contains(item.handle.windowID) {
                return ClassifiedItem(item: item, section: .hidden)
            }
            if let minX = laneBounds.screenMinX, let maxX = laneBounds.screenMaxX {
                guard Double(item.frame.midX) >= minX && Double(item.frame.midX) <= maxX else {
                    return nil
                }
            }
            if notchSupportEnabled,
               let layout = resolvedOverflow,
               layout.isOverflow(
                   itemMinX: Double(item.frame.minX),
                   itemMaxX: Double(item.frame.maxX),
                   itemMidX: Double(item.frame.midX)
               ) {
                return ClassifiedItem(item: item, section: .overflow)
            }
            return ClassifiedItem(item: item, section: .hidden)
        }
    }

    /// Hidden-lane candidates for the reveal panel (backward-compatible API).
    nonisolated static func hiddenCandidates(
        _ items: [MenuBarDiscoveredItem],
        laneBounds: MenuBarLaneBounds,
        parkedWindowIDs: Set<CGWindowID> = [],
        excludingOwnerPID: Int32? = nil,
        notch: NotchBandGeometry? = nil,
        notchSupportEnabled: Bool = true
    ) -> [MenuBarDiscoveredItem] {
        classifiedCandidates(
            items,
            laneBounds: laneBounds,
            parkedWindowIDs: parkedWindowIDs,
            excludingOwnerPID: excludingOwnerPID,
            notch: notch,
            notchSupportEnabled: notchSupportEnabled
        ).map(\.item)
    }

    /// Legacy entry used by tests that only pass a toggle x.
    nonisolated static func hiddenCandidates(
        _ items: [MenuBarDiscoveredItem],
        leftOfX: Double?,
        excludingOwnerPID: Int32? = nil
    ) -> [MenuBarDiscoveredItem] {
        // Wide on-screen bounds + primary far left preserve classic "left of toggle".
        hiddenCandidates(
            items,
            laneBounds: MenuBarLaneBounds(
                toggleX: leftOfX,
                primaryX: leftOfX.map { $0 - 100_000 },
                secondaryX: nil,
                alwaysHiddenEnabled: false,
                screenMinX: -1_000_000,
                screenMaxX: 1_000_000
            ),
            excludingOwnerPID: excludingOwnerPID
        )
    }
}

private struct RevealPanelView: View {
    @ObservedObject var model: RevealPanelModel
    let onActivate: (CGWindowID) -> Void
    let onReorder: (CGWindowID, CGWindowID?) -> Void
    /// Completion `true` only when live unhide succeeded — then drop the tile.
    let onUnhide: (CGWindowID, @escaping (Bool) -> Void) -> Void
    let onOpenSettings: () -> Void
    @State private var dropTargetKey: String?
    /// When true, landing is *after* `dropTargetKey` (right half of tile).
    @State private var dropAfterTarget = false
    @State private var draggingKey: String?
    @State private var unhideZoneTargeted = false
    @State private var hoveredKey: String?

    var body: some View {
        VStack(spacing: 6) {
            panelChrome
            if model.showsSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    TextField("Filter hidden items", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 6)
                Divider()
            }
            if model.filteredEntries.isEmpty {
                Text(model.isLoading ? "Loading…" : (model.items.isEmpty ? "No hidden items" : "No matches"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            } else if model.needsScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    sectionedItemGrid
                }
            } else {
                sectionedItemGrid
            }

            footerStatus
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .onDrop(of: [.text, .plainText, .utf8PlainText], isTargeted: nil) { providers in
            commitPanelDrop(providers: providers, beforeKey: nil, unhideZone: false)
        }
    }

    /// Unhide drop strip + settings gear (top-right).
    private var panelChrome: some View {
        HStack(spacing: 6) {
            unhideDropZone
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("Open Hidden Bar Settings")
            .accessibilityLabel("Open Settings")
        }
    }

    private var unhideDropZone: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 11, weight: .semibold))
            Text(unhideZoneTargeted ? "Release to show in menu bar" : "⌘-drag here to show in menu bar")
                .font(.system(size: 10, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(unhideZoneTargeted ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(unhideZoneTargeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    unhideZoneTargeted ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                    lineWidth: unhideZoneTargeted ? 1.5 : 1
                )
        )
        .animation(.easeOut(duration: 0.12), value: unhideZoneTargeted)
        .onDrop(
            of: [.text, .plainText, .utf8PlainText],
            isTargeted: $unhideZoneTargeted
        ) { providers in
            commitPanelDrop(providers: providers, beforeKey: nil, unhideZone: true)
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        if let status = model.statusMessage, !status.isEmpty {
            Text(status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else if model.isLoading {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Capturing icons…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        } else {
            Text("Drag to reorder · strip unhides · ⌘-drag bar→panel to hide · Esc closes")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    /// Multi-section grid: Hidden · Always hidden · Overflow (user items first).
    private var sectionedItemGrid: some View {
        let keys = model.filteredEntries.map(\.key)
        let insertIndex = resolvedInsertIndex(keys: keys)
        let shifts: [String: CGFloat] = {
            guard let draggingKey, let insertIndex else { return [:] }
            return RevealPanelDropPreview.horizontalShifts(
                orderedKeys: keys,
                draggedKey: draggingKey,
                insertIndex: insertIndex,
                gap: 20
            )
        }()
        let endActive = {
            guard let draggingKey, let insertIndex else { return false }
            return insertIndex >= keys.filter { $0 != draggingKey }.count
        }()
        let groups = model.groupedSections
        let showHeaders = groups.count > 1
            || groups.contains(where: { $0.section == .overflow })

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(groups.enumerated()), id: \.element.section) { _, group in
                if showHeaders {
                    sectionHeader(group.section, count: group.entries.count)
                }
                LazyVGrid(columns: gridColumns, spacing: 6) {
                    ForEach(group.entries) { entry in
                        let key = entry.key
                        let globalIndex = keys.firstIndex(of: key) ?? 0
                        let isDragSource = draggingKey == key
                        tile(entry.item, key: key, keys: keys)
                            .opacity(isDragSource ? 0.3 : 1)
                            .offset(x: shifts[key] ?? 0)
                            .zIndex(isDragSource ? 2 : 1)
                            .overlay(alignment: .leading) {
                                if let insertIndex, insertIndex == globalIndex, draggingKey != nil, !isDragSource {
                                    insertionCaret.offset(x: -11)
                                }
                            }
                    }
                }
            }
            LazyVGrid(columns: gridColumns, spacing: 6) {
                endOfListDropZone(active: endActive)
            }
        }
        .padding(.horizontal, 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: dropTargetKey)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: dropAfterTarget)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: draggingKey)
        .animation(.easeOut(duration: 0.12), value: hoveredKey)
    }

    private func sectionHeader(_ section: RevealPanelSection, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: section.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(section.title)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .foregroundStyle(section == .overflow ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(count) items")
    }

    /// Landing index from current drop-target state (before key, after key, or end).
    private func resolvedInsertIndex(keys: [String]) -> Int? {
        guard let draggingKey else { return nil }
        if dropTargetKey == RevealPanelDrag.endSentinel {
            return RevealPanelDropPreview.insertionIndex(
                orderedKeys: keys,
                draggedKey: draggingKey,
                beforeKey: nil
            )
        }
        guard let dropTargetKey else { return nil }
        if dropAfterTarget {
            let before = RevealPanelDropPreview.beforeKeyForTileDrop(
                orderedKeys: keys,
                draggedKey: draggingKey,
                targetKey: dropTargetKey,
                dropXInTile: 0.75,
                tileWidth: 1
            )
            return RevealPanelDropPreview.insertionIndex(
                orderedKeys: keys,
                draggedKey: draggingKey,
                beforeKey: before
            )
        }
        return RevealPanelDropPreview.insertionIndex(
            orderedKeys: keys,
            draggedKey: draggingKey,
            beforeKey: dropTargetKey
        )
    }

    private var insertionCaret: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: 3, height: 40)
            .shadow(color: Color.accentColor.opacity(0.45), radius: 3, y: 0)
            .transition(.opacity)
    }

    private func endOfListDropZone(active: Bool) -> some View {
        let fill = active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)
        let stroke = active ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08)
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(stroke, style: StrokeStyle(lineWidth: active ? 1.5 : 1, dash: active ? [] : [4, 3]))
            Group {
                if active {
                    insertionCaret
                } else {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .onDrop(
            of: [.text, .plainText, .utf8PlainText],
            isTargeted: Binding(
                get: { dropTargetKey == RevealPanelDrag.endSentinel },
                set: { hovering in
                    if hovering {
                        dropTargetKey = RevealPanelDrag.endSentinel
                        dropAfterTarget = false
                    } else if dropTargetKey == RevealPanelDrag.endSentinel {
                        dropTargetKey = nil
                    }
                }
            ),
            perform: { providers in
                commitPanelDrop(providers: providers, beforeKey: nil, unhideZone: false)
            }
        )
        .help("Drop here to move to the end (rightmost)")
    }

    private func tile(_ item: MenuBarCapturedItem, key: String, keys: [String]) -> some View {
        let hovering = hoveredKey == key
        let isDropTarget = dropTargetKey == key && draggingKey != nil && draggingKey != key
        return ZStack {
            itemLabel(item, highlighted: hovering || isDropTarget)
                // The transparent AppKit drag source below is the single
                // actionable accessibility element for the whole tile.
                .accessibilityHidden(true)
            // AppKit drag source — SwiftUI onTapGesture+onDrag is unreliable on
            // nonactivating panels and often never starts a drag session.
            RevealPanelTileDragSource(
                identityKey: key,
                displayName: item.item.displayName,
                onActivate: {
                    guard draggingKey == nil else { return }
                    onActivate(item.item.handle.windowID)
                },
                onDragBegan: {
                    draggingKey = key
                },
                onDragEnded: {
                    if draggingKey == key {
                        draggingKey = nil
                        dropTargetKey = nil
                        dropAfterTarget = false
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isDropTarget ? Color.accentColor.opacity(0.85) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(hovering && draggingKey == nil ? 1.03 : 1.0)
        .onHover { isHovering in
            hoveredKey = isHovering ? key : (hoveredKey == key ? nil : hoveredKey)
            if draggingKey != nil { return }
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("\(item.item.displayName) — click to open · drag to reorder")
        .onDrop(
            of: [.text, .plainText, .utf8PlainText],
            delegate: RevealPanelTileDropDelegate(
                targetKey: key,
                orderedKeys: keys,
                dropTargetKey: $dropTargetKey,
                dropAfterTarget: $dropAfterTarget,
                draggingKey: $draggingKey,
                onCommit: { draggedKey, beforeKey in
                    applyReorder(draggedKey: draggedKey, beforeKey: beforeKey)
                }
            )
        )
    }

    private func applyReorder(draggedKey: String, beforeKey: String?) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            guard let moved = model.reorder(draggedKey: draggedKey, beforeKey: beforeKey) else {
                return
            }
            onReorder(moved.dragged, moved.before)
        }
        dropTargetKey = nil
        dropAfterTarget = false
        draggingKey = nil
        unhideZoneTargeted = false
    }

    private func commitPanelDrop(
        providers: [NSItemProvider],
        beforeKey: String?,
        unhideZone: Bool
    ) -> Bool {
        guard let provider = providers.first else { return false }
        let typeIDs = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            "public.text",
        ]
        for typeID in typeIDs where provider.hasItemConformingToTypeIdentifier(typeID) {
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                let draggedKey = revealPanelParseDragKey(item)
                guard let draggedKey,
                      draggedKey != RevealPanelDrag.cancelSentinel,
                      !draggedKey.isEmpty
                else { return }
                DispatchQueue.main.async {
                    if unhideZone {
                        guard let windowID = model.items.first(where: {
                            $0.item.identity.key == draggedKey
                        })?.item.handle.windowID else {
                            draggingKey = nil
                            dropTargetKey = nil
                            return
                        }
                        onUnhide(windowID) { succeeded in
                            guard CrossBarDropPolicy.shouldRemovePanelItemAfterUnhide(
                                moveSucceeded: succeeded
                            ) else {
                                draggingKey = nil
                                dropTargetKey = nil
                                unhideZoneTargeted = false
                                return
                            }
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                model.items.removeAll { $0.item.handle.windowID == windowID }
                            }
                            draggingKey = nil
                            dropTargetKey = nil
                            unhideZoneTargeted = false
                        }
                        return
                    }
                    applyReorder(draggedKey: draggedKey, beforeKey: beforeKey)
                }
            }
            return true
        }
        return false
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 56, maximum: 100), spacing: 6),
            count: max(1, model.columnCount)
        )
    }

    @ViewBuilder
    private func itemLabel(_ item: MenuBarCapturedItem, highlighted: Bool = false) -> some View {
        VStack(spacing: 3) {
            iconView(for: item)
                .frame(height: 22)
            Text(MenuBarExtraLabelAssigner.visibleTileLabel(item.item.displayName))
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(highlighted ? .primary : .secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted ? Color.primary.opacity(0.14) : Color.white.opacity(0.07))
        )
    }

    @ViewBuilder
    private func iconView(for item: MenuBarCapturedItem) -> some View {
        if let image = item.image {
            Image(decorative: image, scale: CGFloat(item.scale))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else if let symbol = ControlCenterModules.symbolName(
            forModuleID: item.item.identity.moduleID,
            title: item.item.title
        ), item.item.identity.namespace.lowercased().contains("controlcenter")
            || item.item.ownerName.lowercased().contains("control center")
        {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
        } else if let nsImage = NSRunningApplication(processIdentifier: item.item.ownerPID)?.icon {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else if let symbol = ControlCenterModules.symbolName(
            forModuleID: item.item.identity.moduleID,
            title: item.item.title
        ) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

}

private enum RevealPanelDrag {
    /// Plain text payload of identity.key for ⌘-drag reorder.
    static let utType: UTType = .plainText
    static var cancelSentinel: String { CrossBarDropPolicy.cancelSentinel }
    /// Sentinel drop-target token for “append at end”.
    static let endSentinel = "__reveal_panel_drop_end__"
}

// MARK: - Drop delegate (left/right half → before/after)

private func revealPanelParseDragKey(_ item: NSSecureCoding?) -> String? {
    if let s = item as? String { return s }
    if let s = item as? NSString { return s as String }
    if let data = item as? Data {
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}

/// Uses drop location so the right half of a tile means “after” (including end).
private struct RevealPanelTileDropDelegate: DropDelegate {
    let targetKey: String
    let orderedKeys: [String]
    @Binding var dropTargetKey: String?
    @Binding var dropAfterTarget: Bool
    @Binding var draggingKey: String?
    let onCommit: (String, String?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text, .plainText, .utf8PlainText])
    }

    func dropEntered(info: DropInfo) {
        updateTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetKey == targetKey {
            dropTargetKey = nil
            dropAfterTarget = false
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        updateTarget(info: info)
        let useAfter = dropAfterTarget
        let providers = info.itemProviders(for: [.text, .plainText, .utf8PlainText])
        guard let provider = providers.first else { return false }
        let typeIDs = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            "public.text",
        ]
        for typeID in typeIDs where provider.hasItemConformingToTypeIdentifier(typeID) {
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                guard let draggedKey = revealPanelParseDragKey(item),
                      draggedKey != CrossBarDropPolicy.cancelSentinel,
                      !draggedKey.isEmpty
                else { return }
                let beforeKey: String? = {
                    if useAfter {
                        return RevealPanelDropPreview.beforeKeyForTileDrop(
                            orderedKeys: orderedKeys,
                            draggedKey: draggedKey,
                            targetKey: targetKey,
                            dropXInTile: 0.75,
                            tileWidth: 1
                        )
                    }
                    return targetKey
                }()
                DispatchQueue.main.async {
                    onCommit(draggedKey, beforeKey)
                }
            }
            return true
        }
        return false
    }

    private func updateTarget(info: DropInfo) {
        dropTargetKey = targetKey
        // Local X in the tile; ~half of a typical 70–90pt cell.
        dropAfterTarget = info.location.x > 36
    }
}

// MARK: - AppKit drag source (panel tiles)

/// Transparent hit target that starts an `NSDraggingSession` with the identity key.
/// Works from non-key / nonactivating panels where SwiftUI `onDrag` often never fires.
private struct RevealPanelTileDragSource: NSViewRepresentable {
    let identityKey: String
    let displayName: String
    let onActivate: () -> Void
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> RevealPanelTileDragNSView {
        let view = RevealPanelTileDragNSView()
        view.identityKey = identityKey
        view.displayName = displayName
        view.onActivate = onActivate
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: RevealPanelTileDragNSView, context: Context) {
        nsView.identityKey = identityKey
        nsView.displayName = displayName
        nsView.onActivate = onActivate
        nsView.onDragBegan = onDragBegan
        nsView.onDragEnded = onDragEnded
    }
}

private final class RevealPanelTileDragNSView: NSView, NSDraggingSource {
    var identityKey: String = ""
    var displayName: String = "" {
        didSet {
            setAccessibilityLabel(displayName)
            setAccessibilityHelp("\(displayName) — click to open; drag to reorder")
        }
    }
    var onActivate: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: NSPoint = .zero
    private var didStartDrag = false
    private let dragThreshold: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Fill the tile; participate in hit testing for mouseDown/drag.
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownEvent = event
        mouseDownPoint = event.locationInWindow
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent, !didStartDrag else { return }
        let loc = event.locationInWindow
        let distance = hypot(loc.x - mouseDownPoint.x, loc.y - mouseDownPoint.y)
        guard distance >= dragThreshold else { return }

        didStartDrag = true
        let pbItem = NSPasteboardItem()
        pbItem.setString(identityKey, forType: .string)
        // Also expose as plain text for SwiftUI DropDelegate type filters.
        pbItem.setString(identityKey, forType: NSPasteboard.PasteboardType(rawValue: "public.utf8-plain-text"))

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let preview = dragPreviewImage()
        dragItem.setDraggingFrame(bounds, contents: preview)

        onDragBegan?()
        beginDraggingSession(with: [dragItem], event: mouseDownEvent, source: self)
        self.mouseDownEvent = nil
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            didStartDrag = false
        }
        // Click (no drag session) → activate.
        if !didStartDrag, mouseDownEvent != nil {
            onActivate?()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragEnded?()
        didStartDrag = false
        mouseDownEvent = nil
    }

    private func dragPreviewImage() -> NSImage {
        let size = bounds.size.width > 1 ? bounds.size : NSSize(width: 72, height: 44)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
            let title = self.displayName as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let textSize = title.size(withAttributes: attrs)
            let origin = NSPoint(
                x: max(4, (rect.width - textSize.width) / 2),
                y: max(4, (rect.height - textSize.height) / 2)
            )
            title.draw(at: origin, withAttributes: attrs)
            return true
        }
        return image
    }
}

// MARK: - User menu-bar ⌘-drag policy (pure)

/// When the user holds ⌘ and drags in the system menu bar, Ice expands section
/// dividers so native rearrange works. We mirror that without mid-drag park restore
/// (synthetic moves would fight the user's drag).
enum UserMenuBarCommandDragPolicy {
    /// Soft-reveal markers (shrink spacer lengths) while ⌘-dragging in the band.
    static func shouldRevealMarkersForCommandDrag(
        isCommand: Bool,
        isInMenuBarBand: Bool
    ) -> Bool {
        isCommand && isInMenuBarBand
    }

    /// While a native menu-bar ⌘-drag is active, do not re-apply collapse geometry.
    static func shouldSuppressCollapseReapply(isUserDragging: Bool) -> Bool {
        isUserDragging
    }
}
