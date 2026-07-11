import AppKit
import SwiftUI

@MainActor
final class MenuItemHostingView: NSView {
    private static let defaultWidth: CGFloat = 260
    private static let maxMeasuredHeight: CGFloat = 160

    private let hostingController: NSHostingController<AnyView>

    override var allowsVibrancy: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        measuredSize(width: bounds.width > 0 ? bounds.width : Self.defaultWidth)
    }

    init(rootView: AnyView) {
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(frame: .zero)
        configureHostingView()
        frame = NSRect(origin: .zero, size: measuredSize(width: Self.defaultWidth))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hostingController.view.frame = bounds
    }

    private func configureHostingView() {
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.autoresizingMask = [.width, .height]
        hostingController.view.frame = bounds
        addSubview(hostingController.view)
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = [.minSize, .intrinsicContentSize]
        }
    }

    private func measuredSize(width: CGFloat) -> NSSize {
        let proposed = NSSize(width: width, height: Self.maxMeasuredHeight)
        let measured = hostingController.sizeThatFits(in: proposed)
        let height = min(max(28, measured.height), Self.maxMeasuredHeight)
        return NSSize(width: width, height: height)
    }
}

struct HiddenMenuSummaryRow: View {
    let profileName: String
    let toggleState: String
    let autoCollapseText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "menubar.rectangle")
                    .foregroundStyle(.secondary)
                Text("Nicos Hidden Bar")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(toggleState)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(profileName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Text(autoCollapseText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

struct HiddenMenuDiagnosticsRow: View {
    let markerStatus: String
    let geometryStatus: String
    let bridgeStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            diagnosticLine(icon: "arrow.left.and.right", label: "Markers", value: markerStatus)
            diagnosticLine(icon: "ruler", label: "Geometry", value: geometryStatus)
            diagnosticLine(icon: "bolt.horizontal", label: "Bridge", value: bridgeStatus)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func diagnosticLine(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
