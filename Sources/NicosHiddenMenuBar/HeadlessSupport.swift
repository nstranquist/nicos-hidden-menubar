import AppKit
import Darwin
import Foundation

/// Non-foregrounding launch support — the "headless native macOS app" recipe
/// shared with nicos-scratchpad and nicos-menubar. When
/// `NICOS_HIDDEN_MENUBAR_HEADLESS=1` the app runs as a Dock-less accessory that
/// never calls `activate(ignoringOtherApps:)` and parks any window it opens far
/// off-screen, so a smoke / launch-verify run never steals focus or pops a window
/// onto the user's display.
///
/// AppKit can't run truly windowless the way Chromium's `--headless=new` does — a
/// macOS app needs a window-server connection — so "headless" here means:
/// accessory policy + no activation + windows parked off-screen.
@MainActor
enum HiddenBarHeadless {
    static let isHeadless: Bool = {
        guard let value = ProcessInfo.processInfo.environment["NICOS_HIDDEN_MENUBAR_HEADLESS"] else { return false }
        return value == "1" || value.lowercased() == "true"
    }()

    private static let offscreenOrigin = NSPoint(x: -30_000, y: -30_000)

    /// Count of times we asked AppKit to foreground the app. Stays 0 in headless
    /// mode by construction — the self-test asserts on it so a future unguarded
    /// `activate(...)` is caught as a regression.
    static private(set) var foregroundActivationCount = 0

    static func activateUnlessHeadless() {
        guard !isHeadless else { return }
        foregroundActivationCount += 1
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Show the Dock icon only in a normal launch; headless stays `.accessory`.
    static func setRegularPolicyUnlessHeadless() {
        guard !isHeadless else { return }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    static func parkOffscreenIfHeadless(_ window: NSWindow) {
        guard isHeadless, window.frame.origin != offscreenOrigin else { return }
        window.setFrameOrigin(offscreenOrigin)
    }

    /// Order a window in. Headless keeps it off-screen and uses
    /// `orderFrontRegardless` (no focus, no app activation); normal path makes it
    /// key and front.
    static func surface(_ window: NSWindow) {
        if isHeadless {
            window.setFrameOrigin(offscreenOrigin)
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            // Preserve the original reuse-path fronting (front even if the app is
            // not yet active); harmless on a freshly created window too.
            window.orderFrontRegardless()
        }
    }

    private static var parkObserver: NSObjectProtocol?

    /// Park any window off-screen the instant AppKit displays it (headless only).
    static func installWindowParkingIfNeeded() {
        guard isHeadless, parkObserver == nil else { return }
        parkObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { parkOffscreenIfHeadless(window) }
        }
    }
}

struct HiddenBarHeadlessReport: Codable {
    struct Step: Codable {
        let name: String
        let ok: Bool
        let detail: String
        var skipped: Bool = false
    }
    let ok: Bool
    let steps: [Step]
}

/// Launch-verify that proves the app boots and opens its preferences window (the
/// real foregrounding path) without stealing focus. Mirrors nicos-scratchpad's
/// `headless-no-foreground` + `window-screenshot` assertions. Triggered by
/// `NICOS_HIDDEN_MENUBAR_SELFTEST=1`; writes a report to
/// `NICOS_HIDDEN_MENUBAR_SELFTEST_REPORT` and exits.
@MainActor
enum HiddenBarHeadlessSelfTest {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["NICOS_HIDDEN_MENUBAR_SELFTEST"] == "1"
    }

    static func runAndExit(
        compositionReport: @escaping () -> MenuBarServiceCompositionReport,
        openWindow: @escaping () -> Void,
        window: @escaping () -> NSWindow?
    ) {
        HiddenBarHeadless.installWindowParkingIfNeeded()
        Task { @MainActor in
            var steps: [HiddenBarHeadlessReport.Step] = []
            func record(_ name: String, _ ok: Bool, _ detail: String, skipped: Bool = false) {
                steps.append(.init(name: name, ok: ok, detail: detail, skipped: skipped))
            }

            record("launch", true, "reached applicationDidFinishLaunching")

            let composition = compositionReport()
            record("service-composition", composition.ok, composition.detail)

            openWindow()
            try? await Task.sleep(nanoseconds: 400_000_000)
            let win = window()
            record("window-opened", win != nil, win.map { "opened \($0.title.isEmpty ? "window" : $0.title)" } ?? "no window created")

            let noForeground = HiddenBarHeadless.foregroundActivationCount == 0
                && !NSApp.isActive
                && NSApp.activationPolicy() == .accessory
            record(
                "headless-no-foreground",
                noForeground,
                "activationRequests=\(HiddenBarHeadless.foregroundActivationCount) isActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)"
            )

            if let win,
               let shotPath = ProcessInfo.processInfo.environment["NICOS_HIDDEN_MENUBAR_SELFTEST_SCREENSHOT"],
               !shotPath.isEmpty {
                let shot = captureWindow(win, to: shotPath)
                record("window-screenshot", shot.ok, shot.detail)
            }

            let ok = steps.allSatisfy { $0.ok || $0.skipped }
            writeReport(HiddenBarHeadlessReport(ok: ok, steps: steps))
            try? await Task.sleep(nanoseconds: 150_000_000)
            NSApp.terminate(nil)
            Darwin.exit(ok ? 0 : 1)
        }
    }

    private static func writeReport(_ report: HiddenBarHeadlessReport) {
        guard let path = ProcessInfo.processInfo.environment["NICOS_HIDDEN_MENUBAR_SELFTEST_REPORT"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(report).write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("selftest report write failed: \(error.localizedDescription)\n".utf8))
        }
    }

    /// Render only this app's content view, so it works while the window is
    /// parked off-screen, needs no capture permission, and cannot include the
    /// user's desktop.
    private static func captureWindow(_ window: NSWindow, to path: String) -> (ok: Bool, detail: String) {
        guard window.windowNumber > 0 else { return (false, "window not ordered in") }
        guard let contentView = window.contentView else {
            return (false, "window has no content view")
        }
        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return (false, "window content has empty bounds")
        }
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return (false, "could not allocate window bitmap")
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return (false, "png encode failed")
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return (true, url.path)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
