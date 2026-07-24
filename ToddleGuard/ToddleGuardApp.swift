import AppKit
import SwiftUI

@main
struct ToddleGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Minimal Settings scene keeps the SwiftUI App lifecycle alive for this
        // accessory (LSUIElement) agent. The real UI is the AppKit status item.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private let onboarding = OnboardingWindowController()
    private var statusObserver: NSObjectProtocol?
    private var presentObserver: NSObjectProtocol?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we stay a menu-bar agent (no Dock icon). Info.plist also sets LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        _ = AppState.shared
        menuBar.install()

        statusObserver = NotificationCenter.default.addObserver(
            forName: .toddleGuardStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.menuBar.refresh()
                self?.syncOnboarding()
            }
        }

        presentObserver = NotificationCenter.default.addObserver(
            forName: .toddleGuardPresentOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onboarding.showIfNeeded(state: AppState.shared, force: true)
            }
        }

        // Refresh menu / onboarding while Settings is open (trust can flip without a click).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                AppState.shared.refreshAccessibility()
                self.menuBar.refresh()
                self.syncOnboarding()
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }

        // Defer first onboarding presentation until after the run loop settles.
        DispatchQueue.main.async { [weak self] in
            self?.syncOnboarding(forceIfNeeded: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshAccessibility()
        menuBar.refresh()
        syncOnboarding()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        if let presentObserver {
            NotificationCenter.default.removeObserver(presentObserver)
        }
    }

    private func syncOnboarding(forceIfNeeded: Bool = false) {
        let state = AppState.shared
        if state.isAccessibilityTrusted && state.showOnboarding {
            // Keep window up so the user can click Continue (green state).
            onboarding.showIfNeeded(state: state, force: false)
            onboarding.update(state: state)
            return
        }
        if !state.isAccessibilityTrusted {
            onboarding.showIfNeeded(state: state, force: forceIfNeeded)
            onboarding.update(state: state)
            return
        }
        // Trusted and user dismissed setup.
        if !state.showOnboarding {
            onboarding.showIfNeeded(state: state)
        } else {
            onboarding.update(state: state)
        }
    }
}
