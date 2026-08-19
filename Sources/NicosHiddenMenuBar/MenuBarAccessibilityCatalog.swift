import ApplicationServices
import CoreGraphics
import Foundation

/// Reads AX extras-menu titles so image-only Control Center modules get real
/// names (Wi‑Fi, Focus, …) instead of repeating "Control Center".
enum MenuBarAccessibilityCatalog {
    struct LabeledFrame: Sendable {
        var title: String
        var frame: CGRect
        var pid: pid_t
    }

    /// Best-effort labels for status items belonging to `pids`.
    static func labeledFrames(forPIDs pids: Set<pid_t>) -> [LabeledFrame] {
        guard PrivacyPermissions.isAccessibilityTrusted else { return [] }
        var results: [LabeledFrame] = []
        for pid in pids {
            results.append(contentsOf: extrasItems(forPID: pid))
        }
        return results
    }

    /// Horizontal proximity used by `bestTitle` and the batch assigner.
    static let defaultMaxDistance: CGFloat = 28

    static func isWithinProximity(
        extra: CGRect,
        label: CGRect,
        maxDistance: CGFloat = defaultMaxDistance
    ) -> Bool {
        guard label != .null, label.width > 0 else { return false }
        return abs(extra.midX - label.midX) < max(extra.width, label.width, maxDistance)
    }

    /// Match a window frame to the nearest AX extras item on the same PID.
    static func bestTitle(
        for frame: CGRect,
        pid: pid_t,
        among labels: [LabeledFrame],
        maxDistance: CGFloat = defaultMaxDistance
    ) -> String? {
        let candidates = labels.filter { $0.pid == pid && !$0.title.isEmpty }
        guard !candidates.isEmpty else { return nil }

        // Prefer geometrically matched labels; fall back to title-only AX rows.
        let withGeometry = candidates.filter { $0.frame != .null && $0.frame.width > 0 }
        if !withGeometry.isEmpty {
            let best = withGeometry.min { lhs, rhs in
                abs(lhs.frame.midX - frame.midX) < abs(rhs.frame.midX - frame.midX)
            }
            guard let best, isWithinProximity(extra: frame, label: best.frame, maxDistance: maxDistance) else {
                return nil
            }
            return best.title
        }

        // No geometry: only safe when a single labeled extras item exists for the PID.
        if candidates.count == 1 {
            return candidates[0].title
        }
        return nil
    }

    private static func extrasItems(forPID pid: pid_t) -> [LabeledFrame] {
        let app = AXUIElementCreateApplication(pid)
        guard let extras = copyElement(app, attribute: "AXExtrasMenuBar") else {
            return []
        }
        guard let children = copyArray(extras, attribute: kAXChildrenAttribute as String) else {
            return []
        }

        var items: [LabeledFrame] = []
        for child in children {
            let title = firstNonEmpty(
                copyString(child, attribute: kAXDescriptionAttribute as String),
                copyString(child, attribute: kAXTitleAttribute as String),
                copyString(child, attribute: "AXIdentifier")
            )
            guard let title, !title.isEmpty else { continue }
            guard let origin = copyPoint(child, attribute: kAXPositionAttribute as String),
                let size = copySize(child, attribute: kAXSizeAttribute as String)
            else {
                // Title without geometry still useful when only one unlabeled peer.
                items.append(LabeledFrame(title: title, frame: .null, pid: pid))
                continue
            }
            let frame = CGRect(origin: origin, size: size)
            items.append(LabeledFrame(title: title, frame: frame, pid: pid))
        }
        return items
    }

    // MARK: - AX helpers

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func copyArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let array = value as? [AXUIElement]
        else {
            return nil
        }
        return array
    }

    private static func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let string = value as? String
        else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func copyPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let axValue = value
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func copySize(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let axValue = value
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty { return value }
        }
        return nil
    }
}
