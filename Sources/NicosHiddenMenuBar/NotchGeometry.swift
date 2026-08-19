import CoreGraphics
import Foundation

#if canImport(AppKit)
    import AppKit
#endif

/// Pure geometry for the split menu-bar bands on notched MacBooks.
///
/// On a notched built-in display the usable status-item strips are the system
/// auxiliary top-left and top-right areas. The gap between them is the camera
/// housing. Used as one input to **overflow** detection (items that don't fit
/// the usable status strip — not only items under the camera).
struct NotchBandGeometry: Equatable, Sendable {
    /// Right edge of the left usable menu-bar band (screen coords).
    var leftUsableMaxX: Double
    /// Left edge of the right usable menu-bar band (screen coords).
    var rightUsableMinX: Double
    /// Right edge of the right usable status strip (when known).
    var rightUsableMaxX: Double?
    /// Full display horizontal span (optional; used for off-band checks).
    var screenMinX: Double?
    var screenMaxX: Double?

    /// True when there is a measurable dead zone between the usable bands.
    var hasDeadZone: Bool {
        rightUsableMinX > leftUsableMaxX + Self.minimumDeadZoneWidth
    }

    var deadZoneMinX: Double { leftUsableMaxX }
    var deadZoneMaxX: Double { rightUsableMinX }

    static let minimumDeadZoneWidth: Double = 8

    enum Placement: String, Equatable, Sendable {
        case leftUsable
        case underNotch
        case rightUsable
        case outside
    }

    static func fromAuxiliaryAreas(
        left: CGRect?,
        right: CGRect?,
        screenMinX: Double? = nil,
        screenMaxX: Double? = nil
    ) -> NotchBandGeometry? {
        guard let left, let right else { return nil }
        guard left.width > 1, right.width > 1 else { return nil }
        let geometry = NotchBandGeometry(
            leftUsableMaxX: Double(left.maxX),
            rightUsableMinX: Double(right.minX),
            rightUsableMaxX: Double(right.maxX),
            screenMinX: screenMinX,
            screenMaxX: screenMaxX
        )
        return geometry.hasDeadZone ? geometry : nil
    }

    static func estimatedCentered(
        screenMinX: Double,
        screenMaxX: Double,
        fractionOfWidth: Double = 0.11
    ) -> NotchBandGeometry? {
        let width = screenMaxX - screenMinX
        guard width > 100 else { return nil }
        let gap = max(Self.minimumDeadZoneWidth, width * fractionOfWidth)
        let mid = (screenMinX + screenMaxX) / 2
        return NotchBandGeometry(
            leftUsableMaxX: mid - gap / 2,
            rightUsableMinX: mid + gap / 2,
            rightUsableMaxX: screenMaxX,
            screenMinX: screenMinX,
            screenMaxX: screenMaxX
        )
    }

    func placement(itemMinX: Double, itemMaxX: Double, itemMidX: Double) -> Placement {
        if let screenMinX, itemMaxX < screenMinX - 1 { return .outside }
        if let screenMaxX, itemMinX > screenMaxX + 1 { return .outside }

        if intersectsDeadZone(itemMinX: itemMinX, itemMaxX: itemMaxX) {
            return .underNotch
        }
        if itemMidX < deadZoneMinX {
            return .leftUsable
        }
        if itemMidX >= deadZoneMaxX {
            return .rightUsable
        }
        return .underNotch
    }

    func intersectsDeadZone(itemMinX: Double, itemMaxX: Double) -> Bool {
        guard hasDeadZone else { return false }
        let expand: Double = 6
        let gapMin = deadZoneMinX - expand
        let gapMax = deadZoneMaxX + expand
        guard gapMax > gapMin else { return false }
        return itemMinX < gapMax && itemMaxX > gapMin
    }

    func isUnderNotch(itemMinX: Double, itemMaxX: Double, itemMidX: Double) -> Bool {
        placement(itemMinX: itemMinX, itemMaxX: itemMaxX, itemMidX: itemMidX) == .underNotch
    }
}

// MARK: - Overflow (cut-off status items)

