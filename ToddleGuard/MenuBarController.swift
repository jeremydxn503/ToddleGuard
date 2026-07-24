import AppKit

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var observation: NSObjectProtocol?

    func install() {
        // squareLength keeps a stable, clickable footprint even if the symbol fails.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.title = "Toddle"
            button.image = Self.makeIcon(active: false)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.toolTip = "ToddleGuard"
            button.appearsDisabled = false
        }

        item.isVisible = true
        item.menu = buildMenu()

        observation = NotificationCenter.default.addObserver(
            forName: .toddleGuardStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        refresh()
    }

    func refresh() {
        let state = AppState.shared
        guard let button = statusItem?.button else { return }

        button.image = Self.makeIcon(active: state.isKidModeActive)
        // Always keep readable title so the item cannot become an invisible zero-width glyph.
        button.title = "Toddle"
        button.imagePosition = .imageLeading
        button.toolTip = state.isKidModeActive ? "ToddleGuard — Kid Mode ON" : "ToddleGuard — Kid Mode OFF"
        statusItem?.isVisible = true
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let state = AppState.shared
        let menu = NSMenu()

        let statusTitle: String
        if !state.isAccessibilityTrusted {
            statusTitle = "Status: Needs Accessibility"
        } else if state.isKidModeActive {
            statusTitle = "Status: Kid Mode ON"
        } else {
            statusTitle = "Status: Ready"
        }
        let statusRow = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())

        let toggleTitle = state.isKidModeActive ? "Turn Kid Mode Off" : "Turn Kid Mode On"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleKidMode(_:)), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        if !state.isAccessibilityTrusted {
            let access = NSMenuItem(title: "Grant Accessibility…", action: #selector(openAccessibility(_:)), keyEquivalent: "")
            access.target = self
            menu.addItem(access)

            let reveal = NSMenuItem(title: "Reveal Running App in Finder", action: #selector(revealApp(_:)), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)

            let copy = NSMenuItem(title: "Copy Running App Path", action: #selector(copyAppPath(_:)), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)

            let relaunch = NSMenuItem(title: "Quit & Relaunch", action: #selector(quitAndRelaunch(_:)), keyEquivalent: "")
            relaunch.target = self
            menu.addItem(relaunch)
        }

        menu.addItem(.separator())

        let unlockInfo = NSMenuItem(title: "Unlock: Caps Lock ×2 (3s)  or  ⌘⌥⇧K", action: nil, keyEquivalent: "")
        unlockInfo.isEnabled = false
        menu.addItem(unlockInfo)

        menu.addItem(.separator())

        let loginTitle = state.loginItem.isEnabled ? "Open at Login ✓" : "Open at Login"
        let login = NSMenuItem(title: loginTitle, action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        login.state = state.loginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let about = NSMenuItem(title: "About ToddleGuard…", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ToddleGuard", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleKidMode(_ sender: Any?) {
        AppState.shared.toggleKidMode()
        refresh()
    }

    @objc private func openAccessibility(_ sender: Any?) {
        AppState.shared.requestAccessibility()
        AppState.shared.showOnboarding = true
        refresh()
        NotificationCenter.default.post(name: .toddleGuardPresentOnboarding, object: nil)
    }

    @objc private func revealApp(_ sender: Any?) {
        AccessibilityPermission.revealInFinder()
    }

    @objc private func copyAppPath(_ sender: Any?) {
        AccessibilityPermission.copyPathToPasteboard()
    }

    @objc private func quitAndRelaunch(_ sender: Any?) {
        AccessibilityPermission.quitAndRelaunch()
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        AppState.shared.loginItem.toggle()
        refresh()
    }

    @objc private func showAbout(_ sender: Any?) {
        let trusted = AppState.shared.isAccessibilityTrusted
        let alert = NSAlert()
        alert.messageText = "ToddleGuard"
        alert.informativeText = """
        Kid-is-in-my-lap mode for your MacBook.

        When Kid Mode is on, keyboard and trackpad clicks/scrolls are blocked.

        Unlock while active:
        • Press Caps Lock twice within 3 seconds
        • Press ⌘⌥⇧K (Command-Option-Shift-K)

        Accessibility: \(trusted ? "trusted" : "NOT trusted for this process")
        Bundle: \(AccessibilityPermission.bundleIdentifier)
        Path: \(AccessibilityPermission.runningAppPath)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if !trusted {
            alert.addButton(withTitle: "Open Accessibility Settings")
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            AppState.shared.requestAccessibility()
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        if AppState.shared.isKidModeActive {
            AppState.shared.deactivateKidMode(reason: "quit")
        }
        NSApp.terminate(nil)
    }

    private static func makeIcon(active: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let name = active ? "lock.fill" : "lock.open"
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "ToddleGuard"),
           let configured = symbol.withSymbolConfiguration(config) {
            configured.isTemplate = true
            return configured
        }
        // Fallback: plain title-only is still usable; return a tiny template square.
        let fallback = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 1), xRadius: 2, yRadius: 2).fill()
            return true
        }
        fallback.isTemplate = true
        return fallback
    }
}
