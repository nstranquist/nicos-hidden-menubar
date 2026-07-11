import CoreGraphics
import Foundation

public enum MarkerGeometry {
    public static let minCollapseWidth: Double = 32.0
    public static let maxCollapseWidth: Double = 10000.0

    public struct Inputs {
        public var toggleX: Double?
        public var primaryX: Double?
        public var secondaryX: Double?
        public var alwaysHiddenEnabled: Bool

        public init(toggleX: Double?, primaryX: Double?, secondaryX: Double?, alwaysHiddenEnabled: Bool) {
            self.toggleX = toggleX
            self.primaryX = primaryX
            self.secondaryX = secondaryX
            self.alwaysHiddenEnabled = alwaysHiddenEnabled
        }
    }

    public static func isValidOrder(toggleX: Double?, primaryX: Double?, secondaryX: Double?, alwaysHiddenEnabled: Bool) -> Bool {
        guard let toggleX, let primaryX else {
            return false
        }

        if alwaysHiddenEnabled {
            guard let secondaryX else {
                return false
            }
            return secondaryX < primaryX && primaryX < toggleX
        }

        return primaryX < toggleX
    }

    public static func collapsedWidth(visibleFrameMaxX: Double?, primaryMinX: Double?) -> Double? {
        guard let visibleFrameMaxX, let primaryMinX else {
            return nil
        }
        let rawWidth = visibleFrameMaxX - primaryMinX
        guard rawWidth > 0 else {
            return nil
        }
        return max(minCollapseWidth, min(rawWidth, maxCollapseWidth))
    }

    /// Recover the divider's compact-position x coordinate even while its
    /// status item is acting as an inflated spacer. NSStatusItem keeps the
    /// item's right edge anchored as its length changes, so using the raw
    /// `frame.minX` on a second collapse compounds the previous width.
    public static func compactMinX(
        currentMinX: Double?,
        currentWidth: Double?,
        compactWidth: Double
    ) -> Double? {
        guard let currentMinX, let currentWidth,
              currentWidth >= 0, compactWidth >= 0
        else {
            return nil
        }
        return currentMinX + max(0, currentWidth - compactWidth)
    }

    public static func isReadyStatusItemAnchor(
        _ anchorX: Double?,
        screenMinX: Double,
        screenMidX: Double,
        screenMaxX: Double
    ) -> Bool {
        guard let anchorX else { return false }
        // Menu extras occupy the right half of each display. During launch,
        // AppKit can briefly report a small placeholder x that is technically
        // inside the screen but is not the restored menu-extra position yet.
        return anchorX > screenMidX && anchorX < screenMaxX - 1 && anchorX >= screenMinX
    }

    static func shouldUseCompactFallback(
        revealsBelowMenuBar: Bool,
        collapseHidItems: Bool?
    ) -> Bool {
        revealsBelowMenuBar && collapseHidItems == false
    }

    public static func preferredVisibleFrameMaxX(
        primaryMinX: Double?,
        preferredVisibleFrameMaxX: [Double?],
        fallbackVisibleFrameMaxX: [Double]
    ) -> Double? {
        guard let primaryMinX else {
            return nil
        }

        for candidate in preferredVisibleFrameMaxX {
            guard let candidate else {
                continue
            }
            if collapsedWidth(visibleFrameMaxX: candidate, primaryMinX: primaryMinX) != nil {
                return candidate
            }
        }

        return fallbackVisibleFrameMaxX
            .filter { collapsedWidth(visibleFrameMaxX: $0, primaryMinX: primaryMinX) != nil }
            .max()
    }

    public static func menuBarBand(frame: CGRect, visibleFrame: CGRect) -> CGRect {
        let menuBarHeight = max(0, frame.maxY - visibleFrame.maxY)
        guard menuBarHeight > 0 else {
            return .null
        }
        return CGRect(
            x: frame.minX,
            y: visibleFrame.maxY,
            width: frame.width,
            height: menuBarHeight
        )
    }

    public static func isPointInMenuBarBand(_ point: CGPoint, frame: CGRect, visibleFrame: CGRect) -> Bool {
        menuBarBand(frame: frame, visibleFrame: visibleFrame).contains(point)
    }
}
