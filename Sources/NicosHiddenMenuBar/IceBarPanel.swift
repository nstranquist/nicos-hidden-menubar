import AppKit
import Combine
import SwiftUI

/// A floating, borderless panel that displays the currently hidden menu bar
/// items — Ice's "IceBar" idea. Because hidden items live here instead of being
/// reflowed back into the menu bar, the notch can never swallow them. This is
/// the real fix for cramped notched displays.
@MainActor
final class IceBarPanel {
    private var panel: NSPanel?
    private let model = IceBarModel()
    private let onActivate: (CGWindowID) -> Void
    private var reloadTask: Task<Void, Never>?

    init(onActivate: @escaping (CGWindowID) -> Void) {
        self.onActivate = onActivate
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(near anchorMinX: Double?, on screen: NSScreen) {
        if isVisible {
            hide()
        } else {
            show(near: anchorMinX, on: screen)
        }
    }

    func show(near anchorMinX: Double?, on screen: NSScreen) {
        let panel = panel ?? makePanel()
        self.panel = panel

        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            await model.reload(on: screen, leftOfX: anchorMinX)
            guard !Task.isCancelled else { return }
            positionPanel(panel, near: anchorMinX, on: screen)
            panel.orderFrontRegardless()
        }
    }

    func refreshIfVisible(near anchorMinX: Double?, on screen: NSScreen) {
        guard isVisible else { return }
        show(near: anchorMinX, on: screen)
    }

    func hide() {
        reloadTask?.cancel()
        reloadTask = nil
        panel?.orderOut(nil)
        model.clear()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = IceBarView(model: model) { [weak self] windowID in
            self?.onActivate(windowID)
            self?.hide()
        }
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func positionPanel(_ panel: NSPanel, near anchorMinX: Double?, on screen: NSScreen) {
        let layout = IceBarLayout.calculate(
            itemCount: model.items.count,
            visibleFrame: screen.visibleFrame
        )
        model.columnCount = layout.columnCount
        let menuBarBottom = screen.visibleFrame.maxY
        let y = max(screen.visibleFrame.minY + 6, menuBarBottom - layout.height - 6)
        let anchor = CGFloat(anchorMinX ?? Double(screen.frame.midX))
        var x = anchor - layout.width / 2
        x = max(screen.visibleFrame.minX + 6, min(x, screen.visibleFrame.maxX - layout.width - 6))
        panel.setFrame(NSRect(x: x, y: y, width: layout.width, height: layout.height), display: true)
    }
}

struct IceBarLayout: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let columnCount: Int

    static func calculate(itemCount: Int, visibleFrame: CGRect) -> IceBarLayout {
        let horizontalMargin: CGFloat = 12
        let verticalMargin: CGFloat = 24
        let itemWidth: CGFloat = 72
        let rowHeight: CGFloat = 38
        let chromeWidth: CGFloat = 20
        let chromeHeight: CGFloat = 16
        let searchHeight: CGFloat = itemCount > 8 ? 30 : 0
        let maxWidth = max(160, visibleFrame.width - horizontalMargin)
        let maxColumns = max(1, min(8, Int((maxWidth - chromeWidth) / itemWidth)))
        let columnCount = min(maxColumns, max(1, itemCount))
        let rowCount = max(1, Int(ceil(Double(max(1, itemCount)) / Double(columnCount))))
        let width = min(maxWidth, max(160, CGFloat(columnCount) * itemWidth + chromeWidth))
        let naturalHeight = CGFloat(rowCount) * rowHeight + chromeHeight + searchHeight
        let maxHeight = max(80, min(360, visibleFrame.height - verticalMargin))
        return IceBarLayout(
            width: width,
            height: min(maxHeight, max(54, naturalHeight)),
            columnCount: columnCount
        )
    }
}

/// Observable model holding the captured hidden items for the IceBar.
@MainActor
final class IceBarModel: ObservableObject {
    @Published var items: [MenuBarItemImageCapture.CapturedItem] = []
    @Published var usesImages = false
    @Published var query: String = ""
    @Published var columnCount = 1

    /// Items after applying the search filter.
    var filteredItems: [MenuBarItemImageCapture.CapturedItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.displayName.lowercased().contains(q) }
    }

    func reload(on screen: NSScreen, leftOfX: Double?) async {
        let detailed = IceBarModel.hiddenCandidates(
            MenuBarItemScanner.detailedItems(screen: screen),
            leftOfX: leftOfX
        )
        let captured = await MenuBarItemImageCapture.capture(items: detailed, on: screen)
        guard !Task.isCancelled else { return }
        self.usesImages = captured.contains { $0.image != nil }
        self.items = captured
    }

    func clear() {
        items.removeAll(keepingCapacity: false)
        usesImages = false
        query = ""
        columnCount = 1
    }

    /// Hidden items are those positioned left of our toggle (the divider the hide
    /// mechanism controls), excluding immovable system items. With no anchor we
    /// fall back to all movable items. Pure so it's unit-tested.
    nonisolated static func hiddenCandidates(_ items: [MenuBarWindowInfo], leftOfX: Double?) -> [MenuBarWindowInfo] {
        items.filter { item in
            guard !item.info.isLikelyImmovable else { return false }
            guard let leftOfX else { return true }
            return Double(item.frame.maxX) <= leftOfX
        }
    }
}

private struct IceBarView: View {
    @ObservedObject var model: IceBarModel
    let onActivate: (CGWindowID) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if model.items.count > 8 {
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
            if model.filteredItems.isEmpty {
                Text(model.items.isEmpty ? "No hidden items" : "No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        ForEach(model.filteredItems, id: \.windowID) { item in
                            Button {
                                onActivate(item.windowID)
                            } label: {
                                itemLabel(item)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.plain)
                            .help(item.displayName)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 44, maximum: 120), spacing: 6),
            count: max(1, model.columnCount)
        )
    }

    @ViewBuilder
    private func itemLabel(_ item: MenuBarItemImageCapture.CapturedItem) -> some View {
        if let image = item.image {
            Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 22)
                .padding(.horizontal, 2)
        } else {
            Text(shortLabel(item.displayName))
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
        }
    }

    private func shortLabel(_ name: String) -> String {
        let head = name.split(separator: "—").first.map(String.init) ?? name
        return head.trimmingCharacters(in: .whitespaces)
    }
}
