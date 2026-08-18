import CoreGraphics
import Foundation

/// Pure extra-title assignment used by reveal-panel discovery (Hidden and Overflow).
///
/// One AX extras scan is I/O; this assigner only pairs already-fetched labels.
/// Proximity wins; leftover same-PID extras with a matching leftover-label
/// count are paired left-to-right. Ambiguous leftovers stay untitled (ordinal
/// on the display name) instead of guessing.
enum MenuBarExtraLabelAssigner {
    struct Extra: Equatable, Sendable {
        var pid: pid_t
        var frame: CGRect
        var windowTitle: String
        var ownerName: String
        var appName: String?
    }

    struct Assignment: Equatable, Sendable {
        var title: String
        var displayName: String
    }

    static func assign(
        extras: [Extra],
        axLabels: [MenuBarAccessibilityCatalog.LabeledFrame]
    ) -> [Assignment] {
        let titles = assignedTitles(extras: extras, axLabels: axLabels)
        return displayNames(extras: extras, titles: titles)
    }

    /// Extra titles after proximity + leftover 1:1 pairing. Parallel to `extras`.
    static func assignedTitles(
        extras: [Extra],
        axLabels: [MenuBarAccessibilityCatalog.LabeledFrame]
    ) -> [String] {
        var titles = extras.map { extra in
            extra.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var usedLabel = Array(repeating: false, count: axLabels.count)

        // Phase 1: proximity (greedy left-to-right so the same label is not reused).
        let proximityOrder = extras.indices.sorted { extras[$0].frame.midX < extras[$1].frame.midX }
        for index in proximityOrder {
            guard titles[index].isEmpty else { continue }
            let extra = extras[index]
            var bestIndex: Int?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (labelIndex, label) in axLabels.enumerated() {
                guard !usedLabel[labelIndex] else { continue }
                guard label.pid == extra.pid, !label.title.isEmpty else { continue }
                guard MenuBarAccessibilityCatalog.isWithinProximity(extra: extra.frame, label: label.frame) else {
                    continue
                }
                let distance = abs(label.frame.midX - extra.frame.midX)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = labelIndex
                }
            }
            if let bestIndex {
                titles[index] = axLabels[bestIndex].title
                usedLabel[bestIndex] = true
            }
        }

        // Phase 2: leftover bijection per PID. Requires ≥2 extras in the group
        // so a lone far extra does not claim a lone far label (existing matcher).
        let extrasByPID = Dictionary(grouping: extras.indices) { extras[$0].pid }
        for (pid, memberIndices) in extrasByPID {
            let leftoverExtras = memberIndices
                .filter { titles[$0].isEmpty }
                .sorted { extras[$0].frame.midX < extras[$1].frame.midX }
            let leftoverLabels = axLabels.indices.filter { labelIndex in
                !usedLabel[labelIndex]
                    && axLabels[labelIndex].pid == pid
                    && !axLabels[labelIndex].title.isEmpty
            }

            let geometric = leftoverLabels.filter {
                axLabels[$0].frame != .null && axLabels[$0].frame.width > 0
            }
            let geometryLess = leftoverLabels.filter {
                axLabels[$0].frame == .null || axLabels[$0].frame.width <= 0
            }

            if memberIndices.count >= 2,
               leftoverExtras.count == geometric.count,
               leftoverExtras.count >= 1
            {
                let orderedLabels = geometric.sorted {
                    axLabels[$0].frame.midX < axLabels[$1].frame.midX
                }
                for (extraIndex, labelIndex) in zip(leftoverExtras, orderedLabels) {
                    titles[extraIndex] = axLabels[labelIndex].title
                    usedLabel[labelIndex] = true
                }
                continue
            }

            // Single geometry-less label: same fallback as `bestTitle`.
            if leftoverExtras.count == 1,
               leftoverExtras.count == geometryLess.count,
               geometric.isEmpty
            {
                titles[leftoverExtras[0]] = axLabels[geometryLess[0]].title
                usedLabel[geometryLess[0]] = true
            }
        }

        return titles
    }

    static func displayNames(extras: [Extra], titles: [String]) -> [Assignment] {
        precondition(extras.count == titles.count)
        var untitledOrdinal: [Int: Int] = [:]
        var untitledCount: [Int: Int] = [:]
        for (index, extra) in extras.enumerated() where titles[index].isEmpty {
            untitledCount[Int(extra.pid), default: 0] += 1
        }
        var seenUntitled: [Int: Int] = [:]
        let untitledLTR = extras.indices
            .filter { titles[$0].isEmpty }
            .sorted { extras[$0].frame.midX < extras[$1].frame.midX }
        for index in untitledLTR {
            let pid = Int(extras[index].pid)
            let next = (seenUntitled[pid] ?? 0) + 1
            seenUntitled[pid] = next
            untitledOrdinal[index] = next
        }

        return extras.indices.map { index in
            let extra = extras[index]
            let title = titles[index]
            let display = displayName(
                appName: extra.appName,
                ownerName: extra.ownerName,
                title: title,
                untitledOrdinal: untitledOrdinal[index],
                untitledCount: untitledCount[Int(extra.pid)] ?? 0
            )
            return Assignment(title: title, displayName: display)
        }
    }

    static func displayName(
        appName: String?,
        ownerName: String,
        title: String,
        untitledOrdinal: Int?,
        untitledCount: Int
    ) -> String {
        let app = sanitizedName(appName) ?? sanitizedName(ownerName)
        if !title.isEmpty {
            if let app, app != title {
                return "\(app) — \(title)"
            }
            return title
        }
        if let app {
            if untitledCount > 1, let untitledOrdinal {
                return "\(app) \(untitledOrdinal)"
            }
            return app
        }
        if untitledCount > 1, let untitledOrdinal {
            return "Menu extra \(untitledOrdinal)"
        }
        return "Menu extra"
    }

    /// Tile caption after the assigner. Prefer the extra title after " — "
    /// so same-app siblings stay distinct in the narrow grid. Untitled
    /// ordinals and single-word names pass through.
    static func visibleTileLabel(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: "—") else { return trimmed }
        let extra = trimmed[separator.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return extra.isEmpty ? trimmed : extra
    }

    private static func sanitizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.lowercased() == "menubar" { return nil }
        return trimmed
    }
}
