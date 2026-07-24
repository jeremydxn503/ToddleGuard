import AppKit

/// Pure AppKit onboarding window. Avoids NSHostingView constraint-update crashes
/// that abort the process when SwiftUI is hosted in an accessory-app NSWindow.
@MainActor
final class OnboardingWindowController: NSObject {
    private var window: NSWindow?
    private var trustedIndicator: NSView?
    private var statusLabel: NSTextField?
    private var guidanceLabel: NSTextField?
    private var pathLabel: NSTextField?
    private var continueButton: NSButton?
    private var relaunchButton: NSButton?
    private var isVisible = false
    /// After the user closes Setup, don't auto-pop it again until explicitly requested.
    private var suppressUntilExplicitShow = false

    func showIfNeeded(state: AppState, force: Bool = false) {
        if force {
            suppressUntilExplicitShow = false
            state.showOnboarding = true
        }
        guard state.showOnboarding || force else {
            dismiss()
            return
        }
        // Keep showing while Accessibility is missing, even if showOnboarding was cleared earlier.
        if !state.isAccessibilityTrusted {
            state.showOnboarding = true
        }
        guard state.showOnboarding else {
            dismiss()
            return
        }
        if suppressUntilExplicitShow && !force {
            return
        }
        if window == nil {
            window = makeWindow()
        }
        update(state: state)
        guard !isVisible else { return }
        isVisible = true
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(state: AppState) {
        let trusted = state.isAccessibilityTrusted
        trustedIndicator?.layer?.backgroundColor = (trusted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        statusLabel?.stringValue = trusted
            ? "Accessibility is granted for this process"
            : "Accessibility is not trusted for this running copy"
        pathLabel?.stringValue = AccessibilityPermission.runningAppPath
        continueButton?.isHidden = !trusted
        relaunchButton?.isHidden = trusted

        if trusted && state.eventTapRunning {
            guidanceLabel?.stringValue = "You’re set. Click Continue, then use the menu bar lock to turn Kid Mode on."
        } else if trusted && !state.eventTapRunning {
            guidanceLabel?.stringValue = "macOS reports Accessibility as trusted, but the input tap did not start. Click Quit & Relaunch, then try Kid Mode again."
            relaunchButton?.isHidden = false
            continueButton?.isHidden = true
        } else if state.needsRelaunchForAccessibility {
            guidanceLabel?.stringValue = """
            System Settings can show ToddleGuard as enabled while this process is still untrusted (common after a rebuild; ad-hoc signing changes the code identity).

            1. Open Accessibility settings and remove every ToddleGuard / “Toddle” entry.
            2. Click +, press ⌘⇧G, paste the path below, and add this exact app.
            3. Turn the toggle ON, then click Quit & Relaunch.
            """
        } else {
            guidanceLabel?.stringValue = "Enable this exact app in System Settings → Privacy & Security → Accessibility, then return here."
        }
    }

    private func dismiss() {
        isVisible = false
        window?.orderOut(nil)
        window?.close()
        window = nil
        clearUIRefs()
    }

    private func clearUIRefs() {
        trustedIndicator = nil
        statusLabel = nil
        guidanceLabel = nil
        pathLabel = nil
        continueButton = nil
        relaunchButton = nil
    }

    private func makeWindow() -> NSWindow {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))

        let icon = NSImageView(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
        icon.image = symbol
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)

        let title = makeLabel("Welcome to ToddleGuard", font: .systemFont(ofSize: 18, weight: .semibold))
        let subtitle = makeLabel(
            "Kid Mode blocks keyboard and trackpad input so a toddler on your lap can’t wreck your session.",
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor,
            wrapping: true
        )

        let unlockBox = makeGroup(
            title: "How unlock works",
            lines: [
                "Caps Lock twice within 3 seconds",
                "⌘ ⌥ ⇧ K (Command-Option-Shift-K)",
            ]
        )

        let accessTitle = makeLabel("Accessibility required", font: .systemFont(ofSize: 13, weight: .semibold))
        let accessBody = makeLabel(
            "macOS only allows ToddleGuard to filter input after you grant Accessibility for this exact running app.",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            wrapping: true
        )

        let indicator = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 5
        indicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
        trustedIndicator = indicator

        let status = makeLabel("Accessibility is not trusted for this running copy", font: .systemFont(ofSize: 13, weight: .medium))
        statusLabel = status

        let pathTitle = makeLabel("Enable this app path:", font: .systemFont(ofSize: 11, weight: .semibold))
        let path = makeLabel(AccessibilityPermission.runningAppPath, font: .monospacedSystemFont(ofSize: 11, weight: .regular), wrapping: true)
        path.textColor = .labelColor
        pathLabel = path

        let guidance = makeLabel(
            "Enable this exact app in System Settings → Privacy & Security → Accessibility, then return here.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor,
            wrapping: true
        )
        guidanceLabel = guidance

        let openSettings = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings(_:)))
        openSettings.bezelStyle = .rounded
        openSettings.keyEquivalent = "\r"
        openSettings.translatesAutoresizingMaskIntoConstraints = false

        let reveal = NSButton(title: "Reveal in Finder", target: self, action: #selector(revealInFinder(_:)))
        reveal.bezelStyle = .rounded
        reveal.translatesAutoresizingMaskIntoConstraints = false

        let copyPath = NSButton(title: "Copy Path", target: self, action: #selector(copyPath(_:)))
        copyPath.bezelStyle = .rounded
        copyPath.translatesAutoresizingMaskIntoConstraints = false

        let checkAgain = NSButton(title: "Check Again", target: self, action: #selector(checkAgain(_:)))
        checkAgain.bezelStyle = .rounded
        checkAgain.translatesAutoresizingMaskIntoConstraints = false

        let relaunch = NSButton(title: "Quit & Relaunch", target: self, action: #selector(quitAndRelaunch(_:)))
        relaunch.bezelStyle = .rounded
        relaunch.translatesAutoresizingMaskIntoConstraints = false
        relaunchButton = relaunch

        let cont = NSButton(title: "Continue", target: self, action: #selector(continueTapped(_:)))
        cont.bezelStyle = .rounded
        cont.translatesAutoresizingMaskIntoConstraints = false
        cont.isHidden = true
        continueButton = cont

        let tip = makeLabel(
            "Tip: after rebuilds, remove old ToddleGuard rows in Accessibility and add this path again. Ad-hoc Debug builds change code identity each compile.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor,
            wrapping: true
        )

        let titleColumn = NSStackView(views: [title, subtitle])
        titleColumn.orientation = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = 4

        let header = NSStackView(views: [icon, titleColumn])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = NSStackView(views: [indicator, status])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let pathButtons = NSStackView(views: [reveal, copyPath])
        pathButtons.orientation = .horizontal
        pathButtons.spacing = 8

        let actionButtons = NSStackView(views: [openSettings, checkAgain, relaunch, cont])
        actionButtons.orientation = .horizontal
        actionButtons.spacing = 8

        let accessStack = NSStackView(views: [accessTitle, accessBody, statusRow, pathTitle, path, pathButtons, guidance, actionButtons])
        accessStack.orientation = .vertical
        accessStack.alignment = .leading
        accessStack.spacing = 8
        accessStack.translatesAutoresizingMaskIntoConstraints = false
        accessStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        accessStack.wantsLayer = true
        accessStack.layer?.cornerRadius = 8
        accessStack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let root = NSStackView(views: [header, unlockBox, accessStack, tip])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 10),
            indicator.heightAnchor.constraint(equalToConstant: 10),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            unlockBox.widthAnchor.constraint(equalTo: root.widthAnchor),
            accessStack.widthAnchor.constraint(equalTo: root.widthAnchor),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -52),
            tip.widthAnchor.constraint(equalTo: root.widthAnchor),
            accessBody.widthAnchor.constraint(equalTo: accessStack.widthAnchor, constant: -24),
            path.widthAnchor.constraint(equalTo: accessStack.widthAnchor, constant: -24),
            guidance.widthAnchor.constraint(equalTo: accessStack.widthAnchor, constant: -24),
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "ToddleGuard Setup"
        win.contentView = content
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        return win
    }

    private func makeLabel(
        _ string: String,
        font: NSFont,
        color: NSColor = .labelColor,
        wrapping: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = font
        field.textColor = color
        field.translatesAutoresizingMaskIntoConstraints = false
        if wrapping {
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return field
    }

    private func makeGroup(title: String, lines: [String]) -> NSView {
        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 13, weight: .semibold))
        let rowViews: [NSView] = lines.map { line in
            makeLabel("•  \(line)", font: .systemFont(ofSize: 13))
        }
        let stack = NSStackView(views: [titleLabel] + rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        return stack
    }

    @objc private func openSettings(_ sender: Any?) {
        AppState.shared.requestAccessibility()
        update(state: AppState.shared)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        AccessibilityPermission.revealInFinder()
    }

    @objc private func copyPath(_ sender: Any?) {
        AccessibilityPermission.copyPathToPasteboard()
    }

    @objc private func checkAgain(_ sender: Any?) {
        AppState.shared.refreshAccessibility()
        update(state: AppState.shared)
        if AppState.shared.isAccessibilityTrusted {
            // Ensure Continue is visible immediately.
            continueButton?.isHidden = false
        }
    }

    @objc private func quitAndRelaunch(_ sender: Any?) {
        AccessibilityPermission.quitAndRelaunch()
    }

    @objc private func continueTapped(_ sender: Any?) {
        AppState.shared.showOnboarding = false
        dismiss()
    }
}

extension OnboardingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isVisible = false
        suppressUntilExplicitShow = true
        // Keep showOnboarding true so menu "Grant Accessibility…" can reopen via force.
        window = nil
        clearUIRefs()
    }
}
