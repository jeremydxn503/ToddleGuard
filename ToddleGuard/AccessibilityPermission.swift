import ApplicationServices
import AppKit
import Foundation

enum AccessibilityPermission {
    /// Live trust check for the *current* process. Prefer this over caching.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Path of the running .app bundle (what System Settings must list / enable).
    static var runningAppPath: String {
        Bundle.main.bundlePath
    }

    static var runningAppName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.jeremy.ToddleGuard"
    }

    /// Prompts the system Accessibility dialog when possible (call only on user action).
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: runningAppPath)])
    }

    static func copyPathToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(runningAppPath, forType: .string)
    }

    /// Quit and relaunch this exact bundle. Needed on some macOS versions after toggling Accessibility.
    static func quitAndRelaunch() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        // Fallback if openApplication callback is delayed: still quit shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.terminate(nil)
        }
    }
}
