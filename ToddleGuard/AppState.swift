import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isKidModeActive = false
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var eventTapRunning = false
    /// True when the user has toggled Accessibility in Settings but this process still reads untrusted
    /// (common with ad-hoc rebuilds / until quit+relaunch).
    @Published private(set) var needsRelaunchForAccessibility = false
    @Published var showOnboarding = false

    let loginItem = LoginItemManager()
    private let eventTap = EventTapManager()
    private var cancellables = Set<AnyCancellable>()
    private var activationObservers: [NSObjectProtocol] = []

    private init() {
        eventTap.onUnlock = { [weak self] method in
            Task { @MainActor in
                self?.deactivateKidMode(reason: method)
            }
        }
        eventTap.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                self?.eventTapRunning = running
            }
            .store(in: &cancellables)

        refreshAccessibility()
        if !isAccessibilityTrusted {
            showOnboarding = true
        } else {
            startEventTapIfNeeded()
        }

        let center = NotificationCenter.default
        let becomeActive = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibility()
            }
        }
        let workspaceActive = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == Bundle.main.bundleIdentifier
            else { return }
            Task { @MainActor in
                self?.refreshAccessibility()
            }
        }
        activationObservers = [becomeActive, workspaceActive]
    }

    deinit {
        for observer in activationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refreshAccessibility() {
        let trusted = AccessibilityPermission.isTrusted()
        let wasTrusted = isAccessibilityTrusted
        let previousNeedsRelaunch = needsRelaunchForAccessibility

        isAccessibilityTrusted = trusted
        // While untrusted, guide the user through stale TCC rows + quit/relaunch.
        needsRelaunchForAccessibility = !trusted

        let changed = trusted != wasTrusted || needsRelaunchForAccessibility != previousNeedsRelaunch

        if trusted {
            startEventTapIfNeeded()
        } else {
            if isKidModeActive {
                isKidModeActive = false
            }
            eventTap.stop()
        }

        if changed {
            NotificationCenter.default.post(name: .toddleGuardStatusDidChange, object: nil)
        }
    }

    func requestAccessibility() {
        // Prompt once per explicit user action, then open Settings. Do not prompt from the timer.
        _ = AccessibilityPermission.requestTrust()
        AccessibilityPermission.openSystemSettings()
        showOnboarding = true
        refreshAccessibility()
        NotificationCenter.default.post(name: .toddleGuardPresentOnboarding, object: nil)
    }

    func toggleKidMode() {
        if isKidModeActive {
            deactivateKidMode(reason: "menu")
        } else {
            activateKidMode()
        }
    }

    func activateKidMode() {
        refreshAccessibility()
        guard isAccessibilityTrusted else {
            showOnboarding = true
            requestAccessibility()
            return
        }
        startEventTapIfNeeded()
        guard eventTap.isRunning else {
            // AX can report trusted while the tap still fails (stale identity until relaunch).
            showOnboarding = true
            needsRelaunchForAccessibility = true
            NotificationCenter.default.post(name: .toddleGuardPresentOnboarding, object: nil)
            return
        }
        isKidModeActive = true
        eventTap.kidModeActive = true
        updateMenuBarAppearance()
    }

    func deactivateKidMode(reason: String) {
        isKidModeActive = false
        eventTap.kidModeActive = false
        updateMenuBarAppearance()
        if reason != "menu" {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startEventTapIfNeeded() {
        guard isAccessibilityTrusted else { return }
        if !eventTap.isRunning {
            eventTap.start()
        }
    }

    private func updateMenuBarAppearance() {
        NotificationCenter.default.post(name: .toddleGuardStatusDidChange, object: nil)
    }
}

extension Notification.Name {
    static let toddleGuardStatusDidChange = Notification.Name("ToddleGuardStatusDidChange")
    static let toddleGuardPresentOnboarding = Notification.Name("ToddleGuardPresentOnboarding")
}
