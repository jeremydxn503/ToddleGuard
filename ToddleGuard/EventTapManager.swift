import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

/// System-wide CGEvent tap that blocks keyboard and pointing input while Kid Mode is active,
/// while still recognizing unlock sequences.
final class EventTapManager: ObservableObject {
    @Published private(set) var isRunning = false

    /// Set from the main actor when Kid Mode toggles.
    var kidModeActive: Bool = false

    /// Called on a background run-loop thread when an unlock sequence is detected.
    var onUnlock: ((String) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var runLoop: CFRunLoop?

    private var lastCapsLockAt: CFAbsoluteTime = 0
    private let capsLockWindow: CFAbsoluteTime = 3.0
    private let capsLockDebounce: CFAbsoluteTime = 0.12

    private let lock = NSLock()

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard eventTap == nil else { return }

        let mask = Self.eventMask
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DispatchQueue.main.async { self.isRunning = false }
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            let rl = CFRunLoopGetCurrent()
            self.runLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "ToddleGuard.EventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()

        DispatchQueue.main.async { self.isRunning = true }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        if let rl = runLoop {
            CFRunLoopStop(rl)
        }
        if let source = runLoopSource {
            if let rl = runLoop {
                CFRunLoopRemoveSource(rl, source, .commonModes)
            }
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        tapThread = nil
        kidModeActive = false
        lastCapsLockAt = 0
        DispatchQueue.main.async { self.isRunning = false }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard kidModeActive else {
            return Unmanaged.passUnretained(event)
        }

        if isUnlockCapsLock(event: event, type: type) {
            // Swallow Caps Lock so the system LED/state does not toggle during unlock attempts.
            return nil
        }

        if isUnlockHotkey(event: event, type: type) {
            return nil
        }

        // Keep the menu bar usable so the status item can turn Kid Mode off.
        if isPointingEvent(type), isMenuBarClick() {
            return Unmanaged.passUnretained(event)
        }

        if shouldBlock(type: type) {
            return nil
        }

        // Allow other flagsChanged (modifiers) through so ⌘⌥⇧K still sees correct flags.
        return Unmanaged.passUnretained(event)
    }

    private func isPointingEvent(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .scrollWheel:
            return true
        default:
            return false
        }
    }

    private func isMenuBarClick() -> Bool {
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let frame = screen.frame
            let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 22)
            let barMinY = frame.maxY - menuBarHeight
            if loc.x >= frame.minX, loc.x <= frame.maxX, loc.y >= barMinY, loc.y <= frame.maxY {
                return true
            }
        }
        return false
    }

    private func isUnlockCapsLock(event: CGEvent, type: CGEventType) -> Bool {
        // Caps Lock arrives as flagsChanged with keycode kVK_CapsLock (57).
        guard type == .flagsChanged else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == CGKeyCode(kVK_CapsLock) else { return false }

        let now = CFAbsoluteTimeGetCurrent()
        // Ignore bounce/duplicate flagsChanged from a single physical press.
        if lastCapsLockAt > 0, now - lastCapsLockAt < capsLockDebounce {
            return true
        }
        if lastCapsLockAt > 0, now - lastCapsLockAt <= capsLockWindow {
            lastCapsLockAt = 0
            notifyUnlock("caps-lock")
            return true
        }
        lastCapsLockAt = now
        return true
    }

    private func isUnlockHotkey(event: CGEvent, type: CGEventType) -> Bool {
        guard type == .keyDown else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == CGKeyCode(kVK_ANSI_K) else { return false }

        let flags = event.flags
        let need: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift]
        let hasRequired = flags.intersection(need) == need
        let hasControl = flags.contains(.maskControl)
        guard hasRequired, !hasControl else { return false }

        lastCapsLockAt = 0
        notifyUnlock("hotkey")
        return true
    }

    private func notifyUnlock(_ method: String) {
        // Deactivate immediately so subsequent events are not swallowed.
        kidModeActive = false
        let callback = onUnlock
        DispatchQueue.main.async {
            callback?(method)
        }
    }

    private func shouldBlock(type: CGEventType) -> Bool {
        switch type {
        case .keyDown, .keyUp:
            return true
        case .flagsChanged:
            // Non-Caps-Lock modifier changes are allowed (handled above returns early for Caps Lock).
            return false
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .scrollWheel, .tabletPointer, .tabletProximity:
            return true
        case .mouseMoved:
            // Cursor can move; clicks and scrolls are blocked.
            return false
        default:
            return false
        }
    }

    private static var eventMask: CGEventMask {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
            .tabletPointer, .tabletProximity,
            .tapDisabledByTimeout, .tapDisabledByUserInput,
        ]
        return types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }
}