/// Detects **overflowed** menu extras: registered status items that would fit on
/// a wider menu bar but are cut off on this display (past the visible right edge,
/// under the camera gap, or otherwise outside the usable right status strip).
///
/// This is what the reveal panel’s **Overflow** section lists — not only geometric
/// “under the camera” hits.
struct MenuBarOverflowLayout: Equatable, Sendable {
    /// End of left usable band (app menus). Status items live to the right of this.
    var leftUsableMaxX: Double?
    /// Start of the usable right status strip.
    var rightUsableMinX: Double?
    /// End of the usable right status strip.
    var rightUsableMaxX: Double?
    /// Visible desktop right edge (Cocoa).
    var visibleMaxX: Double
    var screenMinX: Double
    var screenMaxX: Double

    /// Slop when testing full containment in the usable right strip.
    static let containmentSlop: Double = 3

    /// True when this frame is a status-side item that is **not fully visible**
    /// in the usable right menu-bar strip (or is past the visible right edge).
    func isOverflow(
        itemMinX: Double,
        itemMaxX: Double,
        itemMidX: Double,
        isOnScreen: Bool = true
    ) -> Bool {
        // Past the visible right edge → classic overflow / spacer-park.
        if itemMinX >= visibleMaxX - 2 {
            return true
        }
        if itemMinX >= screenMaxX - 1 {
            return true
        }

        // App-menu territory (left of notch / left of status strip) — not overflow.
        if let leftMax = leftUsableMaxX, itemMidX < leftMax - 4 {
            return false
        }

        // Have a measured right status strip (notched MacBook, etc.).
        if let rMin = rightUsableMinX, let rMax = rightUsableMaxX, rMax > rMin + 8 {
            let fullyInRightStrip =
                itemMinX >= rMin - Self.containmentSlop
                && itemMaxX <= rMax + Self.containmentSlop
            if fullyInRightStrip {
                return false
            }
            // Status-side item not fully inside the usable strip → cut off / under gap.
            if let leftMax = leftUsableMaxX {
                return itemMidX >= leftMax - 4
            }
            // No left band: treat anything not fully in right strip as overflow.
            return true
        }

        // Non-notch / no aux rects: only past-edge or off-screen counts.
        if !isOnScreen, itemMidX >= screenMinX, itemMidX <= screenMaxX + 80 {
            return true
        }
        return false
    }
}

// MARK: - Panel sections

/// Where a reveal-panel tile belongs (display order top → bottom).
/// User hidden-lane items first; overflow (cut-off extras) last.
enum RevealPanelSection: String, CaseIterable, Equatable, Sendable, Comparable {
    case hidden
    case alwaysHidden
    /// Cut-off / overflowed status items (renamed from geometric “under notch”).
    case overflow

    var sortIndex: Int {
        switch self {
        case .hidden: return 0
        case .alwaysHidden: return 1
        case .overflow: return 2
        }
    }

    var title: String {
        switch self {
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always hidden"
        case .overflow: return "Overflow"
        }
    }

    var systemImage: String {
        switch self {
        case .hidden: return "rectangle.on.rectangle.angled"
        case .alwaysHidden: return "eye.slash"
        case .overflow: return "arrow.left.and.line.vertical.and.arrow.right"
        }
    }

    static func < (lhs: RevealPanelSection, rhs: RevealPanelSection) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}

/// Pure classifier for panel membership + section. Shared by tests and the panel model.
enum RevealPanelClassifier {
    /// Decide whether an item belongs in the panel and which section.
    ///
    /// Priority:
    /// 1. **Overflow** — cut off / under camera gap (even if left of the hide separator)
    /// 2. Parked / hide lanes — intentional Hidden Bar hide list
    /// 3. none (fully visible, right of markers)
    static func section(
        itemMinX: Double,
        itemMaxX: Double,
        itemMidX: Double,
        laneBounds: MenuBarLaneBounds,
        notch: NotchBandGeometry?,
        overflow: MenuBarOverflowLayout?,
        notchSupportEnabled: Bool,
        isParked: Bool,
        isOnScreen: Bool = true
    ) -> RevealPanelSection? {
        // Cut-off extras first — otherwise "left of primary separator" steals them
        // into Hidden and the Overflow section stays empty.
        if notchSupportEnabled {
            if let overflow,
                overflow.isOverflow(
                    itemMinX: itemMinX,
                    itemMaxX: itemMaxX,
                    itemMidX: itemMidX,
                    isOnScreen: isOnScreen
                )
            {
                return .overflow
            }
            if let notch,
                notch.isUnderNotch(itemMinX: itemMinX, itemMaxX: itemMaxX, itemMidX: itemMidX)
            {
                return .overflow
            }
        }

        if isParked {
            return .hidden
        }

        switch laneBounds.lane(forItemMidX: itemMidX) {
        case .alwaysHidden:
            return .alwaysHidden
        case .hidden:
            return .hidden
        case .visible, .control:
            if laneBounds.isRevealCandidate(
                itemMinX: itemMinX,
                itemMaxX: itemMaxX,
                itemMidX: itemMidX
            ) {
                return .hidden
            }
            return nil
        }
    }
}

