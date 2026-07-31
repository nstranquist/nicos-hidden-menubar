import AppKit
import ApplicationServices
import Foundation
import Security

/// Registers Nicos Hidden Bar with macOS TCC so it appears under
/// System Settings → Privacy & Security → Accessibility (and Screen Recording).
///
/// Apps only show up in those lists after they touch the corresponding APIs.
/// Calling this on launch / from Settings is what creates the toggle row.
///
/// **Ad-hoc reinstalls** change the code signature (CDHash). System Settings can
/// still show an older “Nicos Hidden Bar” row as ON while `AXIsProcessTrusted()`
/// is false for *this* binary — TCC’s stored code requirement no longer matches.
/// Always re-check trust live; never assume the Settings toggle matches runtime.
enum PrivacyPermissions {
    static let accessibilityBundleID = "com.nstranquist.nicos-hidden-menubar"

    static var isAccessibilityTrusted: Bool {
        // Prefer the options API with prompt=false — same answer as AXIsProcessTrusted
        // but ensures TCC has seen this process identity.
        // String key avoids Swift 6 concurrency complaints on the global CFString.
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var hasScreenRecording: Bool {
        MenuBarItemImageCapture.hasScreenRecordingPermission()
    }

    /// Short CDHash of the running executable (for diagnostics / mismatch copy).
    static var runningCodeDirectoryHash: String? {
        guard let url = Bundle.main.executableURL ?? Bundle.main.bundleURL as URL? else {
            return nil
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any]
        else { return nil }
        // cdhashes is an array of Data; take the first sha256/sha1 blob as hex.
        if let hashes = info["cdhashes"] as? [Data], let first = hashes.first {
            return first.map { String(format: "%02x", $0) }.joined()
        }
        if let hash = info["cdhash"] as? Data {
            return hash.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }

    /// Ensure TCC knows about this process for Accessibility.
    /// - Parameter prompt: When true, macOS may show the system permission dialog.
    ///   Prefer **false** for automatic paths so we do not re-prompt every click.
    @discardableResult
    static func enrollAccessibility(prompt: Bool) -> Bool {
        // Touch the Accessibility API so TCC creates a row even before trust.
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let hash = runningCodeDirectoryHash ?? "unknown"
        HiddenMenuBarTelemetry.appLifecycle.info(
            "Accessibility enroll prompt=\(prompt, privacy: .public) trusted=\(trusted, privacy: .public) cdhash=\(hash, privacy: .public)"
        )
        return trusted
    }

    /// Opens System Settings to the Accessibility privacy pane (macOS 13–15+).
    @discardableResult
    static func openAccessibilitySettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                HiddenMenuBarTelemetry.appLifecycle.info("Opened Accessibility settings via \(raw, privacy: .public)")
                return true
            }
        }
        return false
    }

    @discardableResult
    static func openScreenRecordingSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }

    /// Clears this app’s Accessibility TCC row so the *current* binary can re-enroll.
    /// Required after ad-hoc re-sign when Settings still shows ON for a stale CDHash.
    @discardableResult
    static func resetAccessibilityTCCEntry() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", accessibilityBundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            HiddenMenuBarTelemetry.appLifecycle.info(
                "tccutil reset Accessibility status=\(process.terminationStatus, privacy: .public)"
            )
            return ok
        } catch {
            HiddenMenuBarTelemetry.appLifecycle.error(
                "tccutil reset Accessibility failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Soft path for automatic collapse/reject: enroll without system modal,
    /// optionally open Settings once. Does **not** call `prompt: true`.
    @MainActor
    static func guideToAccessibilitySettingsIfNeeded(openSettings: Bool) {
        _ = enrollAccessibility(prompt: false)
        guard openSettings, !isAccessibilityTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            _ = openAccessibilitySettings()
        }
    }

    /// Explicit user action (menu / Settings button): may show system prompt.
    @MainActor
    static func requestAccessibilityAccessAndShowSettings() {
        let trusted = enrollAccessibility(prompt: true)
        if trusted {
            HiddenMenuBarTelemetry.appLifecycle.info("Accessibility already trusted after explicit enroll")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            _ = openAccessibilitySettings()
        }
    }

    /// User-facing recovery when Settings shows ON but runtime trust is false
    /// (stale ad-hoc CDHash). Resets TCC, re-touches AX APIs, opens Settings.
    @MainActor
    static func resetAndReRequestAccessibilityAccess() {
        _ = resetAccessibilityTCCEntry()
        // Brief delay so tccd drops the old row before we re-enroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            _ = enrollAccessibility(prompt: true)
            _ = openAccessibilitySettings()
        }
    }

    @MainActor
    static func requestScreenRecordingAccessAndShowSettings() {
        _ = MenuBarItemImageCapture.requestScreenRecordingPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            _ = openScreenRecordingSettings()
        }
    }

    /// Copy for UI when trust is false despite user believing they enabled it.
    static var untrustedUserHint: String {
        "Accessibility looks ON in Settings, but this build is not trusted. Ad-hoc reinstalls change the code signature — remove every “Nicos Hidden Bar” row under Privacy → Accessibility (or use Reset & re-grant), turn the new row ON, then click the chevron again."
    }

    static var untrustedSettingsDetail: String {
        """
        macOS decides trust with AXIsProcessTrusted(), not the Settings toggle alone. \
        Each make install re-signs the app (ad-hoc CDHash changes). An older ON row can \
        stay listed while this running binary is denied. Fix: remove all Nicos Hidden Bar \
        Accessibility entries (or Reset & re-grant below), relaunch, enable the new row.
        """
    }
}