/// Drop system chrome / our own markers so the panel never shows a useless
/// “Menubar” tile (full-width menubar windows that only look under-notch because
/// their frame spans the camera housing).
enum RevealPanelItemQuality {
    static let maxStatusItemWidth: Double = 96
    static let minStatusItemWidth: Double = 6
    static let minStatusItemHeight: Double = 8

    static let junkOwnerNames: Set<String> = [
        "menubar",
        "systemuiserver",
        "window server",
        "windowserver",
        "loginwindow",
    ]

    static let junkNamespaces: Set<String> = [
        "menubar",
        "com.apple.systemuiserver",
        "com.apple.WindowServer",
        "com.nstranquist.nicos-hidden-menubar",
    ]

    static func isUsablePanelItem(
        ownerName: String,
        namespace: String,
        displayName: String,
        frameWidth: Double,
        frameHeight: Double,
        itemMidX: Double? = nil,
        leftUsableMaxX: Double? = nil
    ) -> Bool {
        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ns = namespace.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if junkOwnerNames.contains(owner) { return false }
        if junkNamespaces.contains(ns) { return false }
        if ns.contains("nicos-hidden-menubar") { return false }
        // Full-width menubar chrome only (not real extras).
        if frameWidth > maxStatusItemWidth { return false }
        if frameWidth < minStatusItemWidth { return false }
        if frameHeight > 0, frameHeight < minStatusItemHeight { return false }
        if label == "menubar" || label == "window server" {
            return false
        }
        // Left usable band = app menus / ghosts — not status extras.
        if let mid = itemMidX, let leftMax = leftUsableMaxX, mid < leftMax - 4 {
            return false
        }
        // pid-0 overflow frames under the gap are OK (unknown owner).
        return true
    }
}

#if canImport(AppKit)
    extension NotchBandGeometry {
        @MainActor
        static func forScreen(_ screen: NSScreen) -> NotchBandGeometry? {
            let minX = Double(screen.frame.minX)
            let maxX = Double(screen.frame.maxX)
            if let fromAux = fromAuxiliaryAreas(
                left: screen.auxiliaryTopLeftArea,
                right: screen.auxiliaryTopRightArea,
                screenMinX: minX,
                screenMaxX: maxX
            ) {
                return fromAux
            }
            guard MenuBarItemScanner.screenHasNotch(screen) else { return nil }
            return estimatedCentered(screenMinX: minX, screenMaxX: maxX)
        }
    }

    extension MenuBarOverflowLayout {
        /// Live screen → overflow layout (always available; richer on notched displays).
        @MainActor
        static func forScreen(_ screen: NSScreen) -> MenuBarOverflowLayout {
            let minX = Double(screen.frame.minX)
            let maxX = Double(screen.frame.maxX)
            let visibleMaxX = Double(screen.visibleFrame.maxX)
            let left = screen.auxiliaryTopLeftArea
            let right = screen.auxiliaryTopRightArea
            if let left, let right, left.width > 1, right.width > 1 {
                return MenuBarOverflowLayout(
                    leftUsableMaxX: Double(left.maxX),
                    rightUsableMinX: Double(right.minX),
                    rightUsableMaxX: Double(right.maxX),
                    visibleMaxX: visibleMaxX,
                    screenMinX: minX,
                    screenMaxX: maxX
                )
            }
            return MenuBarOverflowLayout(
                leftUsableMaxX: nil,
                rightUsableMinX: nil,
                rightUsableMaxX: nil,
                visibleMaxX: visibleMaxX,
                screenMinX: minX,
                screenMaxX: maxX
            )
        }
    }
#endif
